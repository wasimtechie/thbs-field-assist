import 'dart:convert';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/voice/speech_input.dart';
import 'guided_voice_test.dart' show resample;

/// Synthetic model replay only. Does not open, modify or submit user reports.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'the exact S1 rehearsal survives native speech recognition',
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
      const narrative =
          'I installed the ONT in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two d B M. The service test passed. The job is fully completed. I showed the customer the equipment.';
      final pcm = ByteData.sublistView(
        resample(await engine.synthesize(narrative)),
      );
      final samples = Float32List(pcm.lengthInBytes ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = pcm.getInt16(i * 2, Endian.little) / 32768;
      }
      final watch = Stopwatch()..start();
      final transcript = await engine.transcribe(trimSpeechSilence(samples));
      final values = {
        for (final fact in compactNarrativeFacts(form, transcript))
          fact['fieldId']: fact['value'],
      };
      debugPrint(
        'S1_SUMMARY_NATIVE: ${samples.length / 16000}s audio; '
        '${watch.elapsedMilliseconds}ms ASR; transcript=$transcript; values=$values',
      );
      expect(values['actual_work'], contains('living room'));
      expect(values['claimed_outcome'], 'completed');
      expect(values['operational_test'], 'passed');
      expect(values['optical_rx_dbm'], -18.2);
      expect(compactClosureLabels.keys.where((id) => values[id] == null), [
        'serving_asset',
        'next_action',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
