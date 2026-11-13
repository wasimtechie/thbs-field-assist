import 'dart:convert';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/closure/closure_screen.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'compact_closure_test.dart' as fixture;
import 'closure_journey_test.dart' as full;
import 'support/voice_fakes.dart';

typedef Segment = ({double from, double to, String text});

const opening = <Segment>[
  (from: .5, to: 2, text: 'I installed the ONT in the living room.'),
  (from: 3.2, to: 5, text: 'I used the existing duct for the fibre route.'),
  (from: 6.2, to: 9, text: 'The optical receive reading was -18.2 dB.'),
  (from: 10.2, to: 12, text: 'The service test passed.'),
  (from: 13.2, to: 15, text: 'The job is fully completed.'),
  (from: 16.2, to: 18, text: 'I showed the customer the equipment.'),
];
const addition = <Segment>[
  // Realistic thinking time after Anything else; the old three-second timeout
  // would stop the microphone before this speech even begins.
  (from: 4.5, to: 6, text: 'The serving asset is CBT-SYN-10.'),
  (from: 7.2, to: 9, text: 'No further work required.'),
];

class PausedEngine extends TestEngine {
  PausedEngine(this.scripts) : super([]);
  final List<List<Segment>> scripts;
  final turns = <PausedTurn>[];
  final emptyFinals = <int>{};
  @override
  bool get streamingAvailable => true;
  @override
  Future<StreamingSpeechTurn> startSpeechTurn() async {
    final index = turns.length;
    final turn = PausedTurn(
      index < scripts.length ? scripts[index] : [],
      emptyFinals.contains(index),
    );
    turns.add(turn);
    return turn;
  }

  @override
  Future<String> transcribe(Float32List pcm) async =>
      throw StateError('This test must use live streaming partials.');
}

class PausedTurn implements StreamingSpeechTurn {
  PausedTurn(this.script, this.emptyFinal);
  final List<Segment> script;
  final bool emptyFinal;
  int samples = 0;
  bool finished = false, cancelled = false;
  String text = '';
  @override
  Future<SpeechProgress> add(Float32List pcm) async {
    samples += pcm.length;
    final time = samples / 16000;
    text = script.where((s) => s.from <= time).map((s) => s.text).join(' ');
    final seen = script.where((s) => s.from <= time).toList();
    return SpeechProgress(
      text: emptyFinal ? '' : text,
      heardSpeech: seen.isNotEmpty,
      speaking: script.any((s) => s.from <= time && time < s.to),
      audioSeconds: time,
      lastSpeechSeconds: seen.isEmpty ? 0 : time.clamp(0, seen.last.to),
    );
  }

  @override
  Future<String> finish() async {
    finished = true;
    // Return only words actually reached, never future scripted words.
    return emptyFinal ? '' : text;
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

class PausedController extends fixture.CompactController {
  PausedController(this.scripted);
  final PausedEngine scripted;
  @override
  TestEngine get voice => scripted;
}

Future<void> feedTurn(
  WidgetTester tester,
  TestAudio audio,
  PausedTurn turn,
) async {
  for (var i = 0; i < 160 && !turn.finished && !turn.cancelled; i++) {
    audio.bytes!(Uint8List(5120));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();
  }
  expect(turn.finished, true);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

Future<PausedController> mountConversation(
  WidgetTester tester,
  PausedEngine engine,
  TestAudio audio,
) async {
  final container = ProviderContainer(
    overrides: [
      appProvider.overrideWith(() => PausedController(engine)),
      voiceAudioFactoryProvider.overrideWithValue(() => audio),
    ],
  );
  addTearDown(container.dispose);
  final app = container.read(appProvider.notifier) as PausedController;
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
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
  return app;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    rootBundle.evict('assets/voice_questions/index.json');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'flutter/assets',
          (_) async => ByteData.sublistView(
            Uint8List.fromList(utf8.encode('{"model":"test-fallback"}')),
          ),
        );
  });

  test(
    'reported dB transcript preserves the number and requests unit confirmation',
    () {
      const text =
          'I installed the ONT. The optical receive reading was -18.2 dB';
      final form = compactClosureForm(full.closureForm);
      final fact = compactNarrativeFacts(
        form,
        text,
      ).singleWhere((f) => f['fieldId'] == 'optical_rx_dbm');
      expect(fact['value'], -18.2);
      expect(fact['requiresConfirmation'], true);
      expect(fact['unitNeedsConfirmation'], true);
      expect(text.contains(fact['sourceSpan']), true);
      for (final unrelated in [
        'The noise reading was 18.2 dB.',
        'The loss reading was 18.2 dB.',
        'Optical transmit reading was -18.2 dB.',
      ]) {
        expect(
          compactNarrativeFacts(form, unrelated).where(
            (f) => f['fieldId'] == 'optical_rx_dbm' && f['value'] != null,
          ),
          isEmpty,
        );
      }
    },
  );

  for (final emptyAddition in [false, true]) {
    testWidgets(
      'paused six-sentence summary and delayed additions survive ${emptyAddition ? 'an empty recognition retry' : 'through review'}',
      (tester) async {
        final engine = PausedEngine([
          opening,
          if (emptyAddition)
            [(from: .5, to: 2, text: 'Unrecognised extra speech')],
          addition,
          [(from: .5, to: .9, text: 'Yes.')],
        ]);
        if (emptyAddition) engine.emptyFinals.add(1);
        final audio = TestAudio([]);
        final app = await mountConversation(tester, engine, audio);
        await feedTurn(tester, audio, engine.turns.last);
        Json saved() =>
            app.records.data['closure-demo-summary:closure-test'] as Json;
        expect(
          saved()['values']['actual_work'],
          contains('I showed the customer'),
        );
        expect(saved()['values']['claimed_outcome'], 'completed');
        expect(saved()['values']['operational_test'], 'passed');
        expect(saved()['values']['optical_rx_dbm'], -18.2);
        expect(find.text('Anything else?'), findsOneWidget);
        if (emptyAddition) {
          await feedTurn(tester, audio, engine.turns.last);
          expect(
            find.text(
              'Your earlier summary is saved. What would you like to add?',
            ),
            findsWidgets,
          );
          expect(
            saved()['values']['actual_work'],
            contains('I showed the customer'),
          );
        }
        await feedTurn(tester, audio, engine.turns.last);
        expect(
          saved()['values']['actual_work'],
          contains('I showed the customer'),
        );
        expect(
          saved()['values']['actual_work'],
          contains('The serving asset is CBT-SYN-10.'),
        );
        expect(
          saved()['values']['actual_work'],
          contains('No further work required.'),
        );
        expect(saved()['values']['serving_asset'], isNull);
        expect(
          saved()['values']['next_action'],
          contains('No further work required'),
        );
        expect(
          find.textContaining(
            'Was the optical receive reading minus 18.2 dBm?',
          ),
          findsWidgets,
        );
        expect(
          engine.events.where((e) => e == 'speak:Anything else?'),
          hasLength(1),
        );
        await feedTurn(tester, audio, engine.turns.last);
        expect(find.text('Review visit summary'), findsOneWidget);
        expect(
          saved()['sources']['optical_rx_dbm']['requiresConfirmation'],
          false,
        );
        expect((saved()['values'] as Json).length, 5);
        final form = compactClosureForm(full.closureForm);
        for (final id in [
          'claimed_outcome',
          'operational_test',
          'next_action',
        ]) {
          final question = closureSpokenQuestion(
            form.fields.firstWhere((f) => f.id == id),
          );
          expect(engine.events, isNot(contains('speak:$question')));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final hesitant in [false, true]) {
    testWidgets(
      'addition ${hesitant ? 'after a hesitant no' : 'with a corrected reading'} fills all remaining fields without repeating questions',
      (tester) async {
        final cleanOpening = opening
            .map(
              (s) => (
                from: s.from,
                to: s.to,
                text: s.text.replaceAll(' dB.', ' dBm.'),
              ),
            )
            .toList();
        final engine = PausedEngine([
          cleanOpening,
          [
            if (hesitant) (from: .5, to: .8, text: 'No,'),
            (
              from: hesitant ? 1.8 : 4.5,
              to: hesitant ? 2.5 : 5.5,
              text:
                  'sorry the optical received measurement was minus 18.19 dBm.',
            ),
            (
              from: hesitant ? 3.5 : 6.5,
              to: hesitant ? 4.5 : 7.5,
              text: 'The serving asset is CBT-SYN-10.',
            ),
            (
              from: hesitant ? 5.5 : 8.5,
              to: hesitant ? 6.5 : 9.5,
              text: 'No further work required.',
            ),
          ],
        ]);
        final audio = TestAudio([]);
        final app = await mountConversation(tester, engine, audio);
        await feedTurn(tester, audio, engine.turns.last);
        expect(find.text('Anything else?'), findsOneWidget);
        await feedTurn(tester, audio, engine.turns.last);
        final saved =
            app.records.data['closure-demo-summary:closure-test'] as Json;
        expect(saved['values']['optical_rx_dbm'], -18.19);
        expect(saved['values']['serving_asset'], isNull);
        expect(
          saved['values']['next_action'],
          contains('No further work required'),
        );
        expect(saved['values']['actual_work'], isNot(contains('-18.2')));
        expect(saved['values']['actual_work'], contains('I installed the ONT'));
        expect(
          saved['sources']['actual_work']['rawTranscript'],
          contains('-18.2 dBm'),
        );
        expect(
          saved['sources']['actual_work']['interpretedSpan'],
          saved['values']['actual_work'],
        );
        expect(saved['sources']['optical_rx_dbm']['speechRepairs'], isNotEmpty);
        expect(find.text('Review visit summary'), findsOneWidget);
        final form = compactClosureForm(full.closureForm);
        for (final f in form.fields) {
          expect(
            engine.events,
            isNot(contains('speak:${closureSpokenQuestion(f)}')),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'opening the draft during an addition retains both summaries and fills its new asset',
    (tester) async {
      final engine = PausedEngine([
        opening,
        [(from: .5, to: 10, text: 'The serving asset is CBT-SYN-10.')],
      ]);
      final audio = TestAudio([]);
      final app = await mountConversation(tester, engine, audio);
      await feedTurn(tester, audio, engine.turns.last);
      final additionTurn = engine.turns.last;
      for (var i = 0; i < 8; i++) {
        audio.bytes!(Uint8List(5120));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.pumpAndSettle();
      }
      expect(additionTurn.finished, false);
      expect(additionTurn.text, contains('CBT-SYN-10'));
      await tester.ensureVisible(find.byTooltip('Open draft'));
      await tester.tap(find.byTooltip('Open draft'));
      await tester.pumpAndSettle();
      expect(find.byType(ClosureVoiceAssistant), findsNothing);
      final saved =
          app.records.data['closure-demo-summary:closure-test'] as Json;
      expect(saved['values']['actual_work'], contains('I installed the ONT'));
      expect(saved['values']['actual_work'], contains('I showed the customer'));
      expect(
        saved['values']['actual_work'],
        contains('The serving asset is CBT-SYN-10.'),
      );
      expect(saved['values']['serving_asset'], isNull);
      expect(saved['values']['claimed_outcome'], 'completed');
      expect(saved['values']['operational_test'], 'passed');
      expect(saved['values']['optical_rx_dbm'], -18.2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
