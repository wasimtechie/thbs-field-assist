import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../persistence/account_secure_storage.dart';
import 'theme.dart';

final appearanceProvider = NotifierProvider<AppearanceController, ThemeMode>(
  AppearanceController.new,
);

/// Appearance is a device preference, available before account unlock.
class AppearanceController extends Notifier<ThemeMode> {
  static const storage = AccountSecureStorage(options: IOSOptions());
  int revision = 0;
  ThemeMode persisted = ThemeMode.light;
  Future<void> writes = Future.value();
  @override
  ThemeMode build() {
    var disposed = false;
    ref.onDispose(() => disposed = true);
    final initialRevision = revision;
    Future<void>(() async {
      try {
        final saved = await storage.read(key: 'appearance-mode');
        if (!disposed && revision == initialRevision) {
          state = ThemeMode.values.firstWhere(
            (m) => m.name == saved,
            orElse: () => ThemeMode.light,
          );
          persisted = state;
        }
      } catch (_) {
        /* Keep the original light theme if secure storage is unavailable. */
      }
    });
    return ThemeMode.light;
  }

  Future<void> select(ThemeMode mode) async {
    final selection = ++revision;
    state = mode;
    final write = writes
        .catchError((_) {})
        .then((_) => storage.write(key: 'appearance-mode', value: mode.name));
    writes = write;
    try {
      await write;
      persisted = mode;
    } catch (_) {
      if (selection == revision) state = persisted;
      rethrow;
    }
  }
}

class AppearanceButton extends ConsumerWidget {
  const AppearanceButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: 'Change appearance',
    icon: MotionIcon(
      Theme.of(context).brightness == Brightness.dark
          ? Icons.dark_mode_outlined
          : Icons.light_mode_outlined,
    ),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      builder: (_) => const SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: AppearancePicker(),
        ),
      ),
    ),
  );
}

class AppearancePicker extends ConsumerWidget {
  const AppearancePicker({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Eyebrow('Appearance'),
        const SizedBox(height: 10),
        Text(
          'Light, dark, or match your device.',
          style: TextStyle(fontSize: 13, color: context.colors.muted),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in [
              ThemeMode.light,
              ThemeMode.dark,
              ThemeMode.system,
            ])
              Semantics(
                selected: mode == option,
                inMutuallyExclusiveGroup: true,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    backgroundColor: mode == option
                        ? context.colors.raised
                        : context.colors.panel,
                    side: BorderSide(
                      color: mode == option
                          ? context.colors.indigo
                          : context.colors.edge,
                    ),
                  ),
                  onPressed: () async {
                    try {
                      await ref
                          .read(appearanceProvider.notifier)
                          .select(option);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Appearance could not be saved. Please try again.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: MotionIcon(
                    mode == option
                        ? Icons.check_rounded
                        : switch (option) {
                            ThemeMode.system => Icons.brightness_auto_outlined,
                            ThemeMode.light => Icons.light_mode_outlined,
                            ThemeMode.dark => Icons.dark_mode_outlined,
                          },
                    size: 16,
                  ),
                  label: Text(switch (option) {
                    ThemeMode.system => 'System',
                    ThemeMode.light => 'Light',
                    ThemeMode.dark => 'Dark',
                  }),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
