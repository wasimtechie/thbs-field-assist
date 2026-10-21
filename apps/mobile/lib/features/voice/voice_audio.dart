import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:field_voice/field_voice.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:record/record.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'pcm_meter.dart';

// Each conversation owns its capture/playback lifecycle. Integration tests can
// supply generated PCM through this same boundary without opening a microphone.
final voiceAudioFactoryProvider = Provider<VoiceAudio Function()>(
  (ref) => DeviceVoiceAudio.new,
);

abstract interface class VoiceAudio {
  Future<void> configure(void Function() onInterruption);
  Future<bool> hasPermission();

  /// Capture emits a normalized RMS level for each 20 ms PCM frame.
  Future<void> capture({
    required void Function(Uint8List) onBytes,
    required void Function(double) onLevel,
    required void Function(Object) onError,
  });
  Future<void> stopCapture();
  Future<bool> play(SynthesizedAudio audio, void Function(double) onLevel);
  Future<void> stopPlayback();
  Future<void> close();
}

class DeviceVoiceAudio implements VoiceAudio {
  DeviceVoiceAudio({
    AudioRecorder? recorder,
    TargetPlatform? platform,
    this.onInterruption,
  }) : recorder = recorder ?? AudioRecorder(),
       platform = platform ?? defaultTargetPlatform;
  final AudioRecorder recorder;
  final TargetPlatform platform;
  AudioSession? _session;
  StreamSubscription<Uint8List>? _bytes;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _noisy;
  SoundHandle? _handle;
  Timer? _meter;
  Completer<bool>? _completion;
  int _playGeneration = 0, _captureGeneration = 0;
  bool _ducked = false;
  void Function()? onInterruption;

  static AudioSessionConfiguration get sessionConfiguration =>
      const AudioSessionConfiguration.speech().copyWith(
        androidWillPauseWhenDucked: false,
      );

  /// Notifications may lower speech playback briefly, but must not cancel the
  /// microphone/answer. Calls and non-mixable focus loss remain interruptions.
  void handleInterruption(AudioInterruptionEvent event) {
    if (event.type == AudioInterruptionType.duck) {
      _ducked = event.begin;
      final handle = _handle;
      if (handle != null && SoLoud.instance.isInitialized) {
        SoLoud.instance.setVolume(handle, _ducked ? .25 : 1);
      }
    } else if (event.begin) {
      _ducked = false;
      onInterruption?.call();
    }
  }

  @override
  Future<void> configure(void Function() onInterruption) async {
    _session = await AudioSession.instance;
    this.onInterruption = onInterruption;
    await _session!.configure(sessionConfiguration);
    _interruptions ??= _session!.interruptionEventStream.listen(
      handleInterruption,
    );
    _noisy ??= _session!.becomingNoisyEventStream.listen(
      (_) => onInterruption(),
    );
    await _session!.setActive(true);
  }

  @override
  Future<bool> hasPermission() => recorder.hasPermission();
  @override
  Future<void> capture({
    required void Function(Uint8List) onBytes,
    required void Function(double) onLevel,
    required void Function(Object) onError,
  }) async {
    final generation = ++_captureGeneration;
    await stopPlayback();
    if (generation != _captureGeneration) return;
    await _session?.setActive(true);
    if (generation != _captureGeneration) return;
    final stream = await recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // Restore the recording settings used before build 2014. OEM speech
        // effects can attenuate the first/quiet words; retain unprocessed PCM.
        echoCancel: false,
        noiseSuppress: false,
        // audio_session already owns Android focus for the conversation.
        // A second request from record interrupts that same session at the
        // playback -> capture handoff. Calls/focus loss/headset removal still
        // pause through the shared session subscriptions above.
        audioInterruption: platform == TargetPlatform.android
            ? AudioInterruptionMode.none
            : AudioInterruptionMode.pause,
      ),
    );
    if (generation != _captureGeneration) {
      await recorder.stop();
      return;
    }
    final meter = PcmLevelMeter(onLevel);
    _bytes = stream.listen((bytes) {
      if (generation != _captureGeneration) return;
      onBytes(bytes);
      meter.add(bytes);
    }, onError: onError);
  }

  @override
  Future<void> stopCapture() async {
    _captureGeneration++;
    await recorder.stop();
    await _bytes?.cancel();
    _bytes = null;
  }

  @override
  Future<bool> play(
    SynthesizedAudio audio,
    void Function(double) onLevel,
  ) async {
    final generation = ++_playGeneration;
    await stopCapture();
    await _stopPlayback();
    if (generation != _playGeneration) return false;
    await _session?.setActive(true);
    if (!SoLoud.instance.isInitialized) await SoLoud.instance.init();
    final source = await SoLoud.instance.loadMem(
      'kokoro-${DateTime.now().microsecondsSinceEpoch}.wav',
      encodeVoiceWav(audio),
      autoDispose: true,
    );
    if (generation != _playGeneration) {
      await SoLoud.instance.disposeSource(source);
      return false;
    }
    final completion = Completer<bool>();
    _completion = completion;
    _handle = SoLoud.instance.play(source);
    if (_ducked) SoLoud.instance.setVolume(_handle!, .25);
    _meter = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final handle = _handle;
      if (handle == null || !SoLoud.instance.getIsValidVoiceHandle(handle)) {
        _meter?.cancel();
        _handle = null;
        onLevel(0);
        if (!completion.isCompleted) completion.complete(true);
        return;
      }
      final index =
          SoLoud.instance.getPosition(handle).inMicroseconds *
          audio.sampleRate ~/
          1000000;
      var power = 0.0;
      final end = min(index + 1024, audio.samples.length);
      for (var i = index; i < end; i++) {
        power += audio.samples[i] * audio.samples[i];
      }
      onLevel(sqrt(power / max(1, end - index)).clamp(0, 1));
    });
    return completion.future;
  }

  @override
  Future<void> stopPlayback() async {
    _playGeneration++;
    await _stopPlayback();
  }

  Future<void> _stopPlayback() async {
    _meter?.cancel();
    final handle = _handle;
    _handle = null;
    if (handle != null && SoLoud.instance.isInitialized) {
      await SoLoud.instance.stop(handle);
    }
    if (_completion != null && !_completion!.isCompleted) {
      _completion!.complete(false);
    }
    _completion = null;
  }

  @override
  Future<void> close() async {
    await stopCapture();
    await stopPlayback();
    await _interruptions?.cancel();
    await _noisy?.cancel();
    onInterruption = null;
    await recorder.dispose();
    await _session?.setActive(false);
  }
}

Uint8List encodeVoiceWav(SynthesizedAudio audio) {
  final b = ByteData(44 + audio.samples.length * 2);
  void text(int at, String value) {
    for (var i = 0; i < value.length; i++) {
      b.setUint8(at + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  b.setUint32(4, b.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, audio.sampleRate, Endian.little);
  b.setUint32(28, audio.sampleRate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  text(36, 'data');
  b.setUint32(40, audio.samples.length * 2, Endian.little);
  for (var i = 0; i < audio.samples.length; i++) {
    b.setInt16(
      44 + i * 2,
      (audio.samples[i].clamp(-1, 1) * 32767).round(),
      Endian.little,
    );
  }
  return b.buffer.asUint8List();
}
