import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'app_controller.dart';
import '../features/authentication/access_screens.dart';
import '../features/home/home_screen.dart';
import '../core/design_system/workspace.dart';
import '../features/forms/form_screen.dart';
import '../features/sync/queue_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/jobs/jobs_screen.dart';
import '../features/collaboration/communication_screens.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final stage = ref.watch(appProvider.select((s) => s.stage));
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      final required = switch (stage) {
        AccessStage.booting => '/loading',
        AccessStage.signedOut => '/login',
        AccessStage.locked => '/unlock',
        AccessStage.provisioning => '/provision',
        AccessStage.ready => null,
      };
      if (required != null && state.matchedLocation != required) {
        return required;
      }
      if (required == null &&
          [
            '/loading',
            '/login',
            '/unlock',
            '/provision',
          ].contains(state.matchedLocation)) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/unlock', builder: (_, _) => const UnlockScreen()),
      GoRoute(path: '/provision', builder: (_, _) => const ProvisionScreen()),
      ShellRoute(
        builder: (_, state, child) =>
            WorkspaceShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/jobs', builder: (_, _) => const JobsScreen()),
          GoRoute(
            path: '/jobs/:id',
            builder: (_, s) => JobDetailScreen(jobId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/forms/:id',
            builder: (_, s) => FormScreen(reportId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/review/:id',
            builder: (_, s) => ReviewScreen(reportId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/receipt/:id',
            builder: (_, s) =>
                LocalReceiptScreen(reportId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/queue', builder: (_, _) => const QueueScreen()),
          GoRoute(
            path: '/messages',
            builder: (_, _) => const CommunicationsScreen(),
          ),
          GoRoute(
            path: '/messages/:id',
            builder: (_, s) =>
                ConversationScreen(conversationId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        ],
      ),
    ],
  );
});
