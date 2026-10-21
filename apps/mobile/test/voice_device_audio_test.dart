import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'support/voice_fakes.dart';

class CaptureRecorder implements AudioRecorder {
  final input = StreamController<Uint8List>(sync: true);
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
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
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
