import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'package:field_voice/field_voice.dart';
import 'package:audio_session/audio_session.dart';
import 'support/voice_fakes.dart';

class CaptureRecorder implements AudioRecorder {
  final input = StreamController<Uint8List>.broadcast(sync: true);
  RecordConfig? config;
  int stops = 0;
  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    this.config = config;
    return input.stream;
  }

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) =>
      const Stream.empty();
  @override
  Future<String?> stop() async {
    stops++;
    return null;
  }

  @override
  Future<void> dispose() => input.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const iosChannel = MethodChannel('test/ios_voice_playback');
  final tone = SynthesizedAudio(Float32List.fromList([0, .5, -.5, 0]), 16000);
  test(
    'iOS uses speech output while the recorder configures its own input',
    () {
      expect(
        DeviceVoiceAudio.sessionConfiguration.avAudioSessionCategory,
        AVAudioSessionCategory.playback,
      );
      expect(
        DeviceVoiceAudio.sessionConfiguration.avAudioSessionMode,
        AVAudioSessionMode.spokenAudio,
      );
    },
  );
  test(
    'iOS playback awaits native completion and hands capture off after stop',
    () async {
      final recorder = CaptureRecorder();
      final audio = DeviceVoiceAudio(
        recorder: recorder,
        platform: TargetPlatform.iOS,
        iosPlaybackChannel: iosChannel,
      );
      final calls = <MethodCall>[];
      final playing = Completer<void>(), finished = Completer<bool>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, (call) async {
            calls.add(call);
            if (call.method == 'play') {
              playing.complete();
              return finished.future;
            }
            if (call.method == 'stop') finished.complete(false);
            return null;
          });
      addTearDown(() async {
        await audio.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(iosChannel, null);
      });
      var completed = false;
      final playback = audio.play(tone, (_) {}).then((value) {
        completed = true;
        return value;
      });
      await playing.future;
      expect(completed, false);
      final args = calls.single.arguments as Map;
      expect((args['wav'] as Uint8List).sublist(0, 4), [82, 73, 70, 70]);
      expect(args['volume'], 1.0);
      await audio.capture(onBytes: (_) {}, onLevel: (_) {}, onError: (_) {});
      expect(await playback, false);
      expect(calls.map((call) => call.method), ['play', 'stop']);
      expect((calls.last.arguments as Map)['id'], args['id']);
      expect(recorder.config, isNotNull);
    },
  );
  test('iOS native completion and errors release the waveform timer', () async {
    final audio = DeviceVoiceAudio(
      recorder: CaptureRecorder(),
      platform: TargetPlatform.iOS,
      iosPlaybackChannel: iosChannel,
    );
    final levels = <double>[];
    var failPlayback = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iosChannel, (call) async {
          if (call.method == 'play') {
            if (failPlayback) {
              throw PlatformException(code: 'VOICE_PLAYBACK_FAILED');
            }
            return true;
          }
          return null;
        });
    addTearDown(() async {
      await audio.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(iosChannel, null);
    });
    expect(await audio.play(tone, levels.add), true);
    expect(levels.last, 0);
    failPlayback = true;
    await expectLater(
      audio.play(tone, levels.add),
      throwsA(isA<PlatformException>()),
    );
    expect(levels.last, 0);
    // A new attempt remains usable after an output error.
    failPlayback = false;
    expect(await audio.play(tone, levels.add), true);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '${platform.name} optional noise reduction keeps gain fixed and preserves focus ownership',
      () async {
        final recorder = CaptureRecorder();
        final audio = DeviceVoiceAudio(
          recorder: recorder,
          platform: platform,
          noiseReduction: true,
        );
        addTearDown(audio.close);
        await audio.capture(onBytes: (_) {}, onLevel: (_) {}, onError: (_) {});
        expect(recorder.config!.noiseSuppress, true);
        expect(recorder.config!.echoCancel, true);
        expect(recorder.config!.autoGain, false);
        expect(
          recorder.config!.audioInterruption,
          platform == TargetPlatform.android
              ? AudioInterruptionMode.none
              : AudioInterruptionMode.pause,
        );
      },
    );
    test(
      '${platform.name} capture config preserves PCM and uses the correct focus owner',
      () async {
        final recorder = CaptureRecorder();
        final audio = DeviceVoiceAudio(recorder: recorder, platform: platform);
        addTearDown(audio.close);
        final received = <int>[];
        await audio.capture(
          onBytes: (bytes) => received.addAll(bytes),
          onLevel: (_) {},
          onError: (error) => fail('$error'),
        );
        expect(
          recorder.config!.audioInterruption,
          platform == TargetPlatform.android
              ? AudioInterruptionMode.none
              : AudioInterruptionMode.pause,
        );
        expect(recorder.config!.encoder, AudioEncoder.pcm16bits);
        expect(recorder.config!.sampleRate, 16000);
        expect(recorder.config!.numChannels, 1);
        expect(recorder.config!.echoCancel, isFalse);
        expect(recorder.config!.noiseSuppress, isFalse);
        recorder.input.add(Uint8List.fromList([1, 2, 3, 4]));
        expect(received, [1, 2, 3, 4]);
        await audio.stopCapture();
        recorder.input.add(Uint8List.fromList([5, 6]));
        expect(received, [1, 2, 3, 4]);
        expect(recorder.stops, greaterThan(0));
      },
    );
  }
  test(
    'native PCM chunks report distinct frame times and preserve every input byte',
    () async {
      final recorder = CaptureRecorder();
      final audio = DeviceVoiceAudio(recorder: recorder);
      addTearDown(audio.close);
      final received = <int>[], positions = <int>[];
      await audio.capture(
        onBytes: received.addAll,
        onLevel: (_) => positions.add(received.length),
        onError: (_) {},
      );
      final bytes = Uint8List.fromList(
        List.generate(640 * 4 + 17, (i) => i % 256),
      );
      recorder.input.add(bytes);
      expect(received, bytes);
      expect(positions, [640, 1280, 1920, 2560]);
    },
  );
  test(
    'an unexpectedly closed microphone stream reports an error instead of silently listening',
    () async {
      final recorder = CaptureRecorder();
      final audio = DeviceVoiceAudio(recorder: recorder);
      addTearDown(audio.close);
      final errors = <Object>[];
      await audio.capture(
        onBytes: (_) {},
        onLevel: (_) {},
        onError: errors.add,
      );
      await recorder.input.close();
      expect(errors.single.toString(), contains('Microphone stream ended'));
    },
  );
  test(
    'shared-session interruption still pauses and discards capture until explicit resume',
    () async {
      final audio = TestAudio([]);
      var writes = 0;
      final voice = VoiceCoordinator(
        engine: TestEngine([]),
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
      expect(voice.state, VoiceState.listening);
      audio.interruption!();
      await Future<void>.delayed(Duration.zero);
      expect(voice.state, VoiceState.paused);
      expect(audio.events, containsAll(['stop-capture', 'stop-playback']));
      audio.feed();
      await voice.finish();
      expect(writes, 0);
      expect(voice.state, VoiceState.paused);
      await voice.begin();
      expect(voice.state, VoiceState.listening);
    },
  );
}
