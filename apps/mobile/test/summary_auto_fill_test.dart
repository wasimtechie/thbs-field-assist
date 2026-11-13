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
import 'package:field_assist/features/voice/voice_audio.dart';
import 'compact_closure_test.dart' as fixture;
import 'closure_journey_test.dart' as full;
import 'support/voice_fakes.dart';

const summary =
    'I installed the ONT in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two dBm. The service test passed. The job is fully completed. I showed the customer the equipment.';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    // Exercise the real conversation and persistence with an observable,
    // immediate synthesizer. The prepared pack has its own integrity tests.
    rootBundle.evict('assets/voice_questions/index.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          return ByteData.sublistView(
            Uint8List.fromList(utf8.encode('{"model":"test-fallback"}')),
          );
        });
  });
  for (final start in [
    'summary',
    'silence',
    'empty ASR',
    'noise ASR',
    'resume',
    'saved summary',
    'manual work',
  ]) {
    testWidgets(
      'S1 auto-fills four fields after $start and asks only for follow-up',
      (tester) async {
        final audio = TestAudio([]);
        final container = ProviderContainer(
          overrides: [
            appProvider.overrideWith(fixture.CompactController.new),
            voiceAudioFactoryProvider.overrideWithValue(() => audio),
          ],
        );
        addTearDown(container.dispose);
        final app =
            container.read(appProvider.notifier) as fixture.CompactController;
        final original = encodeAnswers(app.records.values);
        if (['resume', 'saved summary', 'manual work'].contains(start)) {
          final previous = start == 'saved summary'
              ? summary
              : 'Installed the ONT.';
          app.records.data['closure-demo-summary:closure-test'] = {
            'values': {'actual_work': previous},
            'sources': {
              'actual_work': {
                'sourceType': start == 'manual work' ? 'manual' : 'speech',
                'sourceSpan': previous,
              },
            },
          };
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
        await tester.tap(find.text('Fill with voice AI'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 250));
        if (start == 'silence') {
          audio.bytes!(Uint8List(16000 * 2 * 8));
          audio.meter!(0);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 250));
        } else if (start == 'empty ASR' || start == 'noise ASR') {
          app.engine.answer = start == 'empty ASR' ? '' : '[Background music]';
          await fixture.utter(tester, audio);
        }
        if (['silence', 'empty ASR', 'noise ASR'].contains(start)) {
          expect(
            app.engine.events,
            contains(
              'speak:${closureAssistantPrompts['assistant_guided_start']}',
            ),
          );
          expect(app.engine.events, isNot(contains('speak:Anything else?')));
          expect(
            find.text(
              closureSpokenQuestion(
                compactClosureForm(full.closureForm).fields.first,
              ),
            ),
            findsWidgets,
          );
          expect(app.records.data['closure-demo-summary:closure-test'], isNull);
        }
        if (start != 'saved summary') {
          app.engine.answer = summary;
          await fixture.utter(tester, audio);
        }
        if (start == 'summary') {
          expect(find.text('Anything else?'), findsOneWidget);
          app.engine.answer = "That's everything.";
          await fixture.utter(tester, audio);
        }
        final saved =
            app.records.data['closure-demo-summary:closure-test'] as Json;
        final values = saved['values'] as Json;
        expect(values['actual_work'], contains(summary));
        expect(
          saved['sources']['actual_work']['sourceType'],
          start == 'manual work' ? 'text' : 'speech',
        );
        expect(values['claimed_outcome'], 'completed');
        expect(values['optical_rx_dbm'], -18.2);
        expect(values['operational_test'], 'passed');
        expect(compactClosureLabels.keys.where((id) => values[id] == null), [
          'next_action',
        ]);
        final form = compactClosureForm(full.closureForm);
        expect(
          find.text(
            closureSpokenQuestion(
              form.fields.firstWhere((f) => f.id == 'next_action'),
            ),
          ),
          findsWidgets,
        );
        // Completed outcome, reading and test questions must never be spoken.
        for (final id in [
          'claimed_outcome',
          'optical_rx_dbm',
          'operational_test',
        ]) {
          final question = closureSpokenQuestion(
            form.fields.firstWhere((f) => f.id == id),
          );
          final spokenCount = app.engine.events
              .where((e) => e == 'speak:$question')
              .length;
          expect(
            spokenCount,
            ['resume', 'manual work'].contains(start) && id == 'claimed_outcome'
                ? 1
                : 0,
          );
        }
        expect(
          find.text(closureSpokenQuestion(form.fields.last)),
          findsWidgets,
        );
        app.engine.answer = 'No further work required';
        await fixture.utter(tester, audio);
        expect(find.text('Review visit summary'), findsOneWidget);
        final complete =
            app.records.data['closure-demo-summary:closure-test'] as Json;
        expect((complete['values'] as Json).length, 5);
        expect(complete['operationalClosureApproved'], false);
        expect(encodeAnswers(app.records.values), original);
        expect(app.engine.extractionCalls, 0);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  test('empty summary decodes are distinct from actual visit details', () {
    for (final text in [
      '',
      ' ',
      '[noise]',
      '(Silence)',
      'Thank you for watching.',
      'Anything else?',
      "That's everything.",
    ]) {
      expect(hasSpokenReportContent(text), false, reason: text);
    }
    for (final text in [
      summary,
      'No access to the premises.',
      'Customer not home.',
      'Nothing completed; return visit required.',
    ]) {
      expect(hasSpokenReportContent(text), true, reason: text);
    }
  });
}
