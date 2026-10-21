import 'dart:math';
import '../../core/contracts.dart';
import '../../core/networking/api_client.dart';
import '../../core/persistence/report_repository.dart';

class SyncService {
  SyncService(this.api, this.repository, {this.beforeUpload});
  final Future<bool> Function(LocalReport report)? beforeUpload;
  final ApiClient api;
  final SecureReportRepository repository;
  bool _running = false;
  String? lastError;
  Future<bool> run({bool manual = false, bool Function()? isCurrent}) async {
    bool current() => isCurrent?.call() ?? true;
    if (!current()) {
      return false;
    }
    if (_running) return false;
    _running = true;
    lastError = null;
    try {
      await api.send('me');
      if (!current()) {
        return false;
      }
      final reports = await repository.list();
      for (final report in reports) {
        if (!current()) {
          return false;
        }
        if (report.state != ReportState.queued) continue;
        if (!manual && report.nextRetryAt?.isAfter(DateTime.now()) == true) {
          continue;
        }
        if (beforeUpload != null && !await beforeUpload!(report)) {
          if (!current()) {
            return false;
          }
          lastError =
              'An assignment response is still queued or needs attention. Its report is kept until that response is resolved.';
          continue;
        }
        if (!current()) {
          return false;
        }
        await repository.move(report.id, 'upload');
        if (!current()) {
          return false;
        }
        try {
          final r = await api.send(
            'submissions',
            method: 'POST',
            body: report.frozen,
            headers: {'X-Payload-SHA256': report.payloadHash!},
          );
          if (!current()) {
            return false;
          }
          await repository.move(
            report.id,
            'receipt',
            receipt: r['receipt'] as Json,
            retries: 0,
          );
        } on ServiceFailure catch (e) {
          if (!current()) {
            return false;
          }
          if (e.receipt != null) {
            await repository.move(
              report.id,
              'receipt',
              receipt: e.receipt,
              retries: 0,
            );
            continue;
          }
          if (e.retryable) {
            final count = report.retryCount + 1;
            final seconds =
                min(60, pow(2, min(count, 6)).toInt()) + Random().nextInt(3);
            await repository.move(
              report.id,
              'transient',
              error: e.message,
              retries: count,
              nextRetry: DateTime.now().add(Duration(seconds: seconds)),
            );
          } else {
            await repository.move(report.id, 'rejected', error: e.message);
          }
          lastError = e.message;
        }
      }
    } on ServiceFailure catch (e) {
      if (!current()) {
        return false;
      }
      lastError = e.message;
    } finally {
      _running = false;
    }
    return true;
  }

  Future<void> reopen(String id) async {
    final r = await repository.get(id);
    if (![ReportState.queued, ReportState.needsAttention].contains(r.state)) {
      throw StateError('Only an unaccepted report can be reopened.');
    }
    final status = await api.send('submissions/status/${r.id}');
    if (status['status'] == 'accepted') {
      await _persistWinningReceipt(r, status['receipt'] as Json);
      return;
    }
    final fence = await api.send(
      'submission-attempts/${r.attemptId}/cancel',
      method: 'POST',
      body: {'clientReportId': r.id, 'payloadHash': r.payloadHash},
    );
    if (fence['status'] == 'accepted') {
      await _persistWinningReceipt(r, fence['receipt'] as Json);
      return;
    }
    if (fence['status'] != 'cancelled') {
      throw StateError(
        'Cancellation is uncertain. Keep the frozen report and reconnect.',
      );
    }
    await repository.move(id, 'fenced_reopen');
  }

  Future<void> _persistWinningReceipt(LocalReport r, Json receipt) async {
    if (r.state == ReportState.needsAttention) {
      await repository.move(r.id, 'retry');
    }
    await repository.move(r.id, 'upload');
    await repository.move(r.id, 'receipt', receipt: receipt, retries: 0);
  }
}
