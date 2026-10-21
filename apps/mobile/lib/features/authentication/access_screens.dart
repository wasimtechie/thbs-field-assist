import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_controller.dart';
import '../../core/networking/api_client.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/appearance.dart';
import 'auth_layout.dart';
import '../../core/design_system/profile_avatar.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(), password = TextEditingController();
  final scrollController = ScrollController();
  bool visible = false;
  @override
  void dispose() {
    scrollController.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _connection() async {
    final key = GlobalKey<FormState>();
    var address = ref.read(appProvider.notifier).api.dio.options.baseUrl;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Connect to your workspace'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use the server address supplied by your administrator. For a laptop demo, both devices need a shared local Wi-Fi network. Initial login needs access to this server.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                initialValue: address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (v) => address = v,
                decoration: const InputDecoration(
                  labelText: 'Server address',
                  hintText: 'https://your-field-assist-server.com',
                ),
                validator: (v) {
                  try {
                    normalizeServerAddress(v ?? '');
                    return null;
                  } on FormatException catch (e) {
                    return e.message;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) Navigator.pop(context, address);
            },
            child: const Text('Save connection'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      await ref.read(appProvider.notifier).configureServer(value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server address saved. Sign in to connect.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  void _help() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Let’s get you back in'),
      content: const Text(
        'Your administrator can reset your password from Field engineers in the dashboard. Ask them to confirm your account is active and your engineer type has a published form. Then return here to sign in.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  bool gettingAccess = false;
  void _access(bool value) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      gettingAccess = value;
      if (value) visible = false;
    });
    if (scrollController.hasClients) scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    return AuthLayout(
      title: gettingAccess
          ? 'Work better.\nTogether.'
          : 'Ready for\nthe field.',
      subtitle: gettingAccess
          ? 'A connected team starts with the right access.'
          : 'Your work. Your team. One connected workspace.',
      paused: app.busy,
      scrollController: scrollController,
      onBack: gettingAccess ? () => _access(false) : null,
      child: gettingAccess
          ? _GetAccessPanel(
              onSignIn: () => _access(false),
              onConnection: _connection,
            )
          : AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const AuthPanelHeading(
                      title: 'Welcome back.',
                      subtitle: 'Sign in to your engineer workspace.',
                    ),
                    const SizedBox(height: 25),
                    ErrorNotice(app.error),
                    TextFormField(
                      controller: email,
                      enabled: !app.busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: authInputDecoration(
                        context,
                        label: 'Work email',
                        icon: Icons.mail_outline_rounded,
                      ),
                      validator: (v) =>
                          v != null &&
                              RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(v.trim())
                          ? null
                          : 'Enter your work email.',
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: password,
                      enabled: !app.busy,
                      obscureText: !visible,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: authInputDecoration(
                        context,
                        label: 'Password',
                        icon: Icons.lock_outline_rounded,
                        suffix: IconButton(
                          tooltip: visible ? 'Hide password' : 'Show password',
                          onPressed: () => setState(() => visible = !visible),
                          icon: MotionIcon(
                            visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your password.'
                          : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: app.busy ? null : _help,
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FilledButton(
                      style: authPrimaryStyle(),
                      onPressed: app.busy ? null : _submit,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (app.busy) ...[
                            const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Flexible(
                            child: Text(app.busy ? 'Signing in…' : 'Sign in'),
                          ),
                          if (!app.busy) ...[
                            const SizedBox(width: 13),
                            const MotionIcon(
                              Icons.arrow_forward_rounded,
                              size: 19,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'New to Field Assist?',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.colors.muted,
                            ),
                          ),
                          TextButton(
                            onPressed: app.busy ? null : () => _access(true),
                            child: const Text(
                              'Get access',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 18),
                    Center(
                      child: TextButton.icon(
                        onPressed: app.busy ? null : _connection,
                        icon: const MotionIcon(Icons.dns_outlined, size: 15),
                        label: const Text(
                          'Connection settings',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const AuthFootnote(),
                  ],
                ),
              ),
            ),
    );
  }

  void _submit() {
    if (ref.read(appProvider).busy || gettingAccess) return;
    if (form.currentState!.validate()) {
      ref.read(appProvider.notifier).signIn(email.text.trim(), password.text);
    }
  }
}

class _GetAccessPanel extends StatelessWidget {
  const _GetAccessPanel({required this.onSignIn, required this.onConnection});
  final VoidCallback onSignIn, onConnection;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ExcludeSemantics(
        child: SizedBox(
          height: 49,
          width: 140,
          child: Stack(
            children: [
              for (final (i, avatar) in [
                '3d_1',
                '3d_2',
                '3d_3',
                '3d_4',
              ].indexed)
                Positioned(
                  left: i * 29,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: context.colors.panel,
                      shape: BoxShape.circle,
                    ),
                    child: ProfileAvatar(
                      name: 'Illustrative profile',
                      avatarId: avatar,
                      size: 41,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      Text(
        'A place on your team.',
        style: TextStyle(
          fontSize: 27,
          height: 1.2,
          letterSpacing: -.9,
          fontWeight: FontWeight.w700,
          color: context.colors.ink,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        'Your organisation sets up your account, squad and the right forms for your work.',
        style: TextStyle(
          fontSize: 13,
          height: 1.7,
          color: context.colors.muted,
        ),
      ),
      const SizedBox(height: 24),
      for (final (number, title, detail) in [
        (
          '01',
          'Connect with your administrator',
          'Share your work email and engineer type.',
        ),
        (
          '02',
          'Get your workspace details',
          'Your administrator creates your account and provides the server address and initial password.',
        ),
        (
          '03',
          'Make your first connection',
          'Sign in online to set up your forms. Then unlock securely and work offline.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 19),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 31,
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.colors.raised,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  number,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: context.colors.indigo,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.65,
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 5),
      FilledButton(
        onPressed: onSignIn,
        style: authPrimaryStyle(),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(child: Text('I have my details')),
            SizedBox(width: 12),
            MotionIcon(Icons.arrow_forward_rounded, size: 19),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: onConnection,
          icon: const MotionIcon(Icons.dns_outlined, size: 15),
          label: const Text(
            'Connection settings',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ),
      const AuthFootnote(),
    ],
  );
}

class UnlockScreen extends ConsumerWidget {
  const UnlockScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider),
        controller = ref.read(appProvider.notifier);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Row(
                  children: [
                    Expanded(child: Brand()),
                    AppearanceButton(),
                  ],
                ),
                const SizedBox(height: 60),
                Container(
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    color: context.colors.raised,
                    shape: BoxShape.circle,
                  ),
                  child: MotionIcon(
                    Icons.fingerprint_rounded,
                    size: 62,
                    color: context.colors.indigo,
                  ),
                ),
                const SizedBox(height: 27),
                Text(
                  'Welcome back,\n${app.user?.name.split(' ').first ?? 'engineer'}.',
                  style: Theme.of(context).textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  app.user?.typeName ?? 'Your protected workspace',
                  style: TextStyle(color: context.colors.muted),
                ),
                const SizedBox(height: 30),
                ErrorNotice(app.error),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: app.busy ? null : controller.unlock,
                    icon: const MotionIcon(Icons.lock_open_rounded),
                    label: Text(app.busy ? 'Unlocking…' : 'Unlock securely'),
                  ),
                ),
                const SizedBox(height: 15),
                Text(
                  'Use your device biometrics or passcode. Offline access is limited to your signed 72-hour lease.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.muted,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 22),
                TextButton(
                  onPressed: app.busy ? null : controller.signOut,
                  child: const Text('Reconnect and sign in online'),
                ),
                const SizedBox(height: 30),
                Text(
                  'Pending reports stay encrypted for their owner.',
                  style: TextStyle(fontSize: 12, color: context.colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProvisionScreen extends ConsumerWidget {
  const ProvisionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider),
        controller = ref.read(appProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Prepare for offline work')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(27),
          children: [
            const SizedBox(height: 20),
            MotionIcon(
              Icons.cloud_download_outlined,
              size: 58,
              color: context.colors.indigo,
            ),
            const SizedBox(height: 27),
            Text(
              'A little preparation.\nA lot of freedom.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Keep this app open while we securely install your assigned form and local voice package.',
              style: TextStyle(color: context.colors.muted, height: 1.8),
            ),
            const SizedBox(height: 35),
            LinearProgressIndicator(
              value: app.progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 14),
            Text(
              app.step,
              style: TextStyle(fontSize: 14, color: context.colors.muted),
            ),
            const SizedBox(height: 26),
            _ProvisionRow('Authorized offline lease', app.lease != null),
            _ProvisionRow(
              'Assigned form and integrity check',
              app.form != null,
            ),
            _ProvisionRow('Encrypted local storage', app.form != null),
            _ProvisionRow('Offline voice assistance', app.voiceReady),
            _ProvisionRow('Offline speech check', app.voiceReady),
            const SizedBox(height: 24),
            ErrorNotice(app.error),
            if (!app.busy) ...[
              FilledButton.icon(
                onPressed: controller.provision,
                icon: const MotionIcon(Icons.refresh_rounded),
                label: const Text('Retry provisioning'),
              ),
              TextButton(
                onPressed: controller.signOut,
                child: const Text('Back to sign in'),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Readiness is checked, never assumed. Incomplete voice packages are not marked ready.',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.muted,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProvisionRow extends StatelessWidget {
  const _ProvisionRow(this.label, this.done);
  final String label;
  final bool done;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        MotionIcon(
          done
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          size: 20,
          color: done ? context.colors.teal : context.colors.edge,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: done ? context.colors.ink : context.colors.muted,
              fontSize: 14,
            ),
          ),
        ),
      ],
    ),
  );
}
