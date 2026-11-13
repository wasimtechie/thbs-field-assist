import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/voice/conversation.dart';
import 'support/voice_fakes.dart';
import 'closure_voice_assistant_test.dart' as fixture;

class CleanupFailureAudio extends TestAudio {
  CleanupFailureAudio() : super([]);
  bool failNextStop = false;
  @override
  Future<void> stopCapture() async {
    if (failNextStop) {
      failNextStop = false;
      throw StateError('Synthetic native cleanup failure');
    }
    await super.stopCapture();
  }
}

void main() {
  test('a short yes/no response is speech while a single click is not', () {
    final short = TurnEndpoint(adaptiveNoise: true);
    short.observe(.05, const Duration(milliseconds: 120));
    expect(short.heardSpeech, true);
    final click = TurnEndpoint(adaptiveNoise: true);
    click.observe(.05, const Duration(milliseconds: 20));
    expect(click.heardSpeech, false);
  });
  testWidgets(
    'a 120 ms spoken no is processed automatically instead of discarded as silence',
    (tester) async {
      final engine = TestEngine([])..answer = 'No';
      final audio = TestAudio([]);
      Answer? saved;
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          announceSavedAnswers: false,
          nextQuestion: (_) =>
              saved == null ? fixture.field('identity_verified') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, response) async {
            saved = response.answer;
          },
        ),
      );
      audio.bytes!(Uint8List(3840));
      audio.meter!(.05);
      audio.bytes!(Uint8List(22400));
      audio.meter!(0);
      await tester.pumpAndSettle();
      expect(saved?.toJson(), false);
      expect(engine.events.where((e) => e == 'transcribe'), hasLength(1));
    },
  );
  test(
    'stationary noise ends a real answer promptly and does not count as speech forever',
    () {
      final endpoint = TurnEndpoint(
        adaptiveNoise: true,
        silence: const Duration(milliseconds: 700),
      );
      var time = 0;
      bool frame(double rms) =>
          endpoint.observe(rms, Duration(milliseconds: time += 20));
      for (var i = 0; i < 30; i++) {
        expect(frame(.008), false);
      }
      expect(endpoint.heardSpeech, false);
      for (var i = 0; i < 20; i++) {
        expect(frame(.045), false);
      }
      expect(endpoint.heardSpeech, true);
      for (var i = 0; i < 34; i++) {
        expect(frame(.008), false);
      }
      expect(frame(.008), true);
      final noise = TurnEndpoint(
        adaptiveNoise: true,
        noSpeech: const Duration(seconds: 2),
      );
      for (var ms = 20; ms < 2000; ms += 20) {
        expect(noise.observe(.008, Duration(milliseconds: ms)), false);
      }
      expect(noise.observe(.008, const Duration(seconds: 2)), true);
      expect(noise.heardSpeech, false);
    },
  );
  test(
    'calibration preserves a quiet short opening and quiet continuation after a loud word',
    () {
      for (final opening in [.008, .07]) {
        final endpoint = TurnEndpoint(
          adaptiveNoise: true,
          silence: const Duration(milliseconds: 700),
        );
        var ms = 0;
        bool frame(double level) =>
            endpoint.observe(level, Duration(milliseconds: ms += 20));
        for (var i = 0; i < 10; i++) {
          frame(opening);
        }
        expect(endpoint.heardSpeech, true);
        if (opening > .03) {
          for (var i = 0; i < 40; i++) {
            expect(frame(.008), false);
          }
        }
        for (var i = 0; i < 34; i++) {
          expect(frame(0), false);
        }
        expect(frame(0), true);
      }
    },
  );
  testWidgets(
    'two empty recognition results pause without an endless record-again loop',
    (tester) async {
      final engine = TestEngine([])..answer = '';
      final audio = TestAudio([]);
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => fixture.field('claimed_outcome'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, _) async => fail('Silence must not be saved'),
        ),
      );
      await fixture.utter(tester, audio);
      await fixture.utter(tester, audio);
      expect(find.textContaining('No clear speech reached'), findsOneWidget);
      expect(
        engine.events.where(
          (e) => e == 'speak:${closureAssistantPrompts['assistant_no_speech']}',
        ),
        hasLength(1),
      );
    },
  );
  testWidgets(
    'a microphone that emits no bytes is detected before the 60-second limit',
    (tester) async {
      final engine = TestEngine([]), audio = TestAudio([]);
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => fixture.field('claimed_outcome'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, _) async {},
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('No clear speech reached'), findsOneWidget);
      expect(engine.events.where((e) => e == 'transcribe'), isEmpty);
    },
  );
  testWidgets(
    'a stalled recognizer times out and a late result cannot fill a field',
    (tester) async {
      final engine = TestEngine([])..recognition = Completer<String>();
      final audio = TestAudio([]);
      var writes = 0;
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          recognitionTimeout: const Duration(milliseconds: 300),
          needsNarrative: false,
          nextQuestion: (_) => fixture.field('claimed_outcome'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, _) async {
            writes++;
          },
          cancelInference: engine.cancel,
        ),
      );
      audio.feed();
      audio.meter!(.05);
      audio.bytes!(Uint8List(48000));
      audio.meter!(0);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Speech processing took too long'),
        findsOneWidget,
      );
      engine.recognition!.complete('completed');
      await tester.pumpAndSettle();
      expect(writes, 0);
    },
  );
  testWidgets(
    'native cleanup failure after saving never asks to save that answer again',
    (tester) async {
      final engine = TestEngine([])..answer = 'completed';
      final audio = CleanupFailureAudio();
      final saved = <String, Answer>{};
      var writes = 0;
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          announceSavedAnswers: false,
          nextQuestion: (_) => ['claimed_outcome', 'operational_test']
              .where((id) => !saved.containsKey(id))
              .map(fixture.field)
              .firstOrNull,
          isAnswered: (f) => saved.containsKey(f.id),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (f, a) async {
            writes++;
            saved[f.id] = a.answer!;
            audio.failNextStop = true;
          },
        ),
      );
      await fixture.utter(tester, audio);
      expect(saved['claimed_outcome']?.toJson(), 'completed');
      expect(writes, 1);
      expect(
        engine.events,
        isNot(
          contains('speak:${closureAssistantPrompts['assistant_save_failed']}'),
        ),
      );
      expect(find.textContaining('Voice could not start'), findsOneWidget);
      await tester.tap(find.text('Resume conversation'));
      await tester.pumpAndSettle();
      expect(
        find.text(closureSpokenQuestion(fixture.field('operational_test'))),
        findsWidgets,
      );
      expect(writes, 1);
    },
  );
  testWidgets(
    'an already-filled active question advances after unclear speech without repeating it',
    (tester) async {
      final engine = TestEngine([])..answer = 'background chatter';
      final audio = TestAudio([]);
      var answered = false;
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) =>
              answered ? null : fixture.field('claimed_outcome'),
          isAnswered: (_) => answered,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, _) async {},
        ),
      );
      answered = true;
      await fixture.utter(tester, audio);
      expect(
        engine.events,
        isNot(
          contains('speak:${closureAssistantPrompts['assistant_unclear']}'),
        ),
      );
      expect(
        engine.events,
        contains('speak:${closureAssistantPrompts['assistant_complete']}'),
      );
    },
  );
}
