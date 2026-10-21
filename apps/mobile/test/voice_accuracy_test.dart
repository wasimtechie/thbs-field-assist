import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/conversation.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'support/voice_fakes.dart';

class CaptureInputEngine extends TestEngine {
  CaptureInputEngine() : super([]);
  Float32List? received;
  @override
  Future<String> transcribe(Float32List pcm) async {
    received = Float32List.fromList(pcm);
    return answer;
  }

  @override
  Future<Json> extract(
    String transcript,
    List<Json> tools,
    String context,
  ) async {
    extractionCalls++;
    // An overconfident model must not turn an unrelated transcript into success.
    return {
      'confidence': .99,
      'function_calls': [
        {
          'name': 'record_installation_outcome',
          'arguments': {'result': 'completed'},
        },
      ],
    };
  }
}

void main() {
  test(
    'explicit natural completion phrases preserve negation without guessing',
    () {
      final field = schema.fields.first;
      for (final text in [
        'Not completed',
        'Not complete',
        'The work is not completed',
        'I have not completed the work',
        "I haven't completed the job",
        'I could not complete the installation',
      ]) {
        expect(
          directSpokenAnswer(field, text)?.toJson(),
          'unable',
          reason: text,
        );
      }
      for (final text in [
        'The job is fully completed',
        'I have completed the installation',
      ]) {
        expect(directSpokenAnswer(field, text)?.toJson(), 'completed');
      }
      expect(directSpokenAnswer(field, 'not fully completed'), isNull);
    },
  );
  test('quiet continuation after a loud syllable is still speech', () {
    final endpoint = TurnEndpoint();
    var time = 0;
    bool frame(double level) =>
        endpoint.observe(level, Duration(milliseconds: time += 20));
    for (var i = 0; i < 20; i++) {
      expect(frame(.10), isFalse);
    }
    for (var i = 0; i < 65; i++) {
      expect(frame(.008), isFalse);
    }
  });

  test('a one-second natural pause does not split not from completed', () {
    final endpoint = TurnEndpoint();
    var time = 0;
    bool frame(double level) =>
        endpoint.observe(level, Duration(milliseconds: time += 20));
    for (var i = 0; i < 15; i++) {
      frame(.05);
    }
    for (var i = 0; i < 50; i++) {
      expect(frame(0), isFalse);
    }
    for (var i = 0; i < 20; i++) {
      expect(frame(.03), isFalse);
    }
  });

  test(
    'recognizer receives the full quiet opening and trailing speech, unchanged',
    () async {
      final engine = CaptureInputEngine()..answer = 'Not completed';
      final audio = TestAudio([]);
      Answers values = {};
      final voice = VoiceCoordinator(
        engine: engine,
        schema: schema,
        readValues: () => values,
        audio: audio,
        playback: false,
        onPatch: (patch, _) async => values = patch.values,
      );
      addTearDown(voice.shutdown);
      await voice.begin();
      final bytes = ByteData(32000);
      for (var i = 0; i < 16000; i++) {
        // Deliberately quiet opening/ending around a much louder middle word.
        final magnitude = i < 6400 || i >= 11200 ? 50 : 5000;
        bytes.setInt16(i * 2, i.isEven ? magnitude : -magnitude, Endian.little);
      }
      audio.bytes!(bytes.buffer.asUint8List());
      await voice.finish();
      expect(engine.received, hasLength(16000));
      expect(engine.received!.first, 50 / 32768);
      expect(engine.received!.last, -50 / 32768);
      expect(values['installation_outcome']!.toJson(), 'unable');
    },
  );

  for (final misheard in ['bots', 'excellent', 'excited']) {
    test(
      'misheard "$misheard" is clarified without guessing completion',
      () async {
        final engine = CaptureInputEngine()..answer = misheard;
        final audio = TestAudio([]);
        Answers values = {};
        var writes = 0;
        final voice = VoiceCoordinator(
          engine: engine,
          schema: schema,
          readValues: () => values,
          audio: audio,
          playback: false,
          onPatch: (patch, _) async {
            writes++;
            values = patch.values;
          },
        );
        addTearDown(voice.shutdown);
        await voice.begin();
        audio.feed();
        await voice.finish();
        expect(writes, 0);
        expect(values, isEmpty);
        expect(engine.extractionCalls, 0);
        expect(voice.activeField!.id, 'installation_outcome');
        expect(voice.savedMessage, isEmpty);
        expect(voice.question, contains('not saved'));
      },
    );
  }
}
