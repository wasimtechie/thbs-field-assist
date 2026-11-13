import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record/record.dart';

/// Diagnostic only: native microphone bytes are counted and discarded. Does
/// not open account storage, run speech models or create engineer reports.
/// Run on a dedicated simulator with `flutter test ... --no-uninstall` so test
/// cleanup retains the app's data and microphone consent.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final rate in [48000, 16000]) {
    testWidgets(
      'iOS native microphone at $rate Hz',
      (tester) async {
        final recorder = AudioRecorder();
        addTearDown(
          () => recorder.dispose().timeout(const Duration(seconds: 10)),
        );
        expect(
          await recorder.hasPermission().timeout(const Duration(seconds: 60)),
          true,
        );
        debugPrint('VOICE_CAPTURE_PROBE $rate starting');
        final stream = await recorder
            .startStream(
              RecordConfig(
                encoder: AudioEncoder.pcm16bits,
                numChannels: 1,
                sampleRate: rate,
              ),
            )
            .timeout(const Duration(seconds: 10));
        debugPrint('VOICE_CAPTURE_PROBE $rate connected');
        final first = await stream.first.timeout(const Duration(seconds: 5));
        expect(first, isNotEmpty);
        await recorder.stop().timeout(const Duration(seconds: 10));
        debugPrint('VOICE_CAPTURE_PROBE $rate PASS bytes=${first.length}');
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
