import '../../core/contracts.dart';

class WorkOrder {
  WorkOrder.fromJson(this.source)
    : id = source['id'] as String,
      title = source['title'] as String,
      site = source['site'] as String,
      instructions = source['instructions'] as String? ?? '',
      assetReference = source['assetReference'] as String? ?? '',
      typeId = source['typeId'] as String,
      priority = source['priority'] as String,
      status = source['status'] as String,
      reviewNote = source['reviewNote'] as String? ?? '',
      dueAt = DateTime.parse(source['dueAt'] as String);
  final Json source;
  final String id,
      title,
      site,
      instructions,
      assetReference,
      typeId,
      priority,
      status,
      reviewNote;
  final DateTime dueAt;
  String get responseStatus =>
      source['responseStatus'] as String? ?? 'accepted';
  int get assignmentRevision => source['assignmentRevision'] as int? ?? 1;
  bool get responseQueued => source['responseQueued'] == true;
  bool get canStart =>
      responseStatus == 'accepted' &&
      (status == 'assigned' || status == 'follow_up');
  bool get overdue =>
      ['assigned', 'follow_up'].contains(status) &&
      dueAt.isBefore(DateTime.now());
  String get statusLabel => switch (status) {
    'assigned' => 'Assigned',
    'submitted' => 'Awaiting review',
    'follow_up' => 'Follow-up requested',
    'completed' => 'Approved & completed',
    _ => status,
  };
}
