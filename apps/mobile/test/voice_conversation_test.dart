import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/conversation.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'package:field_assist/features/voice/prompt_audio_cache.dart';

import 'support/voice_fakes.dart';

void main() {
  test(
    'first question speaks choices before microphone permission/capture',
    () async {
      final events = <String>[];
      final engine = TestEngine(events), audio = TestAudio(events);
      final voice = VoiceCoordinator(
        engine: engine,
        schema: schema,
        readValues: () => {},
        onPatch: (_, _) async {},
        audio: audio,
        echoTail: Duration.zero,
      );
      addTearDown(voice.shutdown);
      await voice.begin();
      expect(voice.question, contains('fully, partially, or not completed'));
      expect(events.indexOf('play'), lessThan(events.indexOf('permission')));
      expect(events.indexOf('permission'), lessThan(events.indexOf('capture')));
      expect(voice.state, VoiceState.listening);
    },
  );
  test(
    'answer is committed before saved acknowledgement and next question',
    () async {
      final events = <String>[],
          entered = Completer<void>(),
          commit = Completer<void>();
      Answers values = {};
      final engine = TestEngine(events), audio = TestAudio(events);
      final voice = VoiceCoordinator(
        engine: engine,
        schema: schema,
        readValues: () => values,
        audio: audio,
        echoTail: Duration.zero,
        onPatch: (patch, source) async {
          expect(source, 'voice');
          entered.complete();
          await commit.future;
          values = patch.values;
        },
      );
      addTearDown(voice.shutdown);
      await voice.begin();
      audio.feed();
      final turn = voice.finish();
      await entered.future;
      expect(voice.state, VoiceState.saving);
      expect(voice.savedMessage, isEmpty);
      expect(values, isEmpty);
      expect(voice.activeField!.id, 'installation_outcome');
      commit.complete();
      await turn;
      expect(values['installation_outcome']!.toJson(), 'partial');
      expect(voice.savedMessage, contains('saved on this device'));
      expect(voice.activeField!.id, 'work_performed');
      expect(engine.extractionCalls, 0);
    },
  );
  test(
    'failed write never acknowledges saved and can retry the same answer',
    () async {
      final events = <String>[];
      Answers values = {};
      var fail = true;
      final voice = VoiceCoordinator(
        engine: TestEngine(events),
        schema: schema,
        readValues: () => values,
        audio: TestAudio(events),
        playback: false,
        onPatch: (patch, source) async {
          if (fail) throw StateError('Disk full');
          values = patch.values;
        },
      );
      addTearDown(voice.shutdown);
      await voice.begin();
      await voice.choose(schema.fields.first.options[1]);
      expect(voice.state, VoiceState.error);
      expect(voice.hasUnsavedAnswer, isTrue);
      expect(voice.savedMessage, isEmpty);
      expect(values, isEmpty);
      fail = false;
      await voice.retrySave();
      expect(values['installation_outcome']!.toJson(), 'partial');
      expect(voice.hasUnsavedAnswer, isFalse);
      expect(voice.savedMessage, isNotEmpty);
    },
  );
  test('pause discards recognition that finishes later', () async {
    final events = <String>[],
        audio = TestAudio(<String>[]),
        engine = TestEngine(<String>[]);
    engine.recognition = Completer<String>();
    var writes = 0;
    final voice = VoiceCoordinator(
      engine: engine,
      schema: schema,
      readValues: () => {},
      audio: audio,
      playback: false,
      onPatch: (_, _) async {
        writes++;
      },
    );
    addTearDown(voice.shutdown);
    await voice.begin();
    audio.feed();
    final turn = voice.finish();
    while (!engine.events.contains('transcribe')) {
      await Future<void>.delayed(Duration.zero);
    }
    await voice.pause();
    engine.recognition!.complete('Fully completed');
    await turn;
    expect(writes, 0);
    expect(voice.state, VoiceState.paused);
    expect(voice.transcript, isEmpty);
    expect(events, isEmpty);
  });
  test('denied microphone retains explicit touch choices', () async {
    final audio = TestAudio([])..permitted = false;
    Answers values = {};
    final voice = VoiceCoordinator(
      engine: TestEngine([]),
      schema: schema,
      readValues: () => values,
      audio: audio,
      playback: false,
      onPatch: (patch, _) async {
        values = patch.values;
      },
    );
    addTearDown(voice.shutdown);
    await voice.begin();
    expect(voice.state, VoiceState.error);
    expect(voice.canChoose, isTrue);
    await voice.choose(schema.fields.first.options[2]);
    expect(values['installation_outcome']!.toJson(), 'unable');
    expect(voice.savedMessage, isNotEmpty);
  });
  test(
    'completion aliases are explicit and negation/alternatives are not guessed',
    () {
      final field = schema.fields.first;
      expect(
        directSpokenAnswer(field, 'Fully completed.')!.toJson(),
        'completed',
      );
      expect(
        directSpokenAnswer(field, 'Partially completed.')!.toJson(),
        'partial',
      );
      expect(directSpokenAnswer(field, 'Not completed.')!.toJson(), 'unable');
      for (final text in [
        'fully or partially',
        'no',
        'not fully',
        'maybe completed',
        'not partially completed',
      ]) {
        expect(directSpokenAnswer(field, text), isNull);
      }
      expect(
        directSpokenAnswer(
          schema.fields.firstWhere((f) => f.id == 'connectivity_test'),
          'Not tested',
        )!.toJson(),
        'not_tested',
      );
    },
  );
  test(
    'endpoint waits for speech then silence and also times out empty input',
    () {
      final endpoint = TurnEndpoint();
      expect(endpoint.observe(0, const Duration(seconds: 1)), isFalse);
      expect(
        endpoint.observe(.08, const Duration(milliseconds: 1100)),
        isFalse,
      );
      expect(
        endpoint.observe(.08, const Duration(milliseconds: 1200)),
        isFalse,
      );
      expect(endpoint.heardSpeech, isTrue);
      expect(endpoint.observe(0, const Duration(milliseconds: 2000)), isFalse);
      expect(endpoint.observe(0, const Duration(milliseconds: 2600)), isTrue);
      expect(TurnEndpoint().observe(0, const Duration(seconds: 8)), isTrue);
    },
  );
  test(
    'spoken prompt preparation shares a bounded cache, not engineer recordings',
    () async {
      final events = <String>[],
          cache = PromptAudioCache(TestEngine(<String>[]));
      final first = cache.synthesize('Question');
      final second = cache.synthesize('Question');
      expect(identical(first, second), isTrue);
      await first;
      expect(events, isEmpty);
      cache.clear();
      expect(identical(first, cache.synthesize('Question')), isFalse);
    },
  );
}
