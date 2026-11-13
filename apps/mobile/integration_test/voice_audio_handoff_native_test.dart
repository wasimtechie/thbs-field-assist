import 'dart:async';
import 'dart:math';
import 'package:audio_session/audio_session.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Exercises native speaker/microphone ownership. Captured PCM is discarded;
/// no engineer reports, model state, credentials or audio files are changed.
/// Use a dedicated simulator and `flutter test ... --no-uninstall`; Flutter's
/// default cleanup otherwise removes the installed app and its local data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'iOS TTS output survives repeated microphone handoffs',
    (tester) async {
      expect(defaultTargetPlatform, TargetPlatform.iOS);
      final samples = Float32List.fromList(
        List.generate(8000, (i) => .04 * sin(2 * pi * 440 * i / 16000)),
      );
      final prompt = SynthesizedAudio(samples, 16000);
      // Establish whether output alone works before opening the input/output
      // session. This distinguishes a simulator bridge failure from handoff.
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await session.setActive(true);
      final audio = DeviceVoiceAudio();
      addTearDown(() => audio.close().timeout(const Duration(seconds: 10)));
      debugPrint('VOICE_AUDIO_HANDOFF speaker-only starting');
      expect(
        await audio.play(prompt, (_) {}).timeout(const Duration(seconds: 8)),
        true,
      );
      debugPrint('VOICE_AUDIO_HANDOFF speaker-only passed');
      final errors = <Object>[];
      debugPrint('VOICE_AUDIO_HANDOFF configuring conversation');
      await audio
          .configure(() => errors.add(StateError('Audio interrupted')))
          .timeout(const Duration(seconds: 10));
      debugPrint('VOICE_AUDIO_HANDOFF conversation configured');
      expect(
        await audio.hasPermission().timeout(const Duration(seconds: 60)),
        true,
      );
      var frames = 0;
      for (var turn = 0; turn < 8; turn++) {
        debugPrint('VOICE_AUDIO_HANDOFF turn=${turn + 1} output starting');
        expect(
          await audio.play(prompt, (_) {}).timeout(const Duration(seconds: 8)),
          true,
        );
        final input = Completer<void>();
        debugPrint('VOICE_AUDIO_HANDOFF turn=${turn + 1} capture starting');
        await audio
            .capture(
              onBytes: (bytes) {
                frames++;
                if (bytes.isNotEmpty && !input.isCompleted) input.complete();
              },
              onLevel: (_) {},
              onError: errors.add,
            )
            .timeout(const Duration(seconds: 10));
        debugPrint('VOICE_AUDIO_HANDOFF turn=${turn + 1} capture connected');
        await input.future.timeout(const Duration(seconds: 5));
        // Longer than the old player's 500 ms deferred-pause interval, when
        // both reported crashes occurred after the microphone had started.
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await audio.stopCapture();
        debugPrint('VOICE_AUDIO_HANDOFF turn=${turn + 1} frames=$frames');
      }
      final playing = audio.play(prompt, (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      audio.handleInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      audio.handleInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      await audio.stopPlayback();
      expect(await playing, false);
      expect(await audio.play(prompt, (_) {}), true);
      expect(errors, isEmpty);
      expect(frames, greaterThan(0));
      debugPrint(
        'VOICE_AUDIO_HANDOFF PASS: 8 native output/input turns, stop/replay and duck/restore',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
