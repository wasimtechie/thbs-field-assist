import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/conversation.dart';

/// Controlled synthetic speech only. Never opens a microphone or an account.
Future<void> main(List<String> args) async {
  final engine = FieldVoice();
  final results = <Json>[];
  try {
    await engine.load(args.single);
    final form = FormDefinition.fromJson(
      jsonDecode(
            File(
              '../../fixtures/templates/fibre-cable-label.json',
            ).readAsStringSync(),
          )
          as Json,
    );
    final cases = [
      ('installation_outcome', 'Not completed.', 'unable'),
      ('installation_outcome', 'Partially completed.', 'partial'),
      ('installation_outcome', 'Fully completed.', 'completed'),
      ('optical_reading', 'Minus twenty two point four.', -22.4),
      ('connectivity_test', 'Not tested.', 'not_tested'),
    ];
    for (final (fieldId, text, expected) in cases) {
      final audio = await engine.synthesize(text);
      final pcm = Float32List(
        (audio.samples.length * 16000 / audio.sampleRate).floor(),
      );
      for (var i = 0; i < pcm.length; i++) {
        final at = i * audio.sampleRate / 16000;
        final low = at.floor(),
            high = (low + 1).clamp(0, audio.samples.length - 1);
        pcm[i] =
            audio.samples[low] +
            (audio.samples[high] - audio.samples[low]) * (at - low);
      }
      final clock = Stopwatch()..start();
      final heard = await engine.transcribe(pcm);
      final field = form.fields.firstWhere((f) => f.id == fieldId);
      final actual = directSpokenAnswer(field, heard)?.toJson();
      results.add({
        'syntheticSpokenText': text,
        'transcript': heard,
        'expectedValue': expected,
        'actualValue': actual,
        'matches': actual == expected,
        'recognitionMs': clock.elapsedMilliseconds,
      });
    }
    final report = {
      'scope':
          'macOS native Kokoro-to-Whistle synthetic replay; no live microphone, phone, accent/noise accuracy or latency acceptance claim.',
      'audioInput':
          'Full resampled 16 kHz PCM, no energy trimming or device effects',
      'cases': results,
      'allMatched': results.every((r) => r['matches'] == true),
    };
    File(
      '../../docs/evidence/voice-accuracy-native-replay.json',
    ).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    );
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    await engine.unload();
    exit(report['allMatched'] == true ? 0 : 1);
  } catch (e) {
    stderr.writeln('Synthetic native replay failed: $e');
    exit(1);
  }
}
