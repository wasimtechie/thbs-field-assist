import '../fttp/fttp_widgets.dart';
import '../fttp/fttp_workflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../collaboration/communication_screens.dart';
import '../../core/contracts.dart';
import '../../core/design_system/profile_avatar.dart';
import '../time_tracking/site_time_card.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/workspace.dart';
import 'visit_progress.dart';

String jobDate(DateTime value) {
  final d = value.toLocal();
  return '${d.day}/${d.month}/${d.year} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key, this.showCompleted = false});
  final bool showCompleted;
  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  bool refreshing = false;
  late bool history = widget.showCompleted;
  @override
  void didUpdateWidget(covariant JobsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.showCompleted != widget.showCompleted) {
      history = widget.showCompleted;
    }
  }

  String error = '';
  Future<void> refresh() async {
    if (refreshing) return;
    setState(() {
      refreshing = true;
      error = '';
    });
    try {
      await ref.read(appProvider.notifier).refreshOperations();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not refresh. Your last downloaded jobs and feedback remain available.',
        );
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final jobs =
        app.workOrders
            .where(
              (j) =>
                  VisitProgress(
                    j,
                    app.reports,
                    app.summarySubmissions,
                  ).inCompleted ==
                  history,
            )
            .toList()
          ..sort((a, b) {
            final p = {'urgent': 0, 'high': 1, 'normal': 2};
            final rank = (p[a.priority] ?? 2).compareTo(p[b.priority] ?? 2);
            return rank != 0 ? rank : a.dueAt.compareTo(b.dueAt);
          });
    return Scaffold(
      appBar: AppBar(
        title: const Text('My jobs'),
        actions: [
          const CollaborationActionsBar(showMessages: false),
          IconButton(
            tooltip: 'Refresh assignments',
            onPressed: refreshing ? null : refresh,
            icon: refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const MotionIcon(Icons.sync_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(23),
        children: [
          const WorkspaceIntro(
            title: 'Your next visit,\nready to go.',
            subtitle: 'Your assignments, visit briefs and supervisor updates.',
            icon: Icons.work_outline_rounded,
          ),
          Text(
            app.operationsSyncedAt == null
                ? 'Connect and refresh to download your assignments.'
                : 'Downloaded ${jobDate(app.operationsSyncedAt!)} · available offline',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 11,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          ErrorNotice(error),
          WorkspaceTabs<bool>(
            values: const [(false, 'Active jobs'), (true, 'Completed')],
            selected: history,
            onSelected: (value) {
              setState(() => history = value);
              GoRouter.maybeOf(
                context,
              )?.go(value ? '/jobs?view=completed' : '/jobs');
            },
          ),
          const SizedBox(height: 17),
          if (jobs.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  history
                      ? 'Completed visits and approved jobs will appear here.'
                      : 'No downloaded active jobs. Refresh after your supervisor assigns work.',
                ),
              ),
            ),
          ...jobs.map((job) {
            final progress = VisitProgress(
              job,
              app.reports,
              app.summarySubmissions,
            );
            final local = app.reports
                .where(
                  (r) =>
                      r.workOrderId == job.id &&
                      r.state != ReportState.accepted,
                )
                .firstOrNull;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => context.push('/jobs/${job.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StatusPill(
                              job.priority.toUpperCase(),
                              color: job.priority == 'urgent'
                                  ? context.colors.danger
                                  : context.colors.indigo,
                            ),
                            StatusPill(
                              job.responseQueued
                                  ? 'Response queued'
                                  : job.responseStatus == 'pending'
                                  ? 'Pending acceptance'
                                  : job.responseStatus == 'declined'
                                  ? 'Declined'
                                  : 'Accepted',
                              color: job.responseStatus == 'declined'
                                  ? context.colors.danger
                                  : context.colors.indigo,
                            ),
                            if (progress.summary != null ||
                                job.status != 'assigned' ||
                                local != null)
                              StatusPill(
                                progress.label.isNotEmpty
                                    ? progress.label
                                    : local == null
                                    ? job.statusLabel
                                    : local.state == ReportState.draft
                                    ? 'Draft on device'
                                    : 'Report queued',
                                color: context.colors.teal,
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          job.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            MotionIcon(
                              Icons.location_on_outlined,
                              size: 14,
                              color: context.colors.muted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                job.site,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (progress.summary != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            progress.delivery,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        AssignmentPeople(source: job.source),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            MotionIcon(
                              Icons.schedule_rounded,
                              size: 16,
                              color: job.overdue
                                  ? context.colors.danger
                                  : context.colors.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${job.overdue ? 'Overdue · ' : ''}${jobDate(job.dueAt)}',
                                style: TextStyle(
                                  color: job.overdue
                                      ? context.colors.danger
                                      : context.colors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const MotionIcon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          if (app.feedback.isNotEmpty) ...[
            const SizedBox(height: 20),
            const WorkspaceSection('Supervisor feedback'),
            const SizedBox(height: 12),
            ...app.feedback
                .take(8)
                .map(
                  (f) => Card(
                    child: ListTile(
                      leading: MotionIcon(
                        f['decision'] == 'approved'
                            ? Icons.task_alt_rounded
                            : Icons.assignment_return_outlined,
                        color: context.colors.teal,
                      ),
                      title: Text(
                        f['decision'] == 'approved'
                            ? 'Report approved'
                            : 'Follow-up requested',
                      ),
                      subtitle: Text(
                        '${(f['note'] as String).isEmpty ? 'Reviewed by your supervisor.' : f['note']}\nReport #${(f['clientReportId'] as String).substring(0, 8)}',
                      ),
                      isThreeLine: true,
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;
  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  bool starting = false;
  String error = '';
  Future<void> respond(String decision) async {
    final form = GlobalKey<FormState>();
    var note = '';
    String? value;
    value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          decision == 'accepted'
              ? 'Accept this assignment?'
              : 'Decline this assignment?',
        ),
        content: Form(
          key: form,
          child: TextFormField(
            onChanged: (value) => note = value,
            maxLength: 1000,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: decision == 'declined'
                  ? 'Reason for declining'
                  : 'Note to your lead (optional)',
            ),
            validator: (v) =>
                decision == 'declined' && (v?.trim().isEmpty ?? true)
                ? 'Give your lead a reason.'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, note.trim());
              }
            },
            child: Text(decision == 'accepted' ? 'Accept job' : 'Send decline'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final job = ref
        .read(appProvider)
        .workOrders
        .where((j) => j.id == widget.jobId)
        .firstOrNull;
    if (job == null) return;
    setState(() {
      starting = true;
      error = '';
    });
    try {
      await ref
          .read(appProvider.notifier)
          .respondToAssignment(job, decision, value);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider),
        job = ref
            .watch(appProvider)
            .workOrders
            .where((j) => j.id == widget.jobId)
            .firstOrNull;
    if (job == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job unavailable')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Refresh assignments to check this job.'),
        ),
      );
    }
    final local = app.reports
        .where(
          (r) => r.workOrderId == job.id && r.state != ReportState.accepted,
        )
        .firstOrNull;
    final earlier = app.workOrders
        .where(
          (j) =>
              j.id != job.id &&
              job.assetReference.isNotEmpty &&
              j.assetReference == job.assetReference,
        )
        .toList();
    final progress = VisitProgress(job, app.reports, app.summarySubmissions);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visit brief'),
        actions: const [CollaborationActionsBar()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(23),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                job.priority.toUpperCase(),
                color: context.colors.indigo,
              ),
              StatusPill(
                progress.label.isEmpty ? job.statusLabel : progress.label,
                color: context.colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatusPill(
            job.responseQueued
                ? '${job.responseStatus == 'accepted' ? 'Acceptance' : 'Decline'} queued on this phone'
                : job.responseStatus == 'pending'
                ? 'Pending your response'
                : job.responseStatus == 'declined'
                ? 'You declined this assignment'
                : 'Assignment accepted',
            color: job.responseStatus == 'declined'
                ? context.colors.danger
                : context.colors.teal,
          ),
          const SizedBox(height: 22),
          Text(job.title, style: Theme.of(context).textTheme.headlineLarge),
          if (progress.summary != null) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: Icon(
                  progress.visitCompleted
                      ? Icons.task_alt
                      : Icons.assignment_turned_in_outlined,
                ),
                title: Text(progress.label),
                subtitle: Text(
                  '${progress.delivery}. Supervisor approval is tracked separately.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/queue'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          AssignmentPeople(source: job.source),
          const SizedBox(height: 20),
          if (job.source['client'] != null)
            _Brief(
              Icons.business_outlined,
              'Client',
              job.source['client']['name'] as String,
            ),
          if (job.source['team'] != null)
            _Brief(
              Icons.groups_outlined,
              'Squad',
              job.source['team']['name'] as String,
            ),
          if (job.source['board'] != null)
            _Brief(
              Icons.view_kanban_outlined,
              'Board',
              job.source['board']['name'] as String,
            ),
          _Brief(Icons.place_outlined, 'Site', job.site),

          _Brief(
            Icons.schedule_rounded,
            job.overdue ? 'Overdue' : 'Due',
            jobDate(job.dueAt),
          ),
          if (job.assetReference.isNotEmpty)
            _Brief(
              Icons.cable_rounded,
              'Asset / cable reference',
              job.assetReference,
            ),
          if ([
            fttpTemplateId,
            closureTemplateId,
          ].contains(app.form?.templateId))
            FttpBrief(job: job)
          else
            _Brief(
              Icons.assignment_outlined,
              'Visit instructions',
              job.instructions.isEmpty
                  ? 'No additional instructions supplied.'
                  : job.instructions,
            ),
          if (job.reviewNote.isNotEmpty)
            _Brief(
              Icons.rate_review_outlined,
              'Supervisor note',
              job.reviewNote,
            ),
          if (job.responseStatus == 'pending' &&
              ['assigned', 'follow_up'].contains(job.status))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Can you take this visit?',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Accept the brief or let your lead know why you cannot take it.',
                      style: TextStyle(
                        color: context.colors.muted,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: starting
                              ? null
                              : () => respond('accepted'),
                          icon: const MotionIcon(Icons.check_rounded, size: 17),
                          label: const Text('Accept job'),
                        ),
                        OutlinedButton.icon(
                          onPressed: starting
                              ? null
                              : () => respond('declined'),
                          icon: const MotionIcon(Icons.close_rounded, size: 17),
                          label: const Text('Decline'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if ((job.source['responseNote'] as String? ?? '').isNotEmpty)
            _Brief(
              Icons.forum_outlined,
              'Your response',
              job.source['responseNote'] as String,
            ),
          if (job.source['team']?['leadId'] != null)
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final c = await ref
                      .read(appProvider.notifier)
                      .openConversation(
                        recipientId: job.source['team']['leadId'] as String,
                      );
                  if (context.mounted) context.push('/messages/${c['id']}');
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                }
              },
              icon: const MotionIcon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
              ),
              label: const Text('Message team lead'),
            ),
          const SizedBox(height: 14),
          SiteTimeCard(job: job),
          ErrorNotice(error),
          const SizedBox(height: 16),
          if (local != null && local.state != ReportState.draft)
            FilledButton.icon(
              onPressed: () => context.push('/queue'),
              icon: const MotionIcon(Icons.cloud_upload_outlined),
              label: const Text('View queued report'),
            )
          else if (job.canStart)
            FilledButton.icon(
              onPressed: starting
                  ? null
                  : () async {
                      setState(() {
                        starting = true;
                        error = '';
                      });
                      try {
                        final report = await ref
                            .read(appProvider.notifier)
                            .startAssignedJob(job.id);
                        if (context.mounted) {
                          context.push('/forms/${report.id}');
                        }
                      } catch (e) {
                        if (mounted) setState(() => error = e.toString());
                      } finally {
                        if (mounted) setState(() => starting = false);
                      }
                    },
              icon: const MotionIcon(Icons.edit_note_rounded),
              label: Text(
                starting
                    ? 'Opening…'
                    : local != null
                    ? progress.summary != null
                          ? 'Edit visit summary'
                          : 'Resume job report'
                    : job.status == 'follow_up'
                    ? 'Start follow-up report'
                    : 'Start job report',
              ),
            ),
          const SizedBox(height: 14),
          Text(
            'Downloaded instructions work offline. Confirm your report to queue it for delivery. A supervisor approves completion after it reaches the dashboard.',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12,
              height: 1.7,
            ),
          ),
          if (earlier.isNotEmpty) ...[
            const SizedBox(height: 28),
            const Eyebrow('Your other visits for this asset'),
            const SizedBox(height: 12),
            ...earlier
                .take(10)
                .map(
                  (j) => Card(
                    child: ListTile(
                      title: Text(j.title),
                      subtitle: Text(j.statusLabel),
                      trailing: const MotionIcon(Icons.chevron_right_rounded),
                      onTap: () => context.push('/jobs/${j.id}'),
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _Brief extends StatelessWidget {
  const _Brief(this.icon, this.label, this.value);
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MotionIcon(icon, color: context.colors.indigo, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: context.colors.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
