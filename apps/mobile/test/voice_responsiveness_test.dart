import 'dart:async';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:field_voice/field_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/conversation.dart';
import 'package:field_assist/features/voice/pcm_meter.dart';
import 'package:field_assist/features/voice/prompt_audio_cache.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'support/voice_fakes.dart';
import 'voice_device_audio_test.dart' show CaptureRecorder;

class LargePromptEngine extends TestEngine {
  LargePromptEngine() : super([]);
  int calls = 0;
  @override
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1}) async {
    calls++;
    return SynthesizedAudio(Float32List(1100000), 24000);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'frequent Saved acknowledgment stays warm across a longer question sequence',
    () async {
      final engine = TestEngine([]);
      final actual = PromptAudioCache(engine);
      await actual.synthesize('Saved.');
      for (var i = 0; i < 20; i++) {
        await actual.synthesize('Question $i');
        await actual.synthesize('Saved.');
      }
      expect(engine.events.where((e) => e == 'speak:Saved.'), hasLength(1));
      actual.clear();
    },
  );
  test(
    'prompt cache respects its RAM budget rather than retaining oversized speech',
    () async {
      final engine = LargePromptEngine();
      final actual = PromptAudioCache(engine);
      await actual.synthesize('First');
      await actual.synthesize('Second');
      await actual.synthesize('First');
      expect(engine.calls, 3);
      actual.clear();
    },
  );
  test('PCM RMS frames survive split samples and do not hold an old peak', () {
    final levels = <double>[];
    final meter = PcmLevelMeter(levels.add);
    final bytes = ByteData(1280);
    for (var i = 0; i < 320; i++) {
      bytes.setInt16(i * 2, i.isEven ? 3276 : -3276, Endian.little);
    }
    final input = bytes.buffer.asUint8List();
    meter.add(Uint8List.sublistView(input, 0, 3));
    meter.add(Uint8List.sublistView(input, 3, 227));
    meter.add(Uint8List.sublistView(input, 227));
    expect(levels, hasLength(2));
    expect(levels.first, closeTo(.1, .001));
    expect(levels.last, 0);
  });

  test(
    'short room peaks do not count as an answer; normal speech auto-ends',
    () {
      final endpoint = TurnEndpoint();
      var ms = 0;
      bool frame(double rms) =>
          endpoint.observe(rms, Duration(milliseconds: ms += 20));
      frame(.8);
      for (var i = 0; i < 20; i++) {
        frame(.002);
      }
      expect(endpoint.heardSpeech, isFalse);
      for (var i = 0; i < 15; i++) {
        frame(.08);
      }
      expect(endpoint.heardSpeech, isTrue);
      // A brief thinking pause must not cut off a multi-word answer.
      for (var i = 0; i < 15; i++) {
        expect(frame(.002), isFalse);
      }
      for (var i = 0; i < 10; i++) {
        expect(frame(.06), isFalse);
      }
      expect(frame(.8), isFalse);
      for (var i = 0; i < 10; i++) {
        expect(frame(.05), isFalse);
      }
      for (var i = 0; i < 64; i++) {
        expect(frame(.002), isFalse);
      }
      expect(frame(.002), isTrue);
    },
  );

  test(
    'an answer saves and advances from speech/silence alone, without Done speaking',
    () async {
      final audio = TestAudio([]);
      final saved = Completer<void>();
      Answers values = {};
      final voice = VoiceCoordinator(
        engine: TestEngine([]),
        schema: schema,
        readValues: () => values,
        audio: audio,
        playback: false,
        onPatch: (patch, _) async {
          values = patch.values;
          saved.complete();
        },
      );
      addTearDown(voice.shutdown);
      await voice.begin();
      audio.feed();
      for (var i = 0; i < 15; i++) {
        audio.meter!(.08);
      }
      for (var i = 0; i < 65; i++) {
        audio.meter!(.001);
      }
      await saved.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(values['installation_outcome']!.toJson(), 'partial');
      expect(voice.savedMessage, contains('saved on this device'));
      expect(voice.activeField!.id, 'work_performed');
      expect(voice.state, VoiceState.listening);
      expect(
        voice.lastTurnMetrics.keys,
        containsAll(['recognitionMs', 'saveMs']),
      );
    },
  );

  test(
    'notification duck events preserve capture; call focus loss pauses it',
    () async {
      var interruptions = 0;
      final recorder = CaptureRecorder();
      final audio = DeviceVoiceAudio(
        recorder: recorder,
        onInterruption: () => interruptions++,
      );
      addTearDown(audio.close);
      final bytes = <int>[];
      await audio.capture(
        onBytes: bytes.addAll,
        onLevel: (_) {},
        onError: (e) => fail('$e'),
      );
      expect(
        DeviceVoiceAudio.sessionConfiguration.androidWillPauseWhenDucked,
        isFalse,
      );
      audio.handleInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      recorder.input.add(Uint8List.fromList([1, 2]));
      audio.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      expect(interruptions, 0);
      expect(bytes, [1, 2]);
      expect(recorder.stops, 0);
      audio.handleInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      expect(interruptions, 1);
      audio.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      expect(interruptions, 1);
    },
  );

  test(
    'Saved is acknowledged after persistence, before preparing the next question',
    () async {
      final events = <String>[];
      Answers values = {};
      final voice = VoiceCoordinator(
        engine: TestEngine(events),
        audio: TestAudio(events),
        schema: schema,
        readValues: () => values,
        echoTail: Duration.zero,
        onPatch: (patch, _) async {
          events.add('persist');
          values = patch.values;
        },
      );
      addTearDown(voice.shutdown);
      await voice.begin();
      await voice.choose(schema.fields.first.options[1]);
      final acknowledgment = events.indexOf('speak:Saved.');
      expect(acknowledgment, greaterThan(events.indexOf('persist')));
      expect(
        events.indexOf('speak:${spokenQuestion(voice.activeField!)}'),
        greaterThan(acknowledgment),
      );
      expect(events.where((e) => e.startsWith('speak:Saved. ')), isEmpty);
    },
  );
}
