import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/sync/queue_screen.dart';
import 'package:field_assist/features/jobs/jobs_screen.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/closure/closure_screen.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/visit_summary_receipt_screen.dart';
import 'package:field_assist/features/forms/form_screen.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'closure_journey_test.dart' as full;
import 'support/voice_fakes.dart';

class CompactReports extends full.ClosureReports {
  bool failSummaryWrite = false;
  @override
  Future<void> setMetadata(String key, Object value) async {
    if (failSummaryWrite && key.startsWith('closure-demo-summary:')) {
      throw StateError('Synthetic write failure');
    }
    data[key] = value;
  }
}

class SummaryApi extends ApiClient {
  SummaryApi() : super(baseUrl: 'https://demo.invalid/api/v1/');
  final submitted = <Json>[];
  bool offline = false;
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    expect(route, 'visit-summaries');
    if (offline) {
      throw const ServiceFailure('NETWORK', 'Unavailable', retryable: true);
    }
    expect(method, 'POST');
    submitted.add(body as Json);
    return {
      'id': 'synthetic-summary-receipt',
      'receivedAt': '2026-10-22T00:00:00Z',
    };
  }
}

class CompactController extends full.VoiceClosureController {
  final summaryApi = SummaryApi();
  @override
  SummaryApi get api => summaryApi;
  CompactController({CompactReports? records})
    : compactRecords = records ?? CompactReports();
  final CompactReports compactRecords;
  @override
  CompactReports get records => compactRecords;
}

Future<void> utter(WidgetTester tester, TestAudio audio) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
  audio.feed();
  audio.meter!(.05);
  audio.bytes!(Uint8List(80000));
  audio.meter!(0);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'five summary fields have no hidden activation dependencies and do not replace the closure policy',
    () {
      final compact = compactClosureForm(full.closureForm);
      expect(compact.fields.map((f) => f.id), compactClosureLabels.keys);
      expect(compact.visibleFields({}), hasLength(5));
      expect(compact.fields.any((f) => f.id == 'serving_asset'), false);
      expect(compact.source['closurePolicy'], isNull);
      expect(full.closureForm.source['closurePolicy'], isNotNull);
      expect(full.closureForm.fields.length, greaterThan(6));
      expect(compact.fields[1].options.first.label, 'Work completed');
      expect(
        closureSpokenAnswer(compact.fields[1], 'referral')?.toJson(),
        'referred',
      );
    },
  );

  testWidgets(
    'five-field voice journey handles asset/result homophones and reviews without bypassing full closure',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = TestAudio([]);
      final container = ProviderContainer(
        overrides: [
          appProvider.overrideWith(CompactController.new),
          voiceAudioFactoryProvider.overrideWithValue(() => audio),
        ],
      );
      addTearDown(container.dispose);
      final controller =
          container.read(appProvider.notifier) as CompactController;
      final original = encodeAnswers(controller.records.values);
      late GoRouter router;
      Future<void> show() async {
        router = GoRouter(
          initialLocation: '/forms/closure-test',
          routes: [
            GoRoute(
              path: '/forms/:id',
              builder: (_, _) => const ClosureScreen(reportId: 'closure-test'),
            ),
            GoRoute(
              path: '/visit-summaries/:id',
              builder: (_, s) =>
                  VisitSummaryReceiptScreen(summaryId: s.pathParameters['id']!),
            ),
            GoRoute(
              path: '/jobs',
              builder: (_, s) => JobsScreen(
                showCompleted: s.uri.queryParameters['view'] == 'completed',
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: DefaultAssetBundle(
              bundle: TestQuestionAssets(),
              child: MaterialApp.router(
                routerConfig: router,
                theme: fieldTheme(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show();
      expect(find.text('5 fields. One conversation.'), findsOneWidget);
      controller.engine.answer =
          'Installed ONT in the living room. Used existing duct. The serving asset is paule one two three. Optical receive -18.2 dBm. Service test past. The job is fully completed.';
      await tester.tap(find.text('Fill with voice AI'));
      await tester.pumpAndSettle();
      await utter(tester, audio);
      expect(find.text('Anything else?'), findsOneWidget);
      expect(controller.engine.extractionCalls, 0);
      controller.engine.answer = 'Customer shown the equipment.';
      await utter(tester, audio);
      final nextAction = compactClosureForm(full.closureForm).fields.last;
      expect(find.text(closureSpokenQuestion(nextAction)), findsWidgets);
      controller.engine.answer = 'No further work required';
      await utter(tester, audio);
      expect(find.text('Review visit summary'), findsOneWidget);
      expect(find.byType(AnswerInput), findsNothing);
      final saved =
          controller.records.data['closure-demo-summary:closure-test'] as Json;
      expect(saved['values'].length, 5);
      expect(saved['values']['serving_asset'], isNull);
      expect(saved['sources']['serving_asset'], isNull);
      expect(
        controller.engine.events,
        isNot(
          contains(
            'speak:${closureSpokenQuestion(full.closureForm.fields.firstWhere((f) => f.id == 'serving_asset'))}',
          ),
        ),
      );
      expect(
        saved['values']['actual_work'],
        contains('Customer shown the equipment.'),
      );
      expect(saved['values']['optical_rx_dbm'], -18.2);
      expect(saved['values']['operational_test'], 'passed');
      expect(saved['operationalClosureApproved'], false);
      expect(encodeAnswers(controller.records.values), original);
      await tester.tap(find.text('Complete visit & submit'));
      await tester.pumpAndSettle();
      expect(find.text('Visit summary submitted'), findsOneWidget);
      expect(find.text('Receipt: synthetic-summary-receipt'), findsOneWidget);
      expect(controller.api.submitted, hasLength(1));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/jobs?view=completed',
      );
      expect(find.text('Review visit summary'), findsNothing);
      expect(find.text('5 fields. One conversation.'), findsNothing);
      expect(controller.records.current, ReportState.draft);
      router.go('/forms/closure-test');
      await tester.pumpAndSettle();
      expect(find.textContaining('Submitted · Dashboard'), findsOneWidget);
      await tester.tap(find.text('Reset answers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep answers'));
      await tester.pumpAndSettle();
      expect(find.textContaining('5 of 5 filled'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await show();
      expect(find.textContaining('5 of 5 filled'), findsOneWidget);
      expect(
        (controller.records.data['closure-demo-summary:closure-test']
            as Json)['values']['serving_asset'],
        isNull,
      );
      await tester.tap(find.text('Reset answers'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset answers'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 of 5 filled'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await show();
      expect(find.textContaining('0 of 5 filled'), findsOneWidget);
      expect(encodeAnswers(controller.records.values), original);
      await tester.scrollUntilVisible(
        find.text('Open full closure checks'),
        250,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open full closure checks'));
      await tester.pumpAndSettle();
      expect(find.text('FTTP closure assistant'), findsOneWidget);
      expect(encodeAnswers(controller.records.values), original);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'offline review shows a queued confirmation, restores it and later displays the actual receipt',
    (tester) async {
      final records = CompactReports();
      records.data['closure-demo-summary:closure-test'] = {
        'values': {
          'actual_work': 'Installed ONT',
          'claimed_outcome': 'completed',
          'serving_asset': 'CBT-SYN-10',
          'optical_rx_dbm': -18.2,
          'operational_test': 'passed',
          'next_action': 'No further work',
        },
        'sources': {},
      };
      final first = CompactController(records: records)..api.offline = true;
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(() => first)],
      );
      final router = GoRouter(
        initialLocation: '/forms/closure-test',
        routes: [
          GoRoute(
            path: '/forms/:id',
            builder: (_, _) => const ClosureScreen(reportId: 'closure-test'),
          ),
          GoRoute(
            path: '/visit-summaries/:id',
            builder: (_, s) =>
                VisitSummaryReceiptScreen(summaryId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/jobs',
            builder: (_, s) => JobsScreen(
              showCompleted: s.uri.queryParameters['view'] == 'completed',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router, theme: fieldTheme()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review 5-field summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete visit & submit'));
      await tester.pumpAndSettle();
      expect(
        find.text('Saved on this device · Waiting to sync'),
        findsOneWidget,
      );
      expect(find.textContaining('Receipt:'), findsNothing);
      expect(first.api.submitted, isEmpty);
      expect(
        container.read(appProvider).summarySubmissions.single['status'],
        'waiting',
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      final reopened = CompactController(records: records);
      final restored = ProviderContainer(
        overrides: [appProvider.overrideWith(() => reopened)],
      );
      addTearDown(restored.dispose);
      restored.read(appProvider);
      await reopened.reloadSummarySubmissions();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: restored,
          child: MaterialApp(theme: fieldTheme(), home: const QueueScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Submitted on device · Waiting to sync'),
        findsOneWidget,
      );
      expect(
        await reopened.flushVisitSummaries(
          restored.read(appProvider).user!.id,
          manual: true,
        ),
        true,
      );
      await tester.pumpAndSettle();
      expect(find.text('Visit summary received'), findsOneWidget);
      expect(find.text('Receipt: synthetic-summary-receipt'), findsOneWidget);
      expect(reopened.api.submitted, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a failed reset retains the prior answers, transcript and review, and can retry',
    (tester) async {
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(CompactController.new)],
      );
      addTearDown(container.dispose);
      final controller =
          container.read(appProvider.notifier) as CompactController;
      controller.records.values = {
        ...controller.records.values,
        'actual_work': const TextAnswer('Full operational draft work'),
        'optical_rx_dbm': const NumberAnswer(-30.2),
      };
      final original = encodeAnswers(controller.records.values);
      final summary = <String, dynamic>{
        'values': {
          'actual_work': 'Recorded demo work',
          'claimed_outcome': 'completed',
        },
        'sources': {
          'actual_work': {
            'sourceType': 'speech',
            'sourceSpan': 'Recorded demo work',
          },
        },
        'reviewedAt': '2026-10-22T00:00:00Z',
        'operationalClosureApproved': false,
      };
      controller.records.data['closure-demo-summary:closure-test'] = summary;
      controller.records.failSummaryWrite = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fieldTheme(),
            home: const ClosureScreen(reportId: 'closure-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset answers'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset answers'));
      await tester.pumpAndSettle();
      expect(find.text('Recorded demo work'), findsOneWidget);
      expect(find.textContaining('Could not reset.'), findsOneWidget);
      expect(
        controller.records.data['closure-demo-summary:closure-test'],
        summary,
      );
      expect(encodeAnswers(controller.records.values), original);
      controller.records.failSummaryWrite = false;
      await tester.tap(find.text('Reset answers'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reset answers'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 of 5 filled'), findsOneWidget);
      expect(
        (controller.records.data['closure-demo-summary:closure-test']
            as Json)['reviewedAt'],
        isNull,
      );
      expect(encodeAnswers(controller.records.values), original);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
