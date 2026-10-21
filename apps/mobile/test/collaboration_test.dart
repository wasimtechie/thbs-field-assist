import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/jobs/work_order.dart';
import 'package:field_assist/features/jobs/jobs_screen.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';
import 'package:field_assist/features/collaboration/communication_screens.dart';
import 'jobs_test.dart' as jobs;

final team = {
  'id': 'team-1',
  'name': 'Fibre Delivery',
  'department': 'Fibre Installation',
  'leadId': 'lead-1',
  'lead': {'id': 'lead-1', 'name': 'Asha · Team Lead'},
  'members': [],
};
final conversation = {
  'id': 'chat-1',
  'kind': 'direct',
  'title': 'Asha · Team Lead',
  'unread': 0,
  'participants': [
    {'id': 'test-owner', 'name': 'Sam Fibre'},
    {'id': 'lead-1', 'name': 'Asha · Team Lead'},
  ],
};
final incoming = {
  'id': 'message-1',
  'clientMessageId': 'server-message-1',
  'sequence': '1',
  'senderId': 'lead-1',
  'text': 'Please use the east gate. Message me if site access is restricted.',
  'createdAt': '2026-10-16T08:00:00Z',
};

class CachedRepository extends jobs.JobReports {
  final cache = <String, Object>{};
  @override
  Future<Object?> metadata(String key) async => cache[key];
  @override
  Future<void> setMetadata(String key, Object value) async {
    cache[key] = value;
  }
}

class CommunicationApi extends ApiClient {
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    if (route.startsWith('conversations/chat-1/messages')) {
      return {
        'conversation': conversation,
        'items': [incoming],
        'nextBefore': null,
      };
    }
    if (route.startsWith('directory')) {
      return {
        'items': [
          {
            'id': 'lead-1',
            'name': 'Asha · Team Lead',
            'department': 'Fibre Installation',
            'email': 'lead@example.invalid',
            'teamName': 'Fibre Delivery',
            'leadName': 'Asha',
          },
        ],
      };
    }
    throw const ServiceFailure(
      'TEST_ONLY',
      'Synthetic transport unavailable',
      retryable: true,
    );
  }
}

class CommunicationsController extends jobs.JobController {
  final store = CachedRepository(), transport = CommunicationApi();
  String? response;
  @override
  SecureReportRepository get repository => store;
  @override
  ApiClient get api => transport;
  @override
  AppState build() => super.build().copy(
    workOrders: [
      WorkOrder.fromJson({
        ...jobs.job().source,
        'responseStatus': 'pending',
        'assignmentRevision': 2,
      }),
    ],
    collaboration: CollaborationState(
      teams: [team],
      conversations: [
        {...conversation, 'lastMessage': incoming},
      ],
      notifications: [
        {
          'id': 'alert-1',
          'kind': 'job.assigned',
          'resourceId': jobs.job().id,
          'title': 'New job assigned',
          'body': 'Synthetic client visit',
          'createdAt': '2026-10-16T08:00:00Z',
          'readAt': null,
        },
      ],
      unread: 1,
    ),
  );
  @override
  Future<void> refreshCollaboration({bool quiet = false}) async {}
  @override
  Future<void> respondToAssignment(
    WorkOrder job,
    String decision,
    String note,
  ) async {
    response = decision;
    state = state.copy(
      workOrders: [
        WorkOrder.fromJson({
          ...job.source,
          'responseStatus': decision,
          'responseNote': note,
          'responseQueued': true,
        }),
      ],
    );
  }

  void acknowledge(String text) {
    store.cache['conversation:chat-1'] = {
      'conversation': conversation,
      'items': [
        incoming,
        {
          'id': 'outgoing-2',
          'clientMessageId': 'pending-1',
          'sequence': '2',
          'senderId': 'test-owner',
          'text': text,
          'createdAt': '2026-10-16T08:01:00Z',
        },
      ],
    };
    state = state.copy(collaboration: state.collaboration.copy(pending: []));
  }

  @override
  Future<String> sendMessage(String conversationId, String text) async {
    state = state.copy(
      collaboration: state.collaboration.copy(
        pending: [
          {
            'id': 'pending-1',
            'kind': 'message',
            'route': 'conversations/$conversationId/messages',
            'payload': jsonEncode({
              'clientMessageId': 'pending-1',
              'text': text,
            }),
            'blocked': 0,
          },
        ],
      ),
    );
    return 'pending-1';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'pending and declined briefs cannot start, while a locally queued acceptance can',
    () {
      for (final decision in ['pending', 'declined']) {
        expect(
          WorkOrder.fromJson({
            ...jobs.job().source,
            'responseStatus': decision,
          }).canStart,
          false,
        );
      }
      expect(
        WorkOrder.fromJson({
          ...jobs.job().source,
          'responseStatus': 'accepted',
          'responseQueued': true,
        }).canStart,
        true,
      );
    },
  );
  test(
    'queued response recovery is bound to the exact assignment generation',
    () {
      final c = ProviderContainer(
        overrides: [appProvider.overrideWith(CommunicationsController.new)],
      );
      addTearDown(c.dispose);
      c.read(appProvider);
      final controller = c.read(appProvider.notifier),
          job = WorkOrder.fromJson({
            ...jobs.job().source,
            'responseStatus': 'pending',
            'assignmentRevision': 2,
          });
      Json action(int revision) => {
        'kind': 'response',
        'blocked': 0,
        'route': 'work-orders/${job.id}/response',
        'payload': jsonEncode({
          'assignmentRevision': revision,
          'decision': 'accepted',
          'note': '',
        }),
      };
      expect(
        controller.queuedWorkOrders([job], [action(1)]).single.canStart,
        false,
      );
      expect(
        controller.queuedWorkOrders([job], [action(2)]).single.responseQueued,
        true,
      );
      expect(
        controller
            .queuedWorkOrders(
              [job],
              [
                {...action(2), 'blocked': 1},
              ],
            )
            .single
            .canStart,
        false,
      );
    },
  );
  testWidgets(
    'decline requires a reason and queued acceptance is not presented as delivered',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = ProviderContainer(
        overrides: [appProvider.overrideWith(CommunicationsController.new)],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: fieldTheme(),
            home: JobDetailScreen(jobId: jobs.job().id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Decline'), 180);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Decline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send decline'));
      await tester.pumpAndSettle();
      expect(find.text('Give your lead a reason.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField),
        'Site access is not available today.',
      );
      await tester.tap(find.text('Send decline'));
      await tester.pumpAndSettle();
      expect(
        (c.read(appProvider.notifier) as CommunicationsController).response,
        'declined',
      );
      expect(c.read(appProvider).workOrders.single.responseQueued, true);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} team and message screens retain scoped contacts and queued status',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = ProviderContainer(
          overrides: [appProvider.overrideWith(CommunicationsController.new)],
        );
        addTearDown(c.dispose);
        final key = GlobalKey();
        Widget shell(Widget page) => UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: fieldTheme(brightness: brightness),
            home: RepaintBoundary(key: key, child: page),
          ),
        );
        await tester.pumpWidget(shell(const CommunicationsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Message lead'), findsOneWidget);
        expect(find.text('Team chat'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          shell(const ConversationScreen(conversationId: 'chat-1')),
        );
        await tester.pumpAndSettle();
        expect(find.text(incoming['text'] as String), findsOneWidget);
        await tester.enterText(
          find.byType(TextField),
          'I have arrived. Can you confirm the site contact?',
        );
        await tester.tap(find.byTooltip('Send message'));
        await tester.pumpAndSettle();
        expect(find.text('Queued · saved on this phone'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_COLLABORATION_UI')) {
          await tester.runAsync(() async {
            final render =
                    key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary,
                image = await render.toImage(pixelRatio: 2),
                bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '../../docs/evidence/collaboration-chat-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        (c.read(appProvider.notifier) as CommunicationsController).acknowledge(
          'I have arrived. Can you confirm the site contact?',
        );
        await tester.pumpAndSettle();
        expect(find.text('Queued · saved on this phone'), findsNothing);
        expect(
          find.text('I have arrived. Can you confirm the site contact?'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
