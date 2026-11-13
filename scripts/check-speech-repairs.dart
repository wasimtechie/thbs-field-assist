import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:field_voice/moonshine.dart';
import '../apps/mobile/lib/core/contracts.dart';
import '../apps/mobile/lib/features/closure/compact_narrative.dart';
import '../apps/mobile/lib/features/voice/streaming_capture.dart';

/// Offline synthetic replay; never reads account files or modifies reports.
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent.path;
  final form = FormDefinition.fromJson(
    jsonDecode(
          File('$root/fixtures/templates/closure-mvp.json').readAsStringSync(),
        )
        as Json,
  );
  final frozen =
      jsonDecode(
            File(
              '$root/fixtures/voice/benchmarks/phonon-vs-moonshine-20261025.json',
            ).readAsStringSync(),
          )
          as Json;
  final summary = <Json>[];
  for (final run in frozen['summaries'] as List) {
    if (run['model'] != 'moonshine' || run['paced'] == true) continue;
    var correct = 0, clarified = 0, absent = 0;
    for (final row in run['details'] as List) {
      final expected = row['expected'] as Json;
      if (!expected.containsKey('optical_rx_dbm')) continue;
      final facts = compactNarrativeFacts(form, row['transcript'] as String);
      final value = facts
          .where((f) => f['fieldId'] == 'optical_rx_dbm')
          .firstOrNull?['value'];
      if (expected['optical_rx_dbm'] == null) {
        if (value != null) throw StateError('Invented reading: ${row['id']}');
        absent++;
      } else if (value == expected['optical_rx_dbm']) {
        correct++;
      } else if (value == null && row['id'] == 'rx-08-v0') {
        clarified++;
      } else {
        throw StateError('Wrong reading candidate: ${row['id']} -> $value');
      }
    }
    summary.add({
      'platform': run['platform'],
      'frozenMoonshineTranscripts': true,
      'correctReadings': correct,
      'requiresClarification': clarified,
      'correctlyAbsentReadings': absent,
    });
  }
  final engine = MoonshineRecognizer();
  await engine.load(
    '$root/.local/model-assets/moonshine-small-streaming',
    libraryPath: '$root/.local/moonshine-runtime/mac/libmoonshine.dylib',
  );
  final cases =
      jsonDecode(
            File(
              '$root/.local/speech-repair-audio/index.json',
            ).readAsStringSync(),
          )
          as List;
  try {
    for (final row in cases) {
      final pcm = File(
        '$root/.local/speech-repair-audio/${row['file']}',
      ).readAsBytesSync();
      final turn = await engine.start();
      final turnEnd = Completer<bool>();
      Completer<void>? frame;
      final capture = StreamingCapture(
        turn: turn,
        silence: summarySpeechPause,
        noSpeech: additionalSpeechWait,
        onProgress: (_) {
          if (frame?.isCompleted == false) frame!.complete();
        },
        onEnd: (empty) {
          if (!turnEnd.isCompleted) turnEnd.complete(empty);
        },
        onError: (e) {
          if (frame?.isCompleted == false) frame!.completeError(e);
        },
      );
      for (var at = 0; at < pcm.length && !turnEnd.isCompleted; at += 5120) {
        final stop = (at + 5120).clamp(0, pcm.length);
        frame = Completer<void>();
        capture.add(Uint8List.sublistView(pcm, at, stop));
        if (stop - at >= 5120) {
          await frame!.future.timeout(const Duration(seconds: 20));
          await Future<void>.delayed(Duration.zero);
        }
      }
      final transcript = await capture.finish();
      final values = {
        for (final f in compactNarrativeFacts(form, transcript))
          f['fieldId']: f['value'],
      };
      final expected = row['expected'] as Json;
      final mismatches = expected.keys
          .where(
            (k) => expected[k] == 'present'
                ? values[k] == null
                : values[k] != expected[k],
          )
          .toList();
      summary.add({
        'id': row['id'],
        'synthetic': true,
        'nativeHostReplay': true,
        'transcript': transcript,
        'values': values,
        'mismatches': mismatches,
      });
      if (mismatches.isNotEmpty)
        throw StateError(
          'Native replay mismatch ${row['id']}: $mismatches; $transcript',
        );
    }
  } finally {
    await engine.unload();
    final output = File('$root/.local/speech-repair-native-results.json');
    output.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
    );
  }
  stdout.writeln(
    jsonEncode({
      'frozenTranscriptPlatforms': 2,
      'nativeSyntheticCases': cases.length,
      'passed': true,
    }),
  );
  exit(0); // The persistent native worker is isolated from the app process.
}
