import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_controller.dart';
import 'avatar_picker.dart';
import '../../core/design_system/profile_avatar.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/appearance.dart';
import '../../core/design_system/workspace.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider),
        controller = ref.read(appProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Your settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 25),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  colors: [context.colors.raised, context.colors.panel],
                ),
              ),
              child: Row(
                children: [
                  ProfileAvatar(
                    name: app.user?.name ?? 'Engineer',
                    avatarId: app.user?.avatarId ?? '',
                    size: 63,
                  ),
                  const SizedBox(width: 17),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.user?.name ?? 'Engineer',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.6,
                            color: context.colors.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          app.user?.typeName ?? 'Your workspace',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.muted,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          app.user?.email ?? '',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.muted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 23),
            const WorkspaceSection('Make it yours'),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: AppearancePicker(),
              ),
            ),
            const SizedBox(height: 7),
            const Card(
              child: ExpansionTile(
                leading: WorkspaceIcon(Icons.face_outlined, size: 38),
                title: Text('Profile avatar'),
                subtitle: Text('Choose your look'),
                shape: Border(),
                collapsedShape: Border(),
                childrenPadding: EdgeInsets.fromLTRB(10, 0, 10, 12),
                children: [AvatarPicker()],
              ),
            ),
            const SizedBox(height: 20),
            const WorkspaceSection('Voice & interaction'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const WorkspaceIcon(
                      Icons.volume_up_outlined,
                      size: 36,
                    ),
                    title: const Text(
                      'Spoken questions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: const Text(
                      'Spoken questions work offline',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: app.playback,
                    onChanged: (v) => controller.settings(playback: v),
                  ),
                  Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: context.colors.edge.withValues(alpha: .6),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 17, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Speech rate',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              '${app.speechRate.toStringAsFixed(1)}×',
                              style: TextStyle(
                                color: context.colors.indigo,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          min: .7,
                          max: 1.5,
                          divisions: 8,
                          value: app.speechRate,
                          onChanged: (v) => controller.settings(rate: v),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: context.colors.edge.withValues(alpha: .6),
                  ),
                  SwitchListTile(
                    secondary: const WorkspaceIcon(
                      Icons.motion_photos_off_outlined,
                      size: 36,
                    ),
                    title: const Text(
                      'Reduce motion',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: const Text(
                      'Also respects the system preference',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: app.reduceMotion,
                    onChanged: (v) => controller.settings(reduced: v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const WorkspaceSection('Workspace & access'),
            Card(
              child: ExpansionTile(
                leading: WorkspaceIcon(
                  Icons.verified_user_outlined,
                  color: context.colors.teal,
                  size: 38,
                ),
                title: const Text('Offline readiness'),
                subtitle: Text(
                  app.voiceReady
                      ? 'Voice package verified'
                      : 'Manual capture available',
                ),
                shape: const Border(),
                collapsedShape: const Border(),
                childrenPadding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                children: [
                  _Status(
                    'Encrypted database',
                    controller.repository.cipherVersion?.isNotEmpty == true
                        ? 'Verified on this device'
                        : 'Not verified',
                    Icons.lock_outline_rounded,
                  ),
                  _Status(
                    'Installed form',
                    '${app.form?.title ?? 'Not assigned'} · v${app.form?.versionNumber ?? '—'}',
                    Icons.assignment_outlined,
                  ),
                  _Status(
                    'Offline lease',
                    'Expires ${app.lease?.expiresAt.toLocal().toString().substring(0, 16) ?? 'not verified'}',
                    Icons.schedule_rounded,
                  ),
                  _Status(
                    'Voice assets',
                    app.voiceReady
                        ? 'Verified · offline speech check passed'
                        : 'Not ready · connect to repair',
                    Icons.mic_none_rounded,
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: app.busy ? null : controller.synchronize,
                      icon: const MotionIcon(Icons.sync_rounded, size: 18),
                      label: Text(
                        app.busy ? 'Checking…' : 'Sync & repair package',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 7),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const WorkspaceIcon(
                      Icons.lock_outline_rounded,
                      size: 38,
                    ),
                    title: const Text('Lock workspace'),
                    trailing: const MotionIcon(
                      Icons.chevron_right_rounded,
                      size: 19,
                    ),
                    onTap: controller.lock,
                  ),
                  Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: context.colors.edge.withValues(alpha: .6),
                  ),
                  ListTile(
                    leading: WorkspaceIcon(
                      Icons.logout_rounded,
                      color: context.colors.danger,
                      size: 38,
                    ),
                    title: Text(
                      'Sign out',
                      style: TextStyle(color: context.colors.danger),
                    ),
                    subtitle: const Text(
                      'Pending reports stay encrypted for your account',
                    ),
                    trailing: const MotionIcon(
                      Icons.chevron_right_rounded,
                      size: 19,
                    ),
                    onTap: controller.signOut,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ErrorNotice(app.error),
            Center(
              child: TextButton(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'THBS Field Assist',
                ),
                child: const Text('Legal notices'),
              ),
            ),
            Text(
              'THBS Field Assist 0.1.0 · Synthetic demo\nNo cloud AI in the core voice journey',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 9,
                height: 1.9,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.title, this.detail, this.icon);
  final String title, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MotionIcon(icon, color: context.colors.teal, size: 19),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.muted,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
