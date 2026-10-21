import 'dart:convert';
import '../../core/contracts.dart';
import '../collaboration/collaboration_service.dart';

const timeActionLabels = {
  'check_in': 'Arrived on site',
  'break_start': 'Break started',
  'break_end': 'Work resumed',
  'check_out': 'Checked out',
};
String elapsedLabel(int seconds) =>
    '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
Json visitDurations(List<Json> events, {DateTime? now}) {
  var working = 0, breaks = 0, state = 'closed';
  DateTime? start, first, last;
  for (final event in events) {
    final time = DateTime.parse(event['occurredAt'] as String);
    if (start != null) {
      final seconds = time.difference(start).inSeconds.clamp(0, 2147483647);
      if (state == 'working') working += seconds;
      if (state == 'break') breaks += seconds;
    }
    switch (event['action']) {
      case 'check_in':
        first = time;
        state = 'working';
      case 'break_start':
        state = 'break';
      case 'break_end':
        state = 'working';
      case 'check_out':
        state = 'closed';
    }
    start = time;
    last = time;
  }
  if (start != null && state != 'closed') {
    final at = now ?? DateTime.now().toUtc();
    final seconds = at.difference(start).inSeconds.clamp(0, 2147483647);
    if (state == 'working') {
      working += seconds;
    } else {
      breaks += seconds;
    }
    last = at.isBefore(start) ? start : at;
  }
  return {
    'workSeconds': working,
    'breakSeconds': breaks,
    'siteSeconds': first == null || last == null
        ? 0
        : last.difference(first).inSeconds.clamp(0, 2147483647),
  };
}

/// Server receipts plus durable pending actions, never an in-memory-only timer.
List<Json> effectiveVisits(CollaborationState state) {
  final visits = <String, Json>{
    for (final v in state.visits)
      v['id'] as String: {
        ...v,
        'events': List<Json>.from((v['events'] as List).cast<Json>()),
      },
  };
  for (final row in state.pending.where((p) => p['kind'] == 'time')) {
    final p = jsonDecode(row['payload'] as String) as Json;
    final id = p['visitId'] as String;
    final visit = visits.putIfAbsent(
      id,
      () => {
        'id': id,
        'workOrderId': (row['route'] as String).split('/')[1],
        'assignmentRevision': p['assignmentRevision'],
        'startedAt': p['occurredAt'],
        'state': 'working',
        'events': <Json>[],
      },
    );
    final events = visit['events'] as List<Json>;
    if (!events.any((e) => e['requestId'] == p['requestId'])) {
      events.add({
        ...p,
        'queued': true,
        'blocked': row['blocked'] == 1,
        'error': row['error'],
      });
    }
    events.sort(
      (a, b) => (a['sequence'] as int).compareTo(b['sequence'] as int),
    );
    visit['queued'] = true;
    if (row['blocked'] == 1) visit['blocked'] = true;
  }
  for (final visit in visits.values) {
    final events = (visit['events'] as List).cast<Json>();
    if (events.isNotEmpty) {
      final e = events.last;
      visit['sequence'] = e['sequence'];
      visit['lastOccurredAt'] = e['occurredAt'];
      visit['state'] = switch (e['action']) {
        'check_out' => 'closed',
        'break_start' => 'break',
        _ => 'working',
      };
      visit['endedAt'] = e['action'] == 'check_out' ? e['occurredAt'] : null;
    }
    visit.addAll(visitDurations(events));
  }
  return visits.values.toList()..sort(
    (a, b) => (b['startedAt'] as String).compareTo(a['startedAt'] as String),
  );
}
