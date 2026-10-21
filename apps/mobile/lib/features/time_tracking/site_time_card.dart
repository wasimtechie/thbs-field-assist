import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../../core/location/location_capture.dart';
import '../jobs/work_order.dart';
import 'time_tracking.dart';

class SiteTimeCard extends ConsumerStatefulWidget {
  const SiteTimeCard({super.key, required this.job});
  final WorkOrder job;
  @override
  ConsumerState<SiteTimeCard> createState() => _SiteTimeCardState();
}

class _SiteTimeCardState extends ConsumerState<SiteTimeCard> {
  Timer? timer;
  bool busy = false;
  String error = '';
  LocationCaptureFailure? locationError;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> action(String value) async {
    if (busy) return;
    setState(() => busy = true);
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(timeActionLabels[value] ?? 'Visit action'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ['check_in', 'check_out'].contains(value)
                  ? 'Record this time and your current location for the visit. Location is captured once.'
                  : 'Record this time for your visit. No location is requested for breaks.',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: note,
              maxLength: 500,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Visit note (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record action'),
          ),
        ],
      ),
    );
    final text = note.text;
    note.dispose();
    if (confirmed != true || !mounted) {
      if (mounted) setState(() => busy = false);
      return;
    }
    setState(() {
      busy = true;
      error = '';
      locationError = null;
    });
    try {
      await ref
          .read(appProvider.notifier)
          .recordSiteTime(widget.job, value, note: text);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          if (e is LocationCaptureFailure) locationError = e;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider),
        visits = effectiveVisits(app.collaboration),
        own = visits.where((v) => v['workOrderId'] == widget.job.id).toList(),
        active = visits.where((v) => v['state'] != 'closed').firstOrNull,
        current = own.where((v) => v['state'] != 'closed').firstOrNull,
        blocked = visits.any((v) => v['blocked'] == true);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MotionIcon(Icons.timer_outlined, color: context.colors.indigo),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Time on site',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              current == null
                  ? 'Check in when you arrive. Check out when you leave.'
                  : '${current['state'] == 'break' ? 'On break' : 'On site'} since ${_date(current['startedAt'] as String)}',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
            if (current != null) ...[
              const SizedBox(height: 14),
              _Totals(visit: current),
            ],
            if (active != null && current == null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Another visit is active. Open that job to check out first.',
                  style: TextStyle(color: context.colors.danger, fontSize: 12),
                ),
              ),
            if (blocked)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'A time action needs attention in Messages → Outbox. Resolve it before recording more actions.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox(height: 14),
            if (busy) const LinearProgressIndicator(),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (current == null && active == null && widget.job.canStart)
                  FilledButton.icon(
                    onPressed: busy || blocked
                        ? null
                        : () => action('check_in'),
                    icon: const Icon(Icons.location_on_outlined, size: 18),
                    label: const Text('Check in'),
                  ),
                if (current != null) ...[
                  OutlinedButton.icon(
                    onPressed: busy || blocked
                        ? null
                        : () => action(
                            current['state'] == 'break'
                                ? 'break_end'
                                : 'break_start',
                          ),
                    icon: Icon(
                      current['state'] == 'break'
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 18,
                    ),
                    label: Text(
                      current['state'] == 'break'
                          ? 'Resume work'
                          : 'Start break',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy || blocked
                        ? null
                        : () => action('check_out'),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Check out'),
                  ),
                ],
              ],
            ),
            ErrorNotice(error),
            if (locationError?.canOpenSettings == true)
              TextButton(
                onPressed: () => const LocationCapture().openSettings(
                  deviceLocation: locationError!.code == 'LOCATION_DISABLED',
                ),
                child: const Text('Open location settings'),
              ),
            if (own.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final visit in own.take(10))
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    '${_date(visit['startedAt'] as String)} · ${visit['state'] == 'closed'
                        ? 'Checked out'
                        : visit['state'] == 'break'
                        ? 'On break'
                        : 'On site'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  subtitle: Text(
                    visit['blocked'] == true
                        ? 'Needs attention'
                        : visit['queued'] == true
                        ? 'Saved on phone · queued for sync'
                        : 'Received by server',
                    style: TextStyle(fontSize: 11, color: context.colors.muted),
                  ),
                  children: [
                    _Totals(visit: visit),
                    for (final e in (visit['events'] as List).cast<Json>())
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(
                          e['queued'] == true
                              ? Icons.cloud_upload_outlined
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                        ),
                        title: Text(
                          timeActionLabels[e['action']] ?? 'Visit action',
                          style: const TextStyle(fontSize: 12),
                        ),
                        subtitle: Text(
                          '${_date(e['occurredAt'] as String)}${e['location'] == null ? '' : ' · ±${(e['location']['accuracyMeters'] as num).round()} m${e['location']['isMocked'] == true ? ' · Simulated' : ''}'}${(e['note'] as String? ?? '').isEmpty ? '' : '\n${e['note']}'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              if (own.length > 10)
                const Text(
                  'Showing the latest 10 downloaded visits for this job.',
                  style: TextStyle(fontSize: 11),
                ),
            ],
            const SizedBox(height: 10),
            Text(
              'Actions save in encrypted storage and sync when connected. Elapsed time continues while the app is closed. Device clock; no continuous location tracking.',
              style: TextStyle(
                fontSize: 11,
                height: 1.6,
                color: context.colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _date(String value) {
  final d = DateTime.parse(value).toLocal();
  return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Totals extends StatelessWidget {
  const _Totals({required this.visit});
  final Json visit;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final pair in [
        ('On site', 'siteSeconds'),
        ('Working', 'workSeconds'),
        ('Breaks', 'breakSeconds'),
      ])
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pair.$1,
                  style: TextStyle(fontSize: 10, color: context.colors.muted),
                ),
                const SizedBox(height: 5),
                Text(
                  elapsedLabel(visit[pair.$2] as int),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
