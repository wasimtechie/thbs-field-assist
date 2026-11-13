import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:field_voice/moonshine.dart';
import '../apps/mobile/lib/core/contracts.dart';
import '../apps/mobile/lib/features/closure/structured_visit_extraction.dart';
import '../apps/mobile/lib/features/closure/closure_speech.dart';
import '../apps/mobile/lib/features/voice/streaming_capture.dart';

class DiagnosticExtractor implements FieldExtractor {
  DiagnosticExtractor(this.delegate);
  final FieldExtractor delegate;
  @override
  Future<Json> extract(String text, List<Json> tools, String context) async {
    final watch = Stopwatch()..start();
    final result = await delegate.extract(text, tools, context);
    stdout.writeln(
      'NEEDLE_HOST: ${jsonEncode({'ms': watch.elapsedMilliseconds, 'result': result})}',
    );
    return result;
  }
}

/// Synthetic paced PCM through the production streaming and extraction adapters.
/// No microphone, user account, report database, submission or server is used.
Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final records =
      jsonDecode(
            File(
              '$root/.local/moonshine-tests/audio/index.json',
            ).readAsStringSync(),
          )
          as List;
  final form = FormDefinition.fromJson(
    jsonDecode(
          File('$root/fixtures/templates/closure-mvp.json').readAsStringSync(),
        )
        as Json,
  );
  final voice = FieldVoice();
  await voice.load('$root/.local/model-assets');
  await voice.smokeTest();
  final extraction = StructuredVisitExtractor(
    DiagnosticExtractor(voice.summaryExtractor),
  );
  if (args.firstOrNull == '--text') {
    for (final text in args.skip(1)) {
      final facts = await extraction.extract(form, text, current: () => true);
      stdout.writeln('TEXT_FACTS: ${jsonEncode(facts)}');
    }
    await voice.unload();
    exit(0);
  }
  final engine = MoonshineRecognizer();
  await engine.load(
    '$root/.local/model-assets/moonshine-small-streaming',
    libraryPath: '$root/.local/moonshine-runtime/mac/libmoonshine.dylib',
  );
  final results = <Json>[];
  var failures = 0;
  for (final raw in records) {
    final row = raw as Json;
    if (args.isNotEmpty && !args.contains(row['id'])) continue;
    final bytes = File(
      '$root/.local/moonshine-tests/audio/${row['file']}',
    ).readAsBytesSync();
    final speechTurn = await engine.start();
    final ended = Completer<bool>();
    final watch = Stopwatch()..start();
    var delivered = 0, partials = 0;
    final inference = <int>[];
    final pump = StreamingCapture(
      turn: speechTurn,
      silence: row['narrative'] == true ? summarySpeechPause : answerSpeechPause,
      noSpeech: const Duration(seconds: 8),
      onProgress: (progress) {
        if (progress.text.isNotEmpty) partials++;
        inference.add(progress.inferenceMilliseconds);
      },
      onEnd: (empty) {
        if (!ended.isCompleted) ended.complete(empty);
      },
      onError: (error) {
        if (!ended.isCompleted) ended.completeError(error);
      },
    );
    for (var at = 0; at < bytes.length && !ended.isCompleted; at += 640) {
      final end = (at + 640).clamp(0, bytes.length);
      pump.add(Uint8List.sublistView(bytes, at, end));
      delivered = end ~/ 2;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final endpointFired = ended.isCompleted;
    final empty = endpointFired ? await ended.future : false;
    final text = await pump.finish();
    final finalMs = watch.elapsedMilliseconds;
    final facts = await extraction.extract(form, text, current: () => true);
    final values = {
      for (final fact in facts) fact['fieldId'] as String: fact['value'],
    };
    if (row['id'] == 'asset') {
      values['serving_asset'] = closureSpokenAnswer(
        form.fields.firstWhere((f) => f.id == 'serving_asset'),
        text,
      )?.toJson();
    }
    final expected = row['expected'] as Json;
    final mismatches = <String>[];
    for (final entry in expected.entries) {
      final actual = values[entry.key];
      if (entry.value == 'present' ? actual == null : actual != entry.value)
        mismatches.add(entry.key);
    }
    if (!endpointFired) mismatches.add('endpoint');
    if (row['id'] == 'noise-only' && (!empty || text.isNotEmpty))
      mismatches.add('noise-transcript');
    if (!empty && delivered < (row['speechEndSamples'] as int) - 3200)
      mismatches.add('cut-off-speech');
    inference.sort();
    final result = <String, dynamic>{
      'id': row['id'],
      'transcript': text,
      'values': values,
      'endpointFired': endpointFired,
      'noSpeech': empty,
      'processedAudioSeconds': delivered / 16000,
      'finalizedWallMilliseconds': finalMs,
      'extractionMilliseconds': watch.elapsedMilliseconds - finalMs,
      'replyReadyWallMilliseconds': watch.elapsedMilliseconds,
      'nonemptyPartialUpdates': partials,
      'nativePassP95Milliseconds': inference.isEmpty
          ? null
          : inference[((inference.length - 1) * .95).floor()],
      'mismatches': mismatches,
      'passed': mismatches.isEmpty,
    };
    if (mismatches.isNotEmpty) failures++;
    results.add(result);
    stdout.writeln('STREAMING_NATIVE: ${jsonEncode(result)}');
    File('$root/.local/moonshine-tests/results.json').writeAsStringSync(
      jsonEncode({
        'scope':
            'Synthetic paced PCM on this Mac; real Moonshine Small Streaming, embedded Silero, and local structured extractor. Not a physical-phone accuracy or latency guarantee.',
        'records': results,
        'failed': failures,
      }),
    );
  }
  await engine.unload();
  await voice.unload();
  exit(failures == 0 ? 0 : 1);
}
