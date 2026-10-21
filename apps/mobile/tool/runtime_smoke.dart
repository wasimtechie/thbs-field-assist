import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/patch_rules.dart';
import 'package:field_assist/features/voice/field_extraction.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    throw ArgumentError('Pass an absolute verified model-package directory.');
  }
  final engine = FieldVoice();
  final load = Stopwatch()..start();
  await engine.load(args[0]);
  load.stop();
  final schema = FormDefinition.fromJson(
    jsonDecode(File('../../fixtures/templates/repair.json').readAsStringSync())
        as Json,
  );
  final extraction = Stopwatch()..start();
  final output = await extractFormFields(
    engine,
    schema,
    'Replaced twenty metres actually twelve. I have not tested the line.',
  );
  extraction.stop();
  final patch = mergeExtraction(
    schema,
    {},
    output,
    'Replaced twenty metres actually twelve. I have not tested the line.',
  );
  final synthesis = Stopwatch()..start();
  final audio = await engine.synthesize(
    'Replaced twenty metres actually twelve. I have not tested the line.',
  );
  synthesis.stop();
  final resampled = Float32List(
    (audio.samples.length * 16000 / audio.sampleRate).floor(),
  );
  for (var i = 0; i < resampled.length; i++) {
    final at = i * audio.sampleRate / 16000;
    final low = at.floor(), high = (low + 1).clamp(0, audio.samples.length - 1);
    resampled[i] =
        audio.samples[low] +
        (audio.samples[high] - audio.samples[low]) * (at - low);
  }
  final asr = Stopwatch()..start();
  final transcript = await engine.transcribe(resampled);
  asr.stop();
  final result = {
    'scope': 'macOS host smoke only; NOT iOS/Android acceptance',
    'host': Platform.operatingSystemVersion,
    'loadMs': load.elapsedMilliseconds,
    'extractionMs': extraction.elapsedMilliseconds,
    'synthesisMs': synthesis.elapsedMilliseconds,
    'asrMs': asr.elapsedMilliseconds,
    'audioSamples': audio.samples.length,
    'audioSampleRate': audio.sampleRate,
    'rssBytes': ProcessInfo.currentRss,
    'peakRssBytes': ProcessInfo.maxRss,
    'syntheticTranscript': transcript,
    'proposedValues': encodeAnswers(patch.values),
    'unresolved': patch.unresolved,
    'confidence': output['confidence'],
  };
  File('../../docs/evidence/native-host-smoke.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  await engine.unload();
  exit(0);
}
