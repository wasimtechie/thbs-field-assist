import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/workspace.dart';
import '../../core/design_system/profile_avatar.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider),
        controller = ref.read(appProvider.notifier);
    final drafts = app.reports
        .where((r) => r.state == ReportState.draft)
        .toList();
    final queued = app.reports
        .where(
          (r) => [
            ReportState.queued,
            ReportState.syncing,
            ReportState.needsAttention,
          ].contains(r.state),
        )
        .length;
    final active = app.workOrders.where((j) => j.status != 'completed').length;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.synchronize,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
            children: [
              Row(
                children: [
                  WorkspaceIcon(Icons.sensors_rounded, size: 31),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'THBS FIELD ASSIST',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Alerts',
                    onPressed: () => context.push('/alerts'),
                    icon: Badge.count(
                      count: app.collaboration.unread,
                      isLabelVisible: app.collaboration.unread > 0,
                      child: const MotionIcon(
                        Icons.notifications_outlined,
                        size: 21,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  IconButton(
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                    icon: ProfileAvatar(
                      name: app.user?.name ?? 'Engineer',
                      avatarId: app.user?.avatarId ?? '',
                      size: 34,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 21),
              FieldEntrance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${app.user?.name.split(' ').first ?? 'engineer'}.',
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontSize: 29, letterSpacing: -.9),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Let’s make it a good day in the field.',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              ErrorNotice(app.error),
              if (app.notice.isNotEmpty) ErrorNotice(app.notice, isInfo: true),
              if (app.form != null)
                FieldEntrance(
                  delay: 50,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          context.colors.raised,
                          context.colors.panel,
                          context.colors.teal.withValues(alpha: .07),
                        ],
                      ),
                      border: Border.all(
                        color: context.colors.panel.withValues(alpha: .8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.indigo.withValues(alpha: .065),
                          blurRadius: 25,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'YOUR FIELD COMPANION',
                                    style: TextStyle(
                                      fontSize: 9,
                                      letterSpacing: 1.2,
                                      color: context.colors.indigo,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 11),
                                  Text(
                                    'Ready for your\nnext report.',
                                    style: TextStyle(
                                      fontSize: 25,
                                      height: 1.2,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.7,
                                      color: context.colors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const AssistantOrb(size: 91),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          app.form!.title,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 17),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: app.busy
                                ? null
                                : () async {
                                    try {
                                      final report = await controller
                                          .startReport();
                                      if (context.mounted) {
                                        context.push('/forms/${report.id}');
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(content: Text(e.toString())),
                                        );
                                      }
                                    }
                                  },
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                MotionIcon(Icons.add_rounded, size: 20),
                                SizedBox(width: 8),
                                Flexible(child: Text('Start report')),
                                SizedBox(width: 13),
                                MotionIcon(
                                  Icons.arrow_forward_rounded,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 11),
                        Center(
                          child: Text(
                            'Complete by voice or touch.',
                            style: TextStyle(
                              fontSize: 10,
                              color: context.colors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const ErrorNotice(
                  'No default form is assigned. Connect and ask your administrator to assign a published form.',
                ),
              const SizedBox(height: 23),
              Row(
                children: [
                  Expanded(
                    child: _Shortcut(
                      label: 'My jobs',
                      detail: '$active open',
                      icon: Icons.work_outline_rounded,
                      onTap: () => context.push('/jobs'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Shortcut(
                      label: 'Reports',
                      detail: '$queued pending',
                      icon: Icons.description_outlined,
                      onTap: () => context.push('/queue'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Shortcut(
                      label: 'Messages',
                      detail: '${app.collaboration.unreadMessages} unread',
                      icon: Icons.forum_outlined,
                      onTap: () => context.push('/messages'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              WorkspaceSection(
                'Pick up where you left off',
                action:
                    '${drafts.length} ${drafts.length == 1 ? 'draft' : 'drafts'}',
                onAction: () => context.push('/queue'),
              ),
              if (drafts.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const WorkspaceIcon(Icons.edit_note_rounded),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'A clean slate. Start your next report above.',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...drafts
                    .take(3)
                    .map(
                      (r) => Card(
                        child: ListTile(
                          leading: const WorkspaceIcon(Icons.edit_note_rounded),
                          title: Text(r.schema.title),
                          subtitle: Text(
                            '${r.values.values.where((v) => !missing(v)).length} values saved · v${r.schema.versionNumber}',
                          ),
                          trailing: const MotionIcon(
                            Icons.arrow_outward_rounded,
                            size: 17,
                          ),
                          onTap: () => context.push('/forms/${r.id}'),
                        ),
                      ),
                    ),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: WorkspaceIcon(
                    Icons.cloud_upload_outlined,
                    color: context.colors.teal,
                  ),
                  title: const Text('Your sync queue'),
                  subtitle: Text('$queued waiting or needing attention'),
                  trailing: const MotionIcon(
                    Icons.chevron_right_rounded,
                    size: 19,
                  ),
                  onTap: () => context.push('/queue'),
                ),
              ),
              const SizedBox(height: 21),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    app.offline ? 'Offline' : 'On this device',
                    icon: app.offline
                        ? Icons.wifi_off_rounded
                        : Icons.phone_iphone_rounded,
                  ),
                  StatusPill(
                    '${app.form?.fields.length ?? 0} form fields',
                    icon: Icons.fact_check_outlined,
                    color: context.colors.indigo,
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                app.voiceReady
                    ? 'Voice package verified. Ready when you are.'
                    : 'Manual forms ready. Voice readiness not verified.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.7,
                  color: context.colors.muted,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                'LAST CONTACT  ${app.lastSync?.toLocal().toString().substring(0, 16) ?? 'Not in this session'}',
                style: TextStyle(
                  fontSize: 9,
                  color: context.colors.muted,
                  letterSpacing: .5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final String label, detail;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      side: BorderSide(color: context.colors.edge.withValues(alpha: .5)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: context.colors.panel,
    ),
    onPressed: onTap,
    child: Column(
      children: [
        WorkspaceIcon(icon, size: 33),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: context.colors.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 9, color: context.colors.muted),
        ),
      ],
    ),
  );
}
