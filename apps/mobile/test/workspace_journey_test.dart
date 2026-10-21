import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/main.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/app/router.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/core/design_system/appearance.dart';
import 'package:field_assist/core/design_system/workspace.dart';
import 'package:field_assist/features/authentication/access_screens.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';
import 'appearance_journey_test.dart' as journey;
import 'jobs_test.dart' as jobs;

// Synthetic view fixtures only: no API, microphone, GPS or real account is used.
const lead = <String, dynamic>{
  'id': 'qa-lead',
  'name': 'Demo · Ananya Rao',
  'avatarId': '3d_1',
  'jobTitle': 'Team lead',
  'department': 'Field Engineering',
  'role': 'TEAM_LEAD',
};
final chat = <String, dynamic>{
  'id': 'qa-conversation',
  'kind': 'direct',
  'title': lead['name'],
  'unread': 0,
  'participants': [
    lead,
    {'id': 'test-owner', 'name': 'Sam Fibre'},
  ],
};
final thread = <String, dynamic>{
  'conversation': chat,
  'nextBefore': null,
  'items': [
    {
      'id': 'message-1',
      'clientMessageId': 'message-1',
      'senderId': 'qa-lead',
      'text':
          'The visit brief is ready. Please check the cable label before starting.',
      'sequence': '1',
      'createdAt': '2026-10-16T03:15:00Z',
    },
    {
      'id': 'message-2',
      'clientMessageId': 'message-2',
      'senderId': 'test-owner',
      'text':
          'Thanks. I will capture the label and send the report after the visit.',
      'sequence': '2',
      'createdAt': '2026-10-16T03:16:00Z',
    },
  ],
};

class PreviewApi extends ApiClient {
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    if (route.startsWith('directory')) {
      return {
        'items': [lead],
      };
    }
    if (route.contains('/messages')) {
      return thread;
    }
    return {};
  }
}

class PreviewReports extends journey.MemoryReports {
  final metadataValues = <String, Object>{
    'conversation:qa-conversation': thread,
  };
  @override
  Future<Object?> metadata(String key) async => metadataValues[key];
  @override
  Future<void> setMetadata(String key, Object value) async {
    metadataValues[key] = value;
  }
}

class WorkspaceController extends journey.DesignController {
  final previewStore = PreviewReports(), previewApi = PreviewApi();
  @override
  SecureReportRepository get repository => previewStore;
  @override
  ApiClient get api => previewApi;
  @override
  AppState build() {
    final state = super.build();
    return state.copy(
      reduceMotion: true,
      offline: true,
      user: EngineerIdentity.fromJson({
        ...state.user!.toJson(),
        'avatarId': 'vibrent_6',
      }),
      reports: [
        for (final (id, status) in [
          ('demo-draft-001', ReportState.draft),
          ('demo-queued-002', ReportState.queued),
          ('demo-received-003', ReportState.accepted),
        ])
          LocalReport(
            id: id,
            ownerId: 'test-owner',
            schema: journey.schema,
            values: previewStore.values,
            state: status,
            revision: 1,
            entitlementId: journey.lease.id,
            updatedAt: DateTime(2026, 10, 16),
            receipt: status == ReportState.accepted
                ? {
                    'id': 'synthetic-receipt',
                    'receivedAt': '2026-10-16T03:00:00Z',
                  }
                : null,
          ),
      ],
      workOrders: [
        jobs.job(),
        jobs.job(
          status: 'follow_up',
          id: '80000000-0000-4000-8000-000000000002',
        ),
      ],
      operationsSyncedAt: DateTime(2026, 10, 16, 9, 15),
      collaboration: CollaborationState(
        teams: [
          {
            'id': 'qa-team',
            'name': 'Fibre Delivery',
            'department': 'Field Engineering',
            'leadId': 'qa-lead',
            'lead': lead,
          },
        ],
        conversations: [
          {...chat, 'lastMessage': (thread['items'] as List).last},
        ],
        notifications: [
          {
            'id': 'qa-notification',
            'kind': 'job.assigned',
            'title': 'A new visit is ready',
            'body': 'Inspect the cable at Orion hub.',
            'resourceId': jobs.job().id,
            'createdAt': '2026-10-16T03:10:00Z',
            'readAt': null,
          },
        ],
        unread: 1,
      ),
    );
  }

  @override
  Future<void> refreshCollaboration({bool quiet = false}) async {}
  @override
  Future<void> refreshOperations({bool quiet = false}) async {}
  @override
  Future<void> synchronize() async {}
  @override
  Future<void> readThread(String id, String sequence) async {}
  void lockForTest() {
    state = state.copy(stage: AccessStage.signedOut);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<ProviderContainer> setup(
    WidgetTester tester,
    Brightness brightness, {
    Size size = const Size(390, 844),
    double scale = 1,
    GlobalKey? boundary,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      overrides: [appProvider.overrideWith(WorkspaceController.new)],
    );
    addTearDown(container.dispose);
    container.read(appearanceProvider);
    await container
        .read(appearanceProvider.notifier)
        .select(
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: boundary, child: const FieldAssistApp()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> nav(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(TextButton, label));
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} navigation, report filters and auth theme isolation',
      (tester) async {
        const capture = bool.fromEnvironment('CAPTURE_WORKSPACE_UI');
        if (capture) {
          await tester.runAsync(() async {
            for (final family in ['Roboto', 'Ahem', 'MaterialIcons']) {
              final file = family == 'MaterialIcons'
                  ? 'MaterialIcons-Regular.otf'
                  : 'Roboto-Regular.ttf';
              await (FontLoader(family)..addFont(
                    File(
                      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/$file',
                    ).readAsBytes().then(ByteData.sublistView),
                  ))
                  .load();
            }
          });
        }
        final boundary = GlobalKey(),
            container = await setup(tester, brightness, boundary: boundary);
        Future<void> shot(String name) async {
          if (!capture) {
            return;
          }
          await tester.runAsync(() async {
            final picture =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../../docs/evidence/workspace-redesign-${brightness.name}-$name.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }

        expect(find.text('Start report'), findsOneWidget);
        await shot('home');
        await nav(tester, 'Jobs');
        expect(find.text('Your next visit,\nready to go.'), findsOneWidget);
        await shot('jobs');
        await nav(tester, 'Reports');
        expect(find.text('Queued'), findsOneWidget);
        await shot('reports');
        await tester.tap(find.widgetWithText(ChoiceChip, 'Drafts'));
        await tester.pumpAndSettle();
        expect(find.text('Queued'), findsNothing);
        expect(find.text('Draft'), findsOneWidget);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Received'));
        await tester.pumpAndSettle();
        expect(find.text('Draft'), findsNothing);
        expect(find.text('View receipt'), findsOneWidget);
        expect(container.read(appProvider).reports.length, 3);
        await nav(tester, 'Team');
        expect(find.text('Team chat'), findsOneWidget);
        await shot('team');
        container.read(routerProvider).push('/messages/qa-conversation');
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Thanks. I will capture the label and send the report after the visit.',
          ),
          findsOneWidget,
        );
        await shot('conversation');
        container.read(routerProvider).go('/settings');
        await tester.pumpAndSettle();
        expect(find.text('Light'), findsOneWidget);
        expect(find.text('Profile avatar'), findsOneWidget);
        await shot('settings');
        await tester.tap(find.text('Profile avatar'));
        await tester.pumpAndSettle();
        expect(find.text('Save avatar'), findsOneWidget);
        container.read(routerProvider).go('/alerts');
        await tester.pumpAndSettle();
        expect(find.text('A new visit is ready'), findsOneWidget);
        await shot('alerts');
        (container.read(appProvider.notifier) as WorkspaceController)
            .lockForTest();
        await tester.pumpAndSettle();
        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.byType(WorkspaceShell), findsNothing);
        expect(
          Theme.of(
            tester.element(find.byType(SignInScreen)),
          ).textTheme.headlineLarge!.fontSize,
          38,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
    testWidgets(
      '${brightness.name} small workspace supports keyboard and large text',
      (tester) async {
        final container = await setup(
          tester,
          brightness,
          size: const Size(320, 640),
          scale: 1.6,
        );
        await nav(tester, 'Reports');
        expect(find.text('Your reports'), findsOneWidget);
        await nav(tester, 'Team');
        await tester.tap(find.widgetWithText(ChoiceChip, 'People'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField));
        await tester.tap(find.byType(TextField));
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'Home'), findsNothing);
        await tester.enterText(find.byType(TextField), 'Ananya');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.text('Demo · Ananya Rao'), findsOneWidget);
        tester.view.resetViewInsets();
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await nav(tester, 'Profile');
        await tester.scrollUntilVisible(find.text('Lock workspace'), 200);
        expect(find.text('Lock workspace'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(container.read(appProvider).reports.length, 3);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
