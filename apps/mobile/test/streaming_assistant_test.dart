import 'dart:async';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'support/voice_fakes.dart';
import 'closure_voice_assistant_test.dart' as fixture;

class StreamingEngine extends TestEngine {
  StreamingEngine() : super([]);
  bool hasSpeech = true;
  Completer<SpeechProgress>? pending;
  final turns = <ScriptedTurn>[];
  @override
  bool get streamingAvailable => true;
  @override
  Future<StreamingSpeechTurn> startSpeechTurn() async {
    final turn = ScriptedTurn(this);
    turns.add(turn);
    return turn;
  }

  @override
  Future<String> transcribe(Float32List samples) async => throw StateError(
    'Streaming conversation must not re-transcribe the complete recording.',
  );
}

class ScriptedTurn implements StreamingSpeechTurn {
  ScriptedTurn(this.engine);
  final StreamingEngine engine;
  int samples = 0;
  bool cancelled = false;
  @override
  Future<SpeechProgress> add(Float32List audio) async {
    samples += audio.length;
    return engine.pending?.future ??
        SpeechProgress(
          text: engine.hasSpeech ? engine.answer : '',
          heardSpeech: engine.hasSpeech,
          speaking: engine.hasSpeech && samples < 6400,
          audioSeconds: samples / 16000,
          lastSpeechSeconds: engine.hasSpeech ? .4 : 0,
        );
  }

  @override
  Future<String> finish() async => engine.hasSpeech ? engine.answer : '';
  @override
  Future<void> cancel() async => cancelled = true;
}

void main() {
  testWidgets(
    'streaming summary saves four facts, then skips those questions automatically',
    (tester) async {
      final engine = StreamingEngine()
        ..answer =
            'I installed the ONT. The reading was minus 18.2DBM. The service test passed. The job is fully completed.';
      final audio = TestAudio([]);
      final form = compactClosureForm(fixture.form);
      final values = <String, Answer>{};
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: true,
          collectSummaryFirst: true,
          announceSavedAnswers: false,
          nextQuestion: (_) =>
              form.fields.where((f) => !values.containsKey(f.id)).firstOrNull,
          isAnswered: (f) => values.containsKey(f.id),
          proposeNarrative: (text, _) async => [
            for (final fact in compactNarrativeFacts(form, text))
              ClosureVoiceFact(
                form.fields.firstWhere((f) => f.id == fact['fieldId']),
                fact,
              ),
          ],
          keepNarrative: (text, facts, selected) async {
            for (final fact in facts) {
              if (selected.contains(fact.field.id) && fact.answer != null) {
                values[fact.field.id] = fact.answer!;
              }
            }
          },
          keepAnswer: (f, a) async {
            if (a.answer != null) values[f.id] = a.answer!;
          },
        ),
      );
      await fixture.utter(tester, audio);
      expect(values['optical_rx_dbm']?.toJson(), -18.2);
      expect(values['claimed_outcome']?.toJson(), 'completed');
      expect(values['operational_test']?.toJson(), 'passed');
      expect(find.text('Anything else?'), findsOneWidget);
      engine.answer = "That's everything.";
      await fixture.utter(tester, audio);
      expect(find.text(closureSpokenQuestion(form.fields[2])), findsWidgets);
      for (final id in [
        'claimed_outcome',
        'optical_rx_dbm',
        'operational_test',
      ]) {
        expect(
          engine.events,
          isNot(
            contains(
              'speak:${closureSpokenQuestion(form.fields.firstWhere((f) => f.id == id))}',
            ),
          ),
        );
      }
    },
  );
  testWidgets(
    'loud ambient levels cannot override neural silence into Anything else',
    (tester) async {
      final engine = StreamingEngine()..hasSpeech = false;
      final audio = TestAudio([]);
      await fixture.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: true,
          collectSummaryFirst: true,
          announceSavedAnswers: false,
          nextQuestion: (_) => fixture.field('actual_work'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async =>
              fail('Neural silence must not be saved'),
          keepAnswer: (_, _) async => fail('No answer was spoken'),
        ),
      );
      for (var i = 0; i < 50; i++) {
        audio.bytes!(Uint8List(5120));
        audio.meter!(.5);
        await tester.pumpAndSettle();
      }
      expect(
        engine.events,
        contains('speak:${closureAssistantPrompts['assistant_guided_start']}'),
      );
      expect(engine.events, isNot(contains('speak:Anything else?')));
      expect(
        find.text(closureSpokenQuestion(fixture.field('actual_work'))),
        findsWidgets,
      );
    },
  );
  testWidgets(
    'manual choice cancels a streaming turn and ignores its late partial',
    (tester) async {
      final pending = Completer<SpeechProgress>();
      final engine = StreamingEngine()..pending = pending;
      final audio = TestAudio([]);
      Answer? value;
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
              value == null ? fixture.field('operational_test') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, a) async => value = a.answer,
        ),
      );
      audio.bytes!(Uint8List(5120));
      await tester.pump();
      final old = engine.turns.first;
      await tester.tap(find.text('Passed'));
      await tester.pumpAndSettle();
      expect(old.cancelled, true);
      pending.complete(
        const SpeechProgress(
          text: 'failed',
          heardSpeech: true,
          speaking: false,
          audioSeconds: 2,
          lastSpeechSeconds: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(value?.toJson(), 'passed');
    },
  );
}
