import '../../core/contracts.dart';
import 'work_order.dart';

/// The engineer's confirmed summary is separate from operational approval.
/// Reassignment and a later supervisor follow-up reopen the active job.
class VisitProgress {
  VisitProgress(WorkOrder job, List<LocalReport> reports, List<Json> summaries)
    : approved = job.status == 'completed' {
    final ids = reports
        .where(
          (r) =>
              r.workOrderId == job.id &&
              r.workOrderAssignmentRevision == job.assignmentRevision,
        )
        .map((r) => r.id)
        .toSet();
    for (final entry in summaries) {
      final payload = entry['payload'] as Json;
      if (payload['workOrderId'] != job.id ||
          !ids.contains(payload['clientReportId'])) {
        continue;
      }
      final confirmed = DateTime.tryParse(
        payload['confirmedAt'] as String? ?? '',
      );
      final changed = DateTime.tryParse(
        job.source['updatedAt'] as String? ?? '',
      );
      if (job.status == 'follow_up' &&
          (confirmed == null ||
              changed == null ||
              !confirmed.isAfter(changed))) {
        continue;
      }
      summary = entry;
    }
  }
  final bool approved;
  Json? summary;
  String? get reportId =>
      (summary?['payload'] as Json?)?['clientReportId'] as String?;
  String? get outcome =>
      ((summary?['payload'] as Json?)?['values'] as Json?)?['claimed_outcome']
          as String?;
  bool get visitCompleted => summary != null && outcome == 'completed';
  bool get inCompleted => approved || visitCompleted;
  String get label => approved
      ? 'Approved & completed'
      : visitCompleted
      ? 'Visit completed'
      : summary != null
      ? 'Visit recorded · Follow-up required'
      : '';
  String get delivery => summary?['status'] == 'received'
      ? 'Summary received by dashboard'
      : summary?['status'] == 'attention'
      ? 'Saved on device · Sync needs attention'
      : 'Saved on device · Waiting to sync';
}
