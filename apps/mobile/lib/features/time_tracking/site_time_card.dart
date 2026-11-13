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
  const SiteTimeCard({super.key, required this.job, this.collapsible = false});
  final WorkOrder job;
  final bool collapsible;
  @override
  ConsumerState<SiteTimeCard> createState() => _SiteTimeCardState();
}

class _SiteTimeCardState extends ConsumerState<SiteTimeCard> {
  Timer? timer;
  bool busy = false;
  bool savingAction = false;
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
    try {
      final state = ref.read(appProvider);
      final visit = effectiveVisits(state.collaboration)
          .where(
            (v) => v['workOrderId'] == widget.job.id && v['state'] != 'closed',
          )
          .firstOrNull;
      final earlyDeparture =
          value == 'check_out' &&
          visit != null &&
          !visitHasSubmission(
            widget.job.id,
            widget.job.assignmentRevision,
            visit['startedAt'] as String,
            state.reports,
            state.summarySubmissions,
          );
      final text = await showDialog<String>(
        context: context,
        builder: (_) =>
            _SiteActionDialog(action: value, earlyDeparture: earlyDeparture),
      );
      if (text == null || !mounted) return;
      setState(() {
        error = '';
        locationError = null;
        savingAction = true;
      });
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
      if (mounted) {
        setState(() {
          busy = false;
          savingAction = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider),
        visits = effectiveVisits(app.collaboration),
        own = visits
            .where(
              (v) =>
                  v['workOrderId'] == widget.job.id &&
                  v['assignmentRevision'] == widget.job.assignmentRevision,
            )
            .toList(),
        active = visits.where((v) => v['state'] != 'closed').firstOrNull,
        current = own.where((v) => v['state'] != 'closed').firstOrNull,
        blocked = visits.any((v) => v['blocked'] == true);
    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.collapsible)
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
          if (!widget.collapsible) const SizedBox(height: 12),
          Text(
            current == null
                ? own.isEmpty
                      ? 'Check-in not recorded. Check in when you arrive; check out when you leave. Resuming a report keeps your recorded times.'
                      : 'Visit checked out. Times are saved below. You can still finish and submit your report after leaving the site.'
                : '${current['state'] == 'break' ? 'On break' : 'On site'} since ${_date(current['startedAt'] as String)}',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12,
              height: 1.7,
            ),
          ),
          if (own.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Check-in is optional in this demo and separate from the visit summary. It records the current time and location, not an earlier arrival.',
                style: TextStyle(fontSize: 12),
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
          if (savingAction) const LinearProgressIndicator(),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (current == null && active == null && widget.job.canStart)
                FilledButton.icon(
                  onPressed: busy || blocked ? null : () => action('check_in'),
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
                    current['state'] == 'break' ? 'Resume work' : 'Start break',
                  ),
                ),
                FilledButton.icon(
                  onPressed: busy || blocked ? null : () => action('check_out'),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Check out'),
                ),
              ],
            ],
          ),
          ErrorNotice(error),
          if (locationError?.canOpenSettings == true)
            TextButton(
              onPressed: () async {
                try {
                  await const LocationCapture().openSettings(
                    deviceLocation: locationError!.code == 'LOCATION_DISABLED',
                  );
                } catch (_) {
                  if (mounted) {
                    setState(
                      () => error =
                          'Open your device settings and allow Field Assist location access. Your report is saved.',
                    );
                  }
                }
              },
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
    );
    return Card(
      child: widget.collapsible
          ? ExpansionTile(
              title: const Text('Time on site'),
              subtitle: Text(
                current == null
                    ? own.isEmpty
                          ? 'Check-in not recorded · Optional in demo'
                          : 'Visit checked out · Times saved'
                    : '${current['state'] == 'break' ? 'On break' : 'On site'} since ${_date(current['startedAt'] as String)}',
              ),
              children: [content],
            )
          : content,
    );
  }
}

/// Owns its controller until the reverse dialog transition has finished.
class _SiteActionDialog extends StatefulWidget {
  const _SiteActionDialog({required this.action, required this.earlyDeparture});
  final String action;
  final bool earlyDeparture;
  @override
  State<_SiteActionDialog> createState() => _SiteActionDialogState();
}

class _SiteActionDialogState extends State<_SiteActionDialog> {
  final note = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(
      widget.earlyDeparture
          ? 'Leave before submitting?'
          : timeActionLabels[widget.action] ?? 'Visit action',
    ),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.earlyDeparture
                ? 'Normally, submit your visit summary before checking out. If you need to leave now, record a reason. Your draft stays on this phone and can be completed later.'
                : ['check_in', 'check_out'].contains(widget.action)
                ? 'Record the current time and a one-time location for this visit. This works offline when device location is available.'
                : 'Record the current time for your visit. Breaks do not request location.',
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: note,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: widget.earlyDeparture
                  ? 'Reason for leaving before submission'
                  : 'Visit note (optional)',
            ),
            validator: (value) =>
                widget.earlyDeparture && (value?.trim().isEmpty ?? true)
                ? 'Add a reason, or finish your report first.'
                : null,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.earlyDeparture ? 'Finish report first' : 'Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, note.text.trim());
          }
        },
        child: Text(
          widget.earlyDeparture ? 'Check out with reason' : 'Record action',
        ),
      ),
    ],
  );
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
