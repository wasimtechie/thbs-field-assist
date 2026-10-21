import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../core/contracts.dart';
import '../../core/networking/api_client.dart';
import '../../core/persistence/report_repository.dart';

class CollaborationState {
  const CollaborationState({
    this.notifications = const [],
    this.conversations = const [],
    this.teams = const [],
    this.pending = const [],
    this.visits = const [],
    this.unread = 0,
    this.unreadMessages = 0,
    this.syncedAt,
  });
  final List<Json> notifications, conversations, teams, pending, visits;
  final int unread, unreadMessages;
  final DateTime? syncedAt;
  factory CollaborationState.fromJson(Json j) => CollaborationState(
    notifications: (j['notifications'] as List? ?? []).cast<Json>(),
    conversations: (j['conversations'] as List? ?? []).cast<Json>(),
    teams: (j['teams'] as List? ?? []).cast<Json>(),
    visits: (j['visits'] as List? ?? []).cast<Json>(),
    pending: (j['pending'] as List? ?? []).cast<Json>(),
    unread: j['unread'] as int? ?? 0,
    unreadMessages: j['unreadMessages'] as int? ?? 0,
    syncedAt: DateTime.tryParse(j['syncedAt'] as String? ?? ''),
  );
  Json toJson() => {
    'notifications': notifications,
    'conversations': conversations,
    'teams': teams,
    'pending': pending,
    'visits': visits,
    'unread': unread,
    'unreadMessages': unreadMessages,
    'syncedAt': syncedAt?.toUtc().toIso8601String(),
  };
  CollaborationState copy({
    List<Json>? notifications,
    List<Json>? conversations,
    List<Json>? teams,
    List<Json>? pending,
    List<Json>? visits,
    int? unread,
    int? unreadMessages,
    DateTime? syncedAt,
  }) => CollaborationState(
    notifications: notifications ?? this.notifications,
    conversations: conversations ?? this.conversations,
    teams: teams ?? this.teams,
    pending: pending ?? this.pending,
    visits: visits ?? this.visits,
    unread: unread ?? this.unread,
    unreadMessages: unreadMessages ?? this.unreadMessages,
    syncedAt: syncedAt ?? this.syncedAt,
  );
}

/// Uses the same per-account SQLCipher database as reports. Stable IDs make
/// a lost HTTP response safe to retry without duplicating a message or decision.
class CollaborationService {
  CollaborationService(this.api, this.repository);
  final ApiClient api;
  final SecureReportRepository repository;
  bool _running = false;
  Future<List<Json>> pending() => repository.database.query(
    'collaboration_outbox',
    orderBy: 'created_at ASC, rowid ASC',
  );
  Future<String> enqueue(
    String owner,
    String kind,
    String route,
    Json payload, {
    String? id,
  }) async {
    final database = repository.database;
    await repository.checkStorage();
    final key = id ?? const Uuid().v4();
    await database.insert('collaboration_outbox', {
      'id': key,
      'owner_id': owner,
      'kind': kind,
      'route': route,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'blocked': 0,
    });
    return key;
  }

  Future<void> retry(String id) => repository.database
      .update(
        'collaboration_outbox',
        {'blocked': 0, 'error': null},
        where: 'id = ?',
        whereArgs: [id],
      )
      .then((_) {});
  Future<void> discard(String id) async {
    final rows = await repository.database.query(
      'collaboration_outbox',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.any((p) => p['kind'] == 'time')) {
      throw StateError(
        'Time records retain their order and cannot be discarded. Retry the action or ask your lead for help.',
      );
    }
    await repository.database.delete(
      'collaboration_outbox',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> canUpload(LocalReport report) async {
    if (report.workOrderId == null) return true;
    return !(await pending()).any(
      (p) =>
          p['kind'] == 'response' &&
          p['route'] == 'work-orders/${report.workOrderId}/response',
    );
  }

  Future<bool> flush({required bool Function() isCurrent}) async {
    if (_running) return false;
    _running = true;
    try {
      final rows = List<Json>.from(await pending());
      final order = {for (var i = 0; i < rows.length; i++) rows[i]['id']: i};
      // Acknowledgements precede check-in; visit actions retain durable order.
      rows.sort((a, b) {
        final ap = a['kind'] == 'response' ? 0 : 1,
            bp = b['kind'] == 'response' ? 0 : 1;
        return ap != bp
            ? ap.compareTo(bp)
            : order[a['id']]!.compareTo(order[b['id']]!);
      });
      final responsesPending = {
        for (final r in rows.where((r) => r['kind'] == 'response'))
          (r['route'] as String).split('/')[1],
      };
      final blockedVisits = <String>{};
      for (final row in rows.take(30)) {
        if (!isCurrent()) return false;
        final payload = jsonDecode(row['payload'] as String) as Json;
        if (row['kind'] == 'time') {
          final visit = payload['visitId'] as String;
          if (row['blocked'] == 1) blockedVisits.add(visit);
          if (blockedVisits.contains(visit) ||
              responsesPending.contains(
                (row['route'] as String).split('/')[1],
              )) {
            continue;
          }
        }
        if (row['blocked'] == 1) continue;
        try {
          final response = await api.send(
            row['route'] as String,
            method: 'POST',
            body: jsonDecode(row['payload'] as String),
          );
          if (!isCurrent()) return false;
          if (row['kind'] == 'response') {
            responsesPending.remove((row['route'] as String).split('/')[1]);
          }
          if (row['kind'] == 'time') {
            final saved =
                (await repository.metadata('time-visits') as List? ?? [])
                    .cast<Json>();
            if (!isCurrent()) return false;
            final merged = {
              for (final v in saved) v['id'] as String: v,
              response['id'] as String: response,
            };
            await repository.setMetadata('time-visits', merged.values.toList());
          }
          if (row['kind'] == 'message') {
            final id = (row['route'] as String).split('/')[1],
                cached = await cachedThread(
                  (row['route'] as String).split('/')[1],
                );
            final rows = <String, Json>{
              for (final m in (cached?['items'] as List? ?? []).cast<Json>())
                m['id'] as String: m,
              response['id'] as String: response,
            };
            final items = rows.values.toList()
              ..sort(
                (a, b) => BigInt.parse(
                  a['sequence'] as String,
                ).compareTo(BigInt.parse(b['sequence'] as String)),
              );
            await repository.setMetadata('conversation:$id', {
              ...?(cached),
              'items': items.length > 100
                  ? items.sublist(items.length - 100)
                  : items,
            });
          }
          if (!isCurrent()) return false;
          await repository.database.delete(
            'collaboration_outbox',
            where: 'id = ? AND owner_id = ?',
            whereArgs: [row['id'], row['owner_id']],
          );
        } on ServiceFailure catch (e) {
          if (row['kind'] == 'time') {
            blockedVisits.add(payload['visitId'] as String);
          }
          if (!isCurrent()) return false;
          await repository.database.update(
            'collaboration_outbox',
            {'error': e.message, 'blocked': e.retryable ? 0 : 1},
            where: 'id = ? AND owner_id = ?',
            whereArgs: [row['id'], row['owner_id']],
          );
          if (e.retryable || e.status == 401 || e.status == 403) return false;
        }
      }
      return true;
    } finally {
      _running = false;
    }
  }

  Future<Json?> cachedThread(String id) async =>
      await repository.metadata('conversation:$id') as Json?;
  Future<Json> messages(
    String id, {
    String? before,
    required bool Function() isCurrent,
  }) async {
    final result = await api.send(
      'conversations/$id/messages?limit=50${before == null ? '' : '&before=$before'}',
    );
    if (!isCurrent()) {
      throw StateError(
        'Unlock the original account to view this conversation.',
      );
    }
    final previous = await cachedThread(id);
    final merged = <String, Json>{
      for (final m in (previous?['items'] as List? ?? []).cast<Json>())
        m['id'] as String: m,
      for (final m in (result['items'] as List).cast<Json>())
        m['id'] as String: m,
    };
    final sorted = merged.values.toList()
      ..sort(
        (a, b) => BigInt.parse(
          a['sequence'] as String,
        ).compareTo(BigInt.parse(b['sequence'] as String)),
      );
    final cached = {
      ...result,
      'items': sorted.length > 100
          ? sorted.sublist(sorted.length - 100)
          : sorted,
    };
    await repository.setMetadata('conversation:$id', cached);
    return result;
  }
}
