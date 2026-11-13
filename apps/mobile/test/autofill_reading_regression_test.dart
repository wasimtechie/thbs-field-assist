import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/closure/closure_screen.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/optical_reading.dart';
import 'package:field_assist/features/forms/form_screen.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'compact_closure_test.dart' as fixture;
import 'closure_journey_test.dart' as full;
import 'support/voice_fakes.dart';

// Verbatim text visible in the engineer's failed simulator test.
const screenshotSummary =
    'I installed the Ointi in the living room. I use the existing duct for the piper road The optical receive driven was -18 0.2 dBm The service test passed';

class Journey {
  Journey(this.container, this.app, this.audio);
  final ProviderContainer container;
  final fixture.CompactController app;
  final TestAudio audio;
  Json get saved =>
      app.records.data['closure-demo-summary:closure-test'] as Json;
}

Future<Journey> mount(WidgetTester tester, {Json? saved}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final audio = TestAudio([]);
  final container = ProviderContainer(
    overrides: [
      appProvider.overrideWith(fixture.CompactController.new),
      voiceAudioFactoryProvider.overrideWithValue(() => audio),
    ],
  );
  addTearDown(container.dispose);
  final app = container.read(appProvider.notifier) as fixture.CompactController;
  if (saved != null) {
    app.records.data['closure-demo-summary:closure-test'] = saved;
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: fieldTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const ClosureScreen(reportId: 'closure-test'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
  return Journey(container, app, audio);
}

Finder input(String id) => find.descendant(
  of: find.byWidgetPredicate((w) => w is AnswerInput && w.field.id == id),
  matching: find.byType(TextField),
);

Future<void> typeSummary(WidgetTester tester, String text) async {
  await tester.ensureVisible(input('actual_work'));
  await tester.enterText(input('actual_work'), text);
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    rootBundle.evict('assets/voice_questions/index.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (message) async => ByteData.sublistView(
            Uint8List.fromList(utf8.encode('{"model":"test-fallback"}')),
          ),
        );
  });
  final form = compactClosureForm(full.closureForm);
  final reading = form.fields.firstWhere((f) => f.id == 'optical_rx_dbm');

  test(
    'exact failed transcript proposes the reading without inventing other fields',
    () {
      final facts = {
        for (final f in compactNarrativeFacts(form, screenshotSummary))
          f['fieldId']: f,
      };
      expect(facts['optical_rx_dbm']?['value'], -18.2);
      expect(facts['optical_rx_dbm']?['requiresConfirmation'], true);
      expect(
        screenshotSummary.contains(facts['optical_rx_dbm']?['sourceSpan']),
        true,
      );
      expect(facts['operational_test']?['value'], 'passed');
      expect(facts['serving_asset'], isNull);
      expect(facts['claimed_outcome'], isNull);
      expect(closureSpokenAnswer(reading, '-18 0.2 dBm'), isNull);
    },
  );
  for (final text in [
    'Optical receive driven was -18.2 dBm.',
    'Optical receive reading was minus eighteen point two dBm.',
    'The received power measured -18.2 dBm.',
  ]) {
    test(
      'clear reading automatically fills without extra confirmation: $text',
      () {
        final fact = opticalNarrativeFacts(text).single;
        expect(fact['value'], -18.2);
        expect(fact['requiresConfirmation'], isNot(true));
      },
    );
  }
  for (final text in [
    'Optical receive target was -18.2 dBm.',
    'The transmit reading was -18.2 dBm.',
    'The optical receive was minus -18.2 dBm.',
    'The optical receive was -18 2 dBm.',
    'The optical receive was -18.2 or -19.1 dBm.',
    'The optical receive might be -18 0.2 dBm.',
  ]) {
    test(
      'uncertain or competing measurement is not silently accepted: $text',
      () {
        expect(
          opticalNarrativeFacts(text).where((f) => f['value'] != null),
          isEmpty,
        );
      },
    );
  }

  testWidgets(
    'manual Work done updates the visible fields and preserves the typing controller',
    (tester) async {
      final journey = await mount(tester);
      await tester.tap(find.text('Fill manually'));
      await tester.pumpAndSettle();
      final before = tester.widget<TextField>(input('actual_work')).controller;
      await typeSummary(
        tester,
        '$screenshotSummary. The job is fully completed. Connected at CBT-SYN-10. No further work required.',
      );
      expect(journey.saved['values']['optical_rx_dbm'], -18.2);
      expect(journey.saved['values']['operational_test'], 'passed');
      expect(journey.saved['values']['claimed_outcome'], 'completed');
      expect(
        tester.widget<TextField>(input('optical_rx_dbm')).controller!.text,
        '-18.2',
      );
      expect(
        tester.widget<TextField>(input('actual_work')).controller,
        same(before),
      );
      expect(before!.selection.baseOffset, before.text.length);
      await tester.tap(find.text('Review 5-field summary'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Confirm the proposed optical reading, or enter the measured value, before reviewing.',
        ),
        findsOneWidget,
      );
      expect(find.text('Review visit summary'), findsNothing);
      await tester.ensureVisible(find.text('Confirm -18.2 dBm'));
      await tester.tap(find.text('Confirm -18.2 dBm'));
      await tester.pumpAndSettle();
      expect(
        journey.saved['sources']['optical_rx_dbm']['requiresConfirmation'],
        isNot(true),
      );
      expect(
        journey.saved['sources']['optical_rx_dbm']['sourceType'],
        'manual',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fresh voice summary auto-fills before a selected confirmation and advances only to the missing asset',
    (tester) async {
      final journey = await mount(tester);
      await tester.tap(find.text('Fill with voice AI'));
      await tester.pumpAndSettle();
      journey.app.engine.answer =
          '$screenshotSummary. The job is fully completed.';
      await fixture.utter(tester, journey.audio);
      expect(find.text('Anything else?'), findsOneWidget);
      expect(journey.saved['values']['optical_rx_dbm'], -18.2);
      expect(journey.saved['values']['operational_test'], 'passed');
      journey.app.engine.answer = 'No.';
      await fixture.utter(tester, journey.audio);
      expect(
        find.textContaining('I heard minus 18.2 dBm. Is that correct?'),
        findsWidgets,
      );
      await tester.tap(find.text('Yes, use -18.2'));
      await tester.pumpAndSettle();
      expect(
        journey.saved['sources']['optical_rx_dbm']['sourceType'],
        'manual',
      );
      expect(
        journey.saved['sources']['optical_rx_dbm']['verificationStatus'],
        'engineer_confirmed',
      );
      expect(
        journey.saved['sources']['optical_rx_dbm']['sourceSpan'],
        contains('-18 0.2 dBm'),
      );
      expect(
        find.text(
          closureSpokenQuestion(
            form.fields.firstWhere((f) => f.id == 'next_action'),
          ),
        ),
        findsWidgets,
      );
      expect(journey.saved['values']['serving_asset'], isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final accept in [true, false]) {
    testWidgets(
      'resumed screenshot summary asks reading confirmation and handles ${accept ? 'yes' : 'no'} by voice',
      (tester) async {
        final journey = await mount(
          tester,
          saved: {
            'values': {
              'actual_work': screenshotSummary,
              'claimed_outcome': 'completed',
            },
            'sources': {
              'actual_work': {
                'sourceType': 'speech',
                'sourceSpan': screenshotSummary,
              },
            },
          },
        );
        expect(journey.saved['values']['optical_rx_dbm'], -18.2);
        await tester.tap(find.text('Fill with voice AI'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('I heard minus 18.2 dBm. Is that correct?'),
          findsWidgets,
        );
        journey.app.engine.answer = accept ? 'Yes, that is correct.' : 'No.';
        await fixture.utter(tester, journey.audio);
        if (accept) {
          expect(
            journey.saved['sources']['optical_rx_dbm']['verificationStatus'],
            'engineer_confirmed',
          );
          expect(
            journey.saved['sources']['optical_rx_dbm']['confirmationSpan'],
            'Yes, that is correct.',
          );
        } else {
          expect(journey.saved['values']['optical_rx_dbm'], isNull);
          expect(find.text(closureSpokenQuestion(reading)), findsWidgets);
          journey.app.engine.answer = 'Minus nineteen point one dBm.';
          await fixture.utter(tester, journey.audio);
          expect(journey.saved['values']['optical_rx_dbm'], -19.1);
        }
        expect(
          find.text(
            closureSpokenQuestion(
              form.fields.firstWhere((f) => f.id == 'next_action'),
            ),
          ),
          findsWidgets,
        );
        expect(
          journey.app.engine.events.where(
            (e) => e == 'speak:${closureSpokenQuestion(form.fields[1])}',
          ),
          isEmpty,
        );
        expect(
          journey.app.engine.events.where(
            (e) =>
                e ==
                'speak:${closureSpokenQuestion(form.fields.firstWhere((f) => f.id == 'operational_test'))}',
          ),
          isEmpty,
        );
        expect(
          find.text(closureSpokenQuestion(form.fields.last)),
          findsWidgets,
        );
        journey.app.engine.answer = 'No further work required';
        await fixture.utter(tester, journey.audio);
        expect(find.text('Review visit summary'), findsOneWidget);
        expect(
          journey.saved['values']['optical_rx_dbm'],
          accept ? -18.2 : -19.1,
        );
        expect(
          journey.saved['sources']['optical_rx_dbm']['requiresConfirmation'],
          isNot(true),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'editing the narrative refreshes derived fields but preserves an explicitly confirmed reading',
    (tester) async {
      final journey = await mount(tester);
      await tester.tap(find.text('Fill manually'));
      await tester.pumpAndSettle();
      await typeSummary(
        tester,
        'Optical receive -18.2 dBm. Service test passed.',
      );
      await typeSummary(
        tester,
        'Optical receive -19.1 dBm. Service test failed.',
      );
      expect(journey.saved['values']['optical_rx_dbm'], -19.1);
      expect(journey.saved['values']['operational_test'], 'failed');
      expect(
        tester.widget<TextField>(input('optical_rx_dbm')).controller!.text,
        '-19.1',
      );
      await tester.ensureVisible(input('optical_rx_dbm'));
      await tester.enterText(input('optical_rx_dbm'), '-20.5');
      await tester.pumpAndSettle();
      await typeSummary(tester, 'ONT installed. Service test passed.');
      expect(journey.saved['values']['optical_rx_dbm'], -20.5);
      expect(journey.saved['values']['operational_test'], 'passed');
      expect(
        journey.saved['sources']['optical_rx_dbm']['sourceType'],
        'manual',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'removing a measurement from a changed narrative clears its old inferred value',
    (tester) async {
      final journey = await mount(tester);
      await tester.tap(find.text('Fill manually'));
      await tester.pumpAndSettle();
      await typeSummary(
        tester,
        'Optical receive -18.2 dBm. Service test passed.',
      );
      await typeSummary(tester, 'ONT installed. Service test passed.');
      expect(journey.saved['values']['optical_rx_dbm'], isNull);
      expect(
        tester.widget<TextField>(input('optical_rx_dbm')).controller!.text,
        isEmpty,
      );
      expect(journey.saved['values']['operational_test'], 'passed');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
