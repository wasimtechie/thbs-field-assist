import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/voice/speech_input.dart';
import 'guided_voice_test.dart' show resample;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Whistle recognises a seven-sentence visit summary and maps only grounded fields',
    (tester) async {
      final api = ApiClient();
      final login = await api.send(
        'auth/login',
        method: 'POST',
        body: {
          'email': 'closure@fieldassist.demo',
          'password': '123456',
          'audience': 'mobile',
        },
      );
      api.token = login['token'] as String;
      final provision = await api.send(
        'devices/provision',
        method: 'POST',
        body: {
          'deviceId': const Uuid().v4(),
          'platform': 'ios',
          'appVersion': 'synthetic-summary-check',
          'osVersion': 'Simulator diagnostics',
        },
      );
      final directory = await AssetInstaller(
        api,
      ).install((provision['manifest'] as Json)['assets'] as Json, (_) {});
      final engine = FieldVoice();
      await engine.load(directory);
      addTearDown(engine.unload);
      final form = compactClosureForm(
        FormDefinition.fromJson(provision['template'] as Json),
      );
      const narrative =
          'Installed the O N T in the living room. Used the existing duct. Connected the fibre at the serving terminal. Optical receive minus eighteen point two d B M. Service test passed. The job is fully completed. No further work required.';
      final speech = await engine.synthesize(narrative);
      final pcm = ByteData.sublistView(resample(speech));
      final samples = Float32List(pcm.lengthInBytes ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = pcm.getInt16(i * 2, Endian.little) / 32768;
      }
      final watch = Stopwatch()..start();
      final transcript = await engine.transcribe(trimSpeechSilence(samples));
      final elapsed = watch.elapsedMilliseconds;
      final values = {
        for (final f in compactNarrativeFacts(form, transcript))
          f['fieldId']: f['value'],
      };
      debugPrint(
        'SUMMARY_NATIVE: ${samples.length / 16000}s audio; ${elapsed}ms ASR; transcript=$transcript; values=$values',
      );
      expect(transcript.toLowerCase(), contains('living room'));
      expect(values['actual_work'], contains('further work'));
      expect(values['claimed_outcome'], 'completed');
      expect(values['operational_test'], 'passed');
      expect(values['optical_rx_dbm'], -18.2);
      expect(values['next_action'], isNotNull);
      expect(
        values['serving_asset'],
        isNull,
        reason: 'No identifier was spoken; ask for it.',
      );
    },
  );
}
