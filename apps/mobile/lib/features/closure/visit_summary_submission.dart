import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/contracts.dart';
import '../../core/networking/api_client.dart';

/// One encrypted metadata transaction holds every immutable confirmation. New
/// edits never replace an older queued submission, including after a restart.
class VisitSummaryOutbox {
  VisitSummaryOutbox({
    required this.read,
    required this.write,
    required this.send,
    required this.assertAccess,
  });
  static const storageKey = 'visit-summary-outbox-v1';
  final Future<Object?> Function(String) read;
  final Future<void> Function(String, Object) write;
  final Future<Json> Function(Json) send;
  final Future<void> Function() assertAccess;
  Future<void> _tail = Future.value();
  bool _flushing = false;
  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _tail.catchError((_) {}).then((_) async {
      await assertAccess();
      return run();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<List<Json>> _load() async => ((await read(storageKey) as List?) ?? [])
      .map((e) => Map<String, dynamic>.from(e as Json))
      .toList();
  Future<List<Json>> list() => _serial(_load);
  Future<Json> enqueue({
    required String reportId,
    required String? workOrderId,
    required Answers values,
    required Json sources,
  }) => _serial(() async {
    final entries = await _load(), encoded = encodeAnswers(values);
    bool matches(Json payload) =>
        payload['workOrderId'] == workOrderId &&
        jsonEncode(payload['values']) == jsonEncode(encoded) &&
        jsonEncode(payload['sources']) == jsonEncode(sources);
    final latest = entries
        .where((e) => (e['payload'] as Json)['clientReportId'] == reportId)
        .lastOrNull;
    if (latest != null && matches(latest['payload'] as Json)) return latest;
    final legacy = latest == null
        ? await read('closure-summary-submission:$reportId') as Json?
        : null;
    final old = legacy?['payload'] as Json?;
    final payload = old != null && matches(old)
        ? old
        : <String, dynamic>{
            'clientSummaryId': const Uuid().v4(),
            'clientReportId': reportId,
            'workOrderId': workOrderId,
            'confirmedAt': DateTime.now().toUtc().toIso8601String(),
            'values': encoded,
            'sources': sources,
          };
    final entry =
        jsonDecode(
              jsonEncode({
                'id': payload['clientSummaryId'],
                'payload': payload,
                'status': legacy?['receipt'] != null ? 'received' : 'waiting',
                if (legacy?['receipt'] != null) 'receipt': legacy!['receipt'],
              }),
            )
            as Json;
    await assertAccess();
    await write(storageKey, [...entries, entry]);
    return entry;
  });
  Future<void> _update(String id, Json changes) => _serial(() async {
    final entries = await _load();
    await assertAccess();
    await write(storageKey, [
      for (final e in entries)
        if (e['id'] == id) {...e, ...changes} else e,
    ]);
  });
  Future<bool> flush({bool manual = false}) async {
    if (_flushing) return false;
    _flushing = true;
    try {
      final entries = await list();
      for (final entry in entries) {
        if (entry['status'] == 'received' ||
            entry['status'] == 'attention' && !manual) {
          continue;
        }
        try {
          await assertAccess();
          final receipt = await send(entry['payload'] as Json);
          await assertAccess();
          await _update(entry['id'] as String, {
            'status': 'received',
            'receipt': receipt,
            'error': null,
          });
        } catch (e) {
          await assertAccess();
          final blocked = e is ServiceFailure && !e.retryable;
          await _update(entry['id'] as String, {
            'status': blocked ? 'attention' : 'waiting',
            'error': blocked
                ? e.toString()
                : 'Waiting for a connection. Your summary is saved on this device.',
          });
          if (!blocked) return false;
        }
      }
      return !(await list()).any((e) => e['status'] != 'received');
    } finally {
      _flushing = false;
    }
  }
}
