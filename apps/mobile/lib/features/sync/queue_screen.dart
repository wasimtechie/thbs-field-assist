import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/workspace.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});
  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  String selection = 'all';
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider),
        controller = ref.read(appProvider.notifier);
    final reports = app.reports
        .where(
          (r) => switch (selection) {
            'draft' => r.state == ReportState.draft,
            'waiting' => [
              ReportState.queued,
              ReportState.syncing,
            ].contains(r.state),
            'received' => r.state == ReportState.accepted,
            'attention' => r.state == ReportState.needsAttention,
            _ => true,
          },
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & sync'),
        actions: [
          IconButton(
            tooltip: 'Synchronize reports',
            onPressed: app.busy ? null : controller.synchronize,
            icon: const MotionIcon(Icons.sync_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.synchronize,
          child: ListView(
            padding: const EdgeInsets.all(23),
            children: [
              const WorkspaceIntro(
                title: 'Your reports',
                subtitle:
                    'Saved locally first. Track drafts, deliveries and server receipts in one place.',
                icon: Icons.description_outlined,
              ),
              WorkspaceTabs<String>(
                values: const [
                  ('all', 'All'),
                  ('draft', 'Drafts'),
                  ('waiting', 'Waiting'),
                  ('received', 'Received'),
                  ('attention', 'Needs attention'),
                ],
                selected: selection,
                onSelected: (value) => setState(() => selection = value),
              ),
              const SizedBox(height: 18),
              ErrorNotice(app.error),
              if (reports.isEmpty)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(30),
                    child: Column(
                      children: [
                        MotionIcon(
                          Icons.cloud_done_outlined,
                          color: context.colors.teal,
                          size: 35,
                        ),
                        SizedBox(height: 14),
                        Text(
                          selection == 'all'
                              ? 'A clear queue'
                              : 'No reports in this view',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Reports matching this view will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.colors.muted,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final report in reports)
                Padding(
                  padding: const EdgeInsets.only(bottom: 13),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(17),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              MotionIcon(
                                report.state == ReportState.accepted
                                    ? Icons.check_circle_outline_rounded
                                    : report.state == ReportState.needsAttention
                                    ? Icons.error_outline_rounded
                                    : Icons.description_outlined,
                                color: report.state == ReportState.accepted
                                    ? context.colors.teal
                                    : context.colors.indigo,
                                size: 23,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  report.schema.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _label(report.state),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: report.state == ReportState.accepted
                                      ? context.colors.teal
                                      : context.colors.muted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '#${report.id.substring(0, 8).toUpperCase()} · Version ${report.schema.versionNumber}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.muted,
                            ),
                          ),
                          if (report.lastError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                report.lastError!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.colors.danger,
                                  height: 1.7,
                                ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (report.state == ReportState.draft)
                                TextButton.icon(
                                  onPressed: () =>
                                      context.push('/forms/${report.id}'),
                                  icon: const MotionIcon(
                                    Icons.edit_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('Continue draft'),
                                ),
                              if (report.state == ReportState.accepted)
                                TextButton.icon(
                                  onPressed: () =>
                                      context.push('/receipt/${report.id}'),
                                  icon: const MotionIcon(
                                    Icons.receipt_long_outlined,
                                    size: 17,
                                  ),
                                  label: const Text('View receipt'),
                                ),
                              if ([
                                ReportState.queued,
                                ReportState.needsAttention,
                              ].contains(report.state)) ...[
                                TextButton.icon(
                                  onPressed: app.busy
                                      ? null
                                      : () async {
                                          if (report.state ==
                                              ReportState.needsAttention) {
                                            await controller.repository.move(
                                              report.id,
                                              'retry',
                                            );
                                          }
                                          await controller.synchronize();
                                        },
                                  icon: const MotionIcon(
                                    Icons.sync_rounded,
                                    size: 17,
                                  ),
                                  label: const Text('Retry sync'),
                                ),
                                TextButton(
                                  onPressed: app.busy
                                      ? null
                                      : () async {
                                          try {
                                            await controller.sync.reopen(
                                              report.id,
                                            );
                                            await controller.reloadReports();
                                            final updated = await controller
                                                .repository
                                                .get(report.id);
                                            if (context.mounted) {
                                              if (updated.state ==
                                                  ReportState.draft) {
                                                context.push(
                                                  '/forms/${report.id}',
                                                );
                                              } else {
                                                context.push(
                                                  '/receipt/${report.id}',
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            if (context.mounted) {
                                              showDialog<void>(
                                                context: context,
                                                builder: (c) => AlertDialog(
                                                  title: const Text(
                                                    'Reconnect before editing',
                                                  ),
                                                  content: Text(
                                                    '$e\n\nThe prior upload must be fenced online before the report can be changed.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(c),
                                                      child: const Text(
                                                        'Keep report safe',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }
                                          }
                                        },
                                  child: const Text('Safely reopen'),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _label(ReportState state) => switch (state) {
  ReportState.draft => 'Draft',
  ReportState.queued => 'Queued',
  ReportState.syncing => 'Syncing',
  ReportState.accepted => 'Accepted',
  ReportState.needsAttention => 'Needs attention',
};

class LocalReceiptScreen extends ConsumerWidget {
  const LocalReceiptScreen({super.key, required this.reportId});
  final String reportId;
  @override
  Widget build(
    BuildContext context,
    WidgetRef ref,
  ) => FutureBuilder<LocalReport>(
    future: ref.read(appProvider.notifier).repository.get(reportId),
    builder: (context, snapshot) {
      final r = snapshot.data;
      return Scaffold(
        appBar: AppBar(title: const Text('Report receipt')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              const SizedBox(height: 35),
              if (r != null &&
                  [
                    ReportState.queued,
                    ReportState.syncing,
                    ReportState.accepted,
                  ].contains(r.state))
                Center(
                  child: Container(
                    width: 112,
                    height: 112,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: context.colors.teal.withValues(alpha: .08),
                      border: Border.all(
                        color: context.colors.teal.withValues(alpha: .3),
                      ),
                    ),
                    child: SuccessMark(color: context.colors.teal),
                  ),
                ),
              const SizedBox(height: 28),
              if (snapshot.hasError)
                ErrorNotice(snapshot.error.toString())
              else if (r == null)
                const Center(child: CircularProgressIndicator())
              else ...[
                Text(
                  r.state == ReportState.accepted
                      ? 'Received and\nrecorded.'
                      : r.state == ReportState.draft
                      ? 'Report in\nprogress.'
                      : 'Saved on\nthis device.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  r.state == ReportState.accepted
                      ? 'Accepted by the Field Assist demo server. This does not close a job in an external system.'
                      : r.state == ReportState.draft
                      ? 'Continue editing and review your details before queuing this report.'
                      : r.state == ReportState.needsAttention
                      ? 'Your report is saved. Open the sync queue to resolve the delivery issue.'
                      : 'Your reviewed report is durably queued. It will be sent when you reconnect and sync.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 15,
                    height: 1.8,
                  ),
                ),
                const SizedBox(height: 30),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(21),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('Local report reference'),
                        const SizedBox(height: 9),
                        SelectableText(
                          r.id,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.colors.ink,
                          ),
                        ),
                        const SizedBox(height: 17),
                        Text(
                          r.schema.title,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Version ${r.schema.versionNumber} · ${_label(r.state)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.colors.muted,
                          ),
                        ),
                        if (r.receipt != null) ...[
                          const SizedBox(height: 22),
                          const Eyebrow('Server receipt'),
                          const SizedBox(height: 9),
                          SelectableText(
                            r.receipt!['id'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.teal,
                            ),
                          ),
                        ],
                        if (r.location case final location?) ...[
                          const SizedBox(height: 20),
                          const Eyebrow('Captured location'),
                          const SizedBox(height: 8),
                          Text(
                            '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}',
                          ),
                          Text(
                            'Accuracy ±${location.accuracyMeters.round()} m${location.isMocked ? ' · Simulated' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: () => context.go('/queue'),
                  icon: const MotionIcon(Icons.cloud_upload_outlined),
                  label: const Text('View sync queue'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to home'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}
