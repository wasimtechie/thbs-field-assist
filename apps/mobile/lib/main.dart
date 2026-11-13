import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app_controller.dart';
import 'app/router.dart';
import 'core/design_system/theme.dart';
import 'core/design_system/appearance.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Alohe avatars',
    ], await rootBundle.loadString('assets/avatars/LICENSE.txt'));
  });
  runApp(const ProviderScope(child: FieldAssistApp()));
}

class FieldAssistApp extends ConsumerStatefulWidget {
  const FieldAssistApp({super.key});
  @override
  ConsumerState<FieldAssistApp> createState() => _FieldAssistAppState();
}

class _FieldAssistAppState extends ConsumerState<FieldAssistApp>
    with WidgetsBindingObserver {
  final messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appProvider.notifier);
    if (controller.demoAccess.matches(ref.read(appProvider).user?.email)) {
      return;
    }
    if ([
          AppLifecycleState.paused,
          AppLifecycleState.detached,
        ].contains(state) &&
        ref.read(appProvider).stage == AccessStage.ready) {
      unawaited(ref.read(appProvider.notifier).lock());
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    ref.listen(appProvider, (previous, next) {
      if (next.stage != AccessStage.ready) {
        messenger.currentState?.clearSnackBars();
        return;
      }
      final newest = next.collaboration.notifications.firstOrNull,
          prior = previous?.collaboration.notifications.firstOrNull;
      if (newest != null &&
          newest['readAt'] == null &&
          newest['id'] != prior?['id']) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || ref.read(appProvider).stage != AccessStage.ready) {
            return;
          }
          messenger.currentState?.clearSnackBars();
          messenger.currentState?.showSnackBar(
            SnackBar(
              content: Text(newest['title'] as String),
              duration: const Duration(seconds: 6),
              action: SnackBarAction(
                label: 'View alerts',
                onPressed: () => router.push('/alerts'),
              ),
            ),
          );
        });
      }
    });
    final reduceMotion =
        ref.watch(appProvider.select((s) => s.reduceMotion)) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    return MaterialApp.router(
      title: 'THBS Field Assist',
      scaffoldMessengerKey: messenger,
      debugShowCheckedModeBanner: false,
      theme: fieldTheme(),
      darkTheme: fieldTheme(brightness: Brightness.dark),
      themeMode: ref.watch(appearanceProvider),
      themeAnimationDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      themeAnimationCurve: Curves.easeOutCubic,
      routerConfig: router,
      builder: (context, child) {
        final reduced = ref.watch(appProvider.select((s) => s.reduceMotion));
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations:
                MediaQuery.disableAnimationsOf(context) || reduced,
          ),
          child: child!,
        );
      },
    );
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
