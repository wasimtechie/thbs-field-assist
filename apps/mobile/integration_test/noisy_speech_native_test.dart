import 'dart:convert';
import 'dart:math' as math;
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/voice/conversation.dart';
import 'package:field_assist/features/voice/speech_input.dart';
import 'guided_voice_test.dart' show resample;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native recognition and turn detection with deterministic synthetic background noise',
    (tester) async {
      final snapshot =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/offline_demo/bootstrap.json',
                ),
              )
              as Json;
      final directory = await AssetInstaller(
        ApiClient(),
      ).installBundled(snapshot, (_) {});
      final engine = FieldVoice();
      await engine.load(directory);
      addTearDown(engine.unload);
      final form = compactClosureForm(
        FormDefinition.fromJson(snapshot['template'] as Json),
      );
      const cases = [
        ('claimed_outcome', 'The work is fully completed.', 'completed'),
        ('operational_test', 'The service test passed.', 'passed'),
        ('operational_test', 'The test has not passed.', null),
        ('optical_rx_dbm', 'Minus eighteen point two d B M.', -18.2),
      ];
      for (final (id, words, expected) in cases) {
        final pcm = ByteData.sublistView(
          resample(await engine.synthesize(words)),
        );
        const before = 9600, after = 24000;
        final audio = Float32List(before + pcm.lengthInBytes ~/ 2 + after);
        final random = math.Random(42);
        for (var i = 0; i < audio.length; i++) {
          // Repeatable hum plus broadband noise, RMS approximately 0.006.
          audio[i] =
              .007 * math.sin(2 * math.pi * 100 * i / 16000) +
              (random.nextDouble() * 2 - 1) * .006;
          if (i >= before && i < audio.length - after) {
            audio[i] += pcm.getInt16((i - before) * 2, Endian.little) / 32768;
          }
        }
        final endpoint = TurnEndpoint(
          adaptiveNoise: true,
          silence: const Duration(milliseconds: 700),
        );
        int? ended;
        for (var at = 0; at + 320 <= audio.length; at += 320) {
          var power = 0.0;
          for (var i = at; i < at + 320; i++) {
            power += audio[i] * audio[i];
          }
          if (endpoint.observe(
            math.sqrt(power / 320),
            Duration(microseconds: (at + 320) * 1000000 ~/ 16000),
          )) {
            ended = at + 320;
            break;
          }
        }
        expect(
          ended,
          isNotNull,
          reason: 'Ambient noise must not hold the turn open.',
        );
        expect(endpoint.heardSpeech, true);
        final transcript = await engine.transcribe(
          trimSpeechSilence(Float32List.sublistView(audio, 0, ended)),
        );
        final answer = closureSpokenAnswer(
          form.fields.firstWhere((f) => f.id == id),
          transcript,
        );
        debugPrint(
          'NOISY_NATIVE: $words -> $transcript -> ${answer?.toJson()}; end=${ended! / 16000}s',
        );
        expect(
          answer?.toJson(),
          expected,
          reason: 'Synthetic noisy speech: $words; transcript: $transcript',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
