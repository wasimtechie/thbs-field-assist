import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/closure/closure_screen.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/visit_summary_receipt_screen.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'compact_closure_test.dart' as fixture;
import 'closure_journey_test.dart' as full;
import 'support/voice_fakes.dart';

const rehearsal =
    'The customer granted access. The customer approved the ONT location in the living room. '
    'I used the existing duct for the fibre route. '
    'I installed the external fibre and connection point. '
    'I fitted the internal fibre to the ONT. '
    'I installed the ONT in the living room. '
    'The optical receive reading was minus eighteen point two dBm. '
    'The service test passed. The installation work is fully completed.';

const missingIds = [
  'ont_status_checked',
  'service_live',
  'customer_handover',
  'site_handover_safe',
  'next_action',
];

const completeRehearsal =
    'The customer granted access for the visit. '
    'The customer approved the ONT location in the living room, and I installed the ONT there. '
    'I used the existing duct for the fibre route. '
    'I installed the external fibre and connection point, then fitted the internal fibre to the ONT. '
    'I checked the ONT power and status. '
    'The optical receive reading was minus eighteen point two dBm. '
    'The service test passed and the service is live. '
    'I showed the customer the equipment. '
    'The installation is fully completed, and I left the site safe and tidy. '
    'No further work is required.';

// Exact text observed in the user's simulator on 27 October. Keep the
// garbled measurement unresolved rather than replacing it with the script.
const observedTranscript =
    'The customer granted access for the visit The customer. Approve the ONT location in the living room. '
    'and install the ONT there I use the existing duct for the fibre route. '
    'I also installed the external fibre and connection point Then fitted the internal fibre to the OND '
    'I checked the ONT power and status The optical receive reading was -18.99 Two dBm. '
    'The service test was passed and now the service is live I showed the customer the equipment '
    "the installation was fully completed And I'll let this side safe and tidy. No further work is required.";

class AssignedReports extends fixture.CompactReports {
  AssignedReports() {
    values = decodeAnswers({'scenario': 'S1', 'work_stage': 'final_provision'});
  }
  @override
  Future<LocalReport> get(String id) async {
    final r = await super.get(id);
    return LocalReport(
      id: r.id,
      ownerId: r.ownerId,
      schema: r.schema,
      values: r.values,
      state: r.state,
      revision: r.revision,
      entitlementId: r.entitlementId,
      updatedAt: r.updatedAt,
      workOrderId: '87d3d394-eacd-4a8c-b04c-554bdcc2d25a',
    );
  }
}

class ExpandedController extends fixture.CompactController {
  ExpandedController() : super(records: AssignedReports());
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  final form = compactClosureForm(full.closureForm, expanded: true);
  Map<String, dynamic> values(String text) => {
    for (final f in compactNarrativeFacts(form, text))
      f['fieldId'] as String: f['value'],
  };

  test('S1 rehearsal fills ten of fifteen fields with grounded evidence', () {
    expect(form.fields, hasLength(15));
    expect(form.visibleFields({}), hasLength(15));
    expect(form.fields.map((f) => f.id), provisionClosureLabels.keys);
    expect(form.fields.any((f) => f.id == 'serving_asset'), false);
    expect(form.source['closurePolicy'], isNull);
    final v = values(rehearsal);
    expect(v.entries.where((e) => e.value != null), hasLength(10));
    expect(v['access_permission'], true);
    expect(v['location_agreed'], true);
    expect(v['drop_route'], 'existing');
    expect(v['external_connection'], true);
    expect(v['internal_fibre'], true);
    expect(v['ont_fitted'], true);
    expect(v['optical_rx_dbm'], -18.2);
    expect(v['operational_test'], 'passed');
    expect(v['claimed_outcome'], 'completed');
    expect(
      provisionClosureLabels.keys.where((id) => v[id] == null),
      missingIds,
    );
    for (final fact in compactNarrativeFacts(form, rehearsal)) {
      expect(rehearsal.contains(fact['sourceSpan'] as String), true);
    }
  });

  test('the complete spoken script fills all fifteen fields', () {
    final v = values(completeRehearsal);
    expect(provisionClosureLabels.keys.where((id) => v[id] == null), isEmpty);
    expect(v['optical_rx_dbm'], -18.2);
  });

  test('numeric sign pauses keep the explicit value and raw source', () {
    for (final reading in [
      'minus. 18.2',
      'minus, eighteen point two',
      'minus eighteen point. two',
    ]) {
      final text = 'The optical receive reading was $reading dBm.';
      final facts = compactNarrativeFacts(form, text);
      final optical = facts.firstWhere((f) => f['fieldId'] == 'optical_rx_dbm');
      expect(optical['value'], -18.2, reason: reading);
      expect(text.contains(optical['sourceSpan'] as String), true);
    }
    for (final reading in ['-18.99 Two', 'minus. -18.2', '18.2 or 19.1']) {
      expect(
        values(
          'The optical receive reading was $reading dBm.',
        )['optical_rx_dbm'],
        isNull,
      );
    }
    expect(
      values('I left the site safe and. tidy.')['site_handover_safe'],
      true,
    );
    expect(
      values("I'll let this side safe and tidy.")['site_handover_safe'],
      isNull,
    );
  });

  test(
    'observed ASR grammar, punctuation and OND fill the stated ONT facts',
    () {
      final v = values(observedTranscript);
      expect(v['location_agreed'], true);
      expect(v['ont_fitted'], true);
      expect(v['internal_fibre'], true);
      expect(v['ont_status_checked'], true);
      expect(v['optical_rx_dbm'], isNull);
      expect(v['site_handover_safe'], isNull);
      expect(provisionClosureLabels.keys.where((id) => v[id] == null), [
        'optical_rx_dbm',
        'site_handover_safe',
      ]);
      for (final fact in compactNarrativeFacts(form, observedTranscript)) {
        expect(observedTranscript.contains(fact['sourceSpan'] as String), true);
      }
    },
  );

  test(
    'spaced ONT and uninflected visit verbs are understood without accepting plans',
    () {
      final v = values(
        'The customer approve the O N T location. '
        'I install the O N T in the living room. I fit the internal fibre to the O N T.',
      );
      expect(v['location_agreed'], true);
      expect(v['ont_fitted'], true);
      expect(v['internal_fibre'], true);
      for (final text in [
        'I will install the ONT.',
        'I need to install the ONT.',
        'I plan to install the ONT.',
        'Please install the ONT.',
        'I am going to fit the internal fibre to the ONT.',
        'Can you install the ONT?',
      ]) {
        final planned = values(text);
        expect(planned['ont_fitted'], isNot(true), reason: text);
        expect(planned['internal_fibre'], isNot(true), reason: text);
      }
      expect(summaryFinished("Nothing much, that's everything."), true);
      expect(summaryFinished('Nothing much has been completed.'), false);
    },
  );

  test(
    'new booleans preserve explicit no, uncertainty and conflicting facts',
    () {
      final v = values(
        'The customer denied access. The ONT location was not approved. '
        'The external fibre is not installed. The internal fibre was not fitted. '
        'The ONT is not installed. ONT power and status were not checked. '
        'The service is not live. The customer was not shown the equipment. '
        'The site is unsafe.',
      );
      for (final id in provisionClosureLabels.keys.where(
        (id) => !compactClosureLabels.containsKey(id) && id != 'drop_route',
      )) {
        expect(v[id], false, reason: id);
      }
      expect(
        values('I think the customer granted access.')['access_permission'],
        isNull,
      );
      expect(
        values('The service is live. The service is not live.')['service_live'],
        isNull,
      );
      expect(
        values(
          'The customer granted access. The customer denied access.',
        )['access_permission'],
        isNull,
      );
      expect(values('I installed the ONT.')['service_live'], isNull);
      expect(values('The service test passed.')['customer_handover'], isNull);
      expect(values('The site is safe.')['site_handover_safe'], isNull);
      expect(
        values('I installed the external fibre.')['external_connection'],
        isNull,
      );
      expect(
        values('The engineer approved the ONT location.')['location_agreed'],
        isNull,
      );
      expect(values('I checked the ONT power.')['ont_status_checked'], isNull);
    },
  );

  for (final sample in [
    (
      name: 'ten facts online',
      text: rehearsal,
      missing: missingIds,
      offline: false,
    ),
    (
      name: 'ten facts offline',
      text: rehearsal,
      missing: missingIds,
      offline: true,
    ),
    (
      name: 'complete fifteen-field summary',
      text: completeRehearsal,
      missing: <String>[],
      offline: false,
    ),
    (
      name: 'observed ASR with two genuine clarifications',
      text: observedTranscript,
      missing: ['optical_rx_dbm', 'site_handover_safe'],
      offline: false,
    ),
  ]) {
    final offline = sample.offline;
    testWidgets('${sample.name}: asks only missing fields and submits', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = TestAudio([]);
      final container = ProviderContainer(
        overrides: [
          appProvider.overrideWith(ExpandedController.new),
          voiceAudioFactoryProvider.overrideWithValue(() => audio),
        ],
      );
      addTearDown(container.dispose);
      final app = container.read(appProvider.notifier) as ExpandedController;
      app.summaryApi.offline = offline;
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
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('15 fields. One conversation.'), findsOneWidget);
      app.engine.answer = sample.text;
      await tester.tap(find.text('Fill with voice AI'));
      await tester.pumpAndSettle();
      await fixture.utter(tester, audio);
      expect(find.text('Anything else?'), findsOneWidget);
      final saved =
          app.records.data['closure-demo-summary:closure-test'] as Json;
      expect((saved['values'] as Json).length, 15 - sample.missing.length);
      expect(saved['fieldIds'], hasLength(15));
      app.engine.answer = "Nothing much, that's everything.";
      await fixture.utter(tester, audio);
      for (final id in sample.missing) {
        final field = form.fields.firstWhere((f) => f.id == id);
        expect(
          find.text(closureSpokenQuestion(field)),
          findsWidgets,
          reason: id,
        );
        app.engine.answer = id == 'optical_rx_dbm'
            ? 'Minus eighteen point two dBm'
            : id == 'next_action'
            ? 'No further work required'
            : 'Yes';
        await fixture.utter(tester, audio);
      }
      expect(find.text('Review visit summary'), findsOneWidget);
      for (final field in form.fields.where(
        (f) => !sample.missing.contains(f.id),
      )) {
        expect(
          app.engine.events,
          isNot(contains('speak:${closureSpokenQuestion(field)}')),
        );
      }
      expect(app.engine.extractionCalls, 0);
      final complete =
          app.records.data['closure-demo-summary:closure-test'] as Json;
      expect((complete['values'] as Json).length, 15);
      expect(complete['values']['optical_rx_dbm'], -18.2);
      expect(
        complete['values']['actual_work'],
        isNot(contains('Nothing much')),
      );
      await tester.tap(find.text('Complete visit & submit'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          offline
              ? 'Saved on this device · Waiting to sync'
              : 'Visit summary submitted',
        ),
        findsOneWidget,
      );
      expect(
        app.state.summarySubmissions.single['payload']['values'].length,
        15,
      );
      if (offline) {
        app.summaryApi.offline = false;
        await app.synchronize();
        await tester.pumpAndSettle();
      }
      expect(app.summaryApi.submitted.single['values'].length, 15);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
