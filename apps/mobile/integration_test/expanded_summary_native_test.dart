import 'dart:convert';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/voice/speech_input.dart';
import 'guided_voice_test.dart' show resample;

// Synthetic, fully local model replay. No microphone, report changes or upload.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native offline speech maps the complete fifteen-field S1 summary',
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
      expect(engine.streamingAvailable, true);
      final form = compactClosureForm(
        FormDefinition.fromJson(snapshot['template'] as Json),
        expanded: true,
      );
      const narrative =
          'The customer granted access for the visit. '
          'The customer approved the O N T location in the living room, and I installed the O N T there. '
          'I used the existing duct for the fibre route. '
          'I installed the external fibre and connection point, then fitted the internal fibre to the O N T. '
          'I checked the O N T power and status. '
          'The optical receive reading was minus eighteen point two d B M. '
          'The service test passed and the service is live. '
          'I showed the customer the equipment. '
          'The installation is fully completed, and I left the site safe and tidy. '
          'No further work is required.';
      final pieces = <Float32List>[];
      // Preserve complete phrases rather than introducing a synthetic pause
      // halfway through "minus eighteen" or "safe and tidy".
      for (final chunk in narrative.split(RegExp(r'(?<!\d)\.\s+'))) {
        final pcm = ByteData.sublistView(
          resample(await engine.synthesize(chunk)),
        );
        final samples = Float32List(pcm.lengthInBytes ~/ 2);
        for (var i = 0; i < samples.length; i++) {
          samples[i] = pcm.getInt16(i * 2, Endian.little) / 32768;
        }
        pieces.add(samples);
        pieces.add(Float32List(4000));
      }
      final samples = Float32List(pieces.fold<int>(0, (n, p) => n + p.length));
      var offset = 0;
      for (final piece in pieces) {
        samples.setRange(offset, offset + piece.length, piece);
        offset += piece.length;
      }
      final transcript = await engine.transcribe(trimSpeechSilence(samples));
      final values = {
        for (final fact in compactNarrativeFacts(form, transcript))
          fact['fieldId']: fact['value'],
      };
      final missing = provisionClosureLabels.keys
          .where((id) => values[id] == null)
          .toList();
      debugPrint(
        'EXPANDED_S1_NATIVE: ${jsonEncode({'transcript': transcript, 'values': values, 'missing': missing})}',
      );
      expect(missing, isEmpty);
      expect(values['optical_rx_dbm'], -18.2);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
