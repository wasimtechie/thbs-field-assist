import 'dart:convert';
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
import 'package:field_assist/features/voice/speech_input.dart';
import 'guided_voice_test.dart' show resample;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native speech replay maps natural choices with no network or report changes',
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
      const samples = [
        ('claimed_outcome', 'The work is fully completed.', 'completed'),
        ('claimed_outcome', 'I have fully completed the work.', 'completed'),
        ('claimed_outcome', 'The job is partially completed.', 'partial'),
        ('claimed_outcome', 'The job is on hold.', 'hold'),
        ('claimed_outcome', 'The second option.', 'partial'),
        ('operational_test', 'The service test passed.', 'passed'),
        ('operational_test', 'The test failed.', 'failed'),
        ('operational_test', 'Not tested.', 'not_tested'),
        ('operational_test', 'The test has not passed.', null),
        ('claimed_outcome', 'Not fully completed.', null),
      ];
      for (final (id, words, expected) in samples) {
        final pcm = ByteData.sublistView(
          resample(await engine.synthesize(words)),
        );
        final audio = Float32List(pcm.lengthInBytes ~/ 2);
        for (var i = 0; i < audio.length; i++) {
          audio[i] = pcm.getInt16(i * 2, Endian.little) / 32768;
        }
        final transcript = await engine.transcribe(trimSpeechSilence(audio));
        final answer = closureSpokenAnswer(
          form.fields.firstWhere((f) => f.id == id),
          transcript,
        );
        debugPrint(
          'SPOKEN_CHOICE_REPLAY: $words -> $transcript -> ${answer?.toJson()}',
        );
        expect(
          answer?.toJson(),
          expected,
          reason: 'Generated speech: $words; Whistle: $transcript',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
