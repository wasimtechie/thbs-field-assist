import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../../apps/mobile/lib/core/contracts.dart';
import '../../apps/mobile/lib/features/closure/compact_narrative.dart';
import '../../apps/mobile/lib/features/closure/closure_speech.dart';

const small = [
  'zero',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'seven',
  'eight',
  'nine',
  'ten',
  'eleven',
  'twelve',
  'thirteen',
  'fourteen',
  'fifteen',
  'sixteen',
  'seventeen',
  'eighteen',
  'nineteen',
];
const tens = [
  '',
  '',
  'twenty',
  'thirty',
  'forty',
  'fifty',
  'sixty',
  'seventy',
  'eighty',
  'ninety',
];
String number(String s) {
  final parts = s.split('.');
  final n = int.parse(parts.first);
  String integer(int x) => x < 20
      ? small[x]
      : x < 100
      ? '${tens[x ~/ 10]}${x % 10 == 0 ? '' : ' ${small[x % 10]}'}'
      : x < 1000
      ? '${small[x ~/ 100]} hundred${x % 100 == 0 ? '' : ' ${integer(x % 100)}'}'
      : x.toString().split('').map((d) => small[int.parse(d)]).join(' ');
  return integer(n) +
      (parts.length > 1
          ? ' point ${parts[1].split('').map((d) => small[int.parse(d)]).join(' ')}'
          : '');
}

/// Shared orthography normalisation; no hypothesis-specific corrections.
List<String> words(String text) {
  var t = text.toLowerCase().replaceAll('−', '-').replaceAll('’', "'");
  for (final a in [
    'ont',
    'cbt',
    'csp',
    'pon',
    'los',
    'fttp',
    'dbm',
    'db',
    'syn',
  ]) {
    t = t.replaceAll(RegExp('\\b${a.split('').join(r'[\s.]+')}\\b'), a);
  }
  t = t.replaceAllMapped(
    RegExp(r'(^|[\s(:;,])\-\s*(\d)'),
    (m) => '${m[1]}minus ${m[2]}',
  );
  t = t.replaceAllMapped(RegExp(r'\d+(?:\.\d+)?'), (m) => ' ${number(m[0]!)} ');
  t = t.replaceAll(RegExp(r'\bfibre\b'), 'fiber');
  return t
      .replaceAll(RegExp(r"[^a-z' ]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
}

int distance(List<String> ref, List<String> hyp) {
  var previous = List.generate(hyp.length + 1, (i) => i);
  for (var i = 0; i < ref.length; i++) {
    final next = [i + 1, ...List.filled(hyp.length, 0)];
    for (var j = 0; j < hyp.length; j++) {
      next[j + 1] = math.min(
        math.min(next[j] + 1, previous[j + 1] + 1),
        previous[j] + (ref[i] == hyp[j] ? 0 : 1),
      );
    }
    previous = next;
  }
  return previous.last;
}

double percentile(List<double> values, double p) {
  final sorted = [...values]..sort();
  final position = p * (sorted.length - 1);
  final lo = position.floor(), hi = position.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (position - lo);
}

/// Measures the literal numeric value/sign/unit independently of form-context
/// recognition. Conflicting readings fail; the scorer never supplies a sign.
List<num> transcriptReadings(String text) =>
    RegExp(
          r'(?:(minus|negative)\s*|([-−])\s*)?(\d+(?:\.\d+)?)\s*d[.\s]*b[.\s]*m\b',
          caseSensitive: false,
        )
        .allMatches(text)
        .map((m) {
          final sign = m[1] != null || m[2] != null ? -1 : 1;
          return sign * num.parse(m[3]!);
        })
        .toSet()
        .toList();

Map<String, dynamic> mapped(FormDefinition form, String text) {
  final facts = compactNarrativeFacts(form, text);
  final values = {for (final f in facts) f['fieldId'] as String: f['value']};
  if (values['serving_asset'] == null && text.isNotEmpty) {
    values['serving_asset'] = closureSpokenAnswer(
      form.fields.firstWhere((f) => f.id == 'serving_asset'),
      text,
    )?.toJson();
  }
  return {'values': values, 'facts': facts};
}

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.parent.path;
  final lab = '$root/.local/phonon-ab';
  final corpus =
      jsonDecode(File('$lab/run/cases.json').readAsStringSync()) as Map;
  final cases = {
    for (final r in corpus['records'] as List)
      r['id'] as String: Map<String, dynamic>.from(r as Map),
  };
  final form = FormDefinition.fromJson(
    jsonDecode(
          File('$root/fixtures/templates/closure-mvp.json').readAsStringSync(),
        )
        as Map<String, dynamic>,
  );
  final summaries = <Map<String, dynamic>>[];
  final all = <Map<String, dynamic>>[];
  final referenceFailures = <String>[];
  for (final entry in cases.entries) {
    final ref = mapped(form, entry.value['text'] as String)['values'] as Map;
    for (final e in (entry.value['expected'] as Map).entries) {
      if (e.value == 'present' ? ref[e.key] == null : ref[e.key] != e.value)
        referenceFailures.add('${entry.key}:${e.key}');
    }
  }
  final files =
      Directory('$lab/results')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final records = file
        .readAsLinesSync()
        .where((l) => l.startsWith('{'))
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
    final loaded = records.firstWhere((r) => r['event'] == 'loaded');
    final results = records.where((r) => r['event'] == 'result').toList();
    if (results.isEmpty) continue;
    final platform = file.uri.pathSegments.last.startsWith('ios-')
        ? 'iOS simulator, experimental Phonon CPU port'
        : 'Android ARM64 emulator';
    final model = loaded['model'];
    final unique = results.where((r) => r['run'] == 0).toList();
    var errors = 0,
        totalWords = 0,
        readings = 0,
        correctReadings = 0,
        correctTranscriptReadings = 0,
        absentReadings = 0,
        correctAbsent = 0,
        assets = 0,
        correctAssets = 0,
        terms = 0,
        correctTerms = 0,
        fieldChecks = 0,
        correctFields = 0;
    final details = <Map<String, dynamic>>[];
    for (final row in unique) {
      final c = cases[row['id']]!;
      final ref = words(c['text'] as String),
          hyp = words(row['transcript'] as String);
      final edits = distance(ref, hyp);
      errors += edits;
      totalWords += ref.length;
      final mapping = mapped(form, row['transcript'] as String);
      final values = mapping['values'] as Map;
      final expected = c['expected'] as Map;
      final literalReadings = transcriptReadings(row['transcript'] as String);
      final failures = <String>[];
      for (final e in expected.entries) {
        fieldChecks++;
        final equal = e.value == 'present'
            ? values[e.key] != null
            : values[e.key] == e.value;
        if (equal)
          correctFields++;
        else
          failures.add(e.key as String);
      }
      if (expected.containsKey('optical_rx_dbm')) {
        if (expected['optical_rx_dbm'] is num) {
          readings++;
          if (literalReadings.length == 1 &&
              literalReadings.single == expected['optical_rx_dbm'])
            correctTranscriptReadings++;
          final fact = (mapping['facts'] as List)
              .where((f) => f['fieldId'] == 'optical_rx_dbm')
              .firstOrNull;
          if (values['optical_rx_dbm'] == expected['optical_rx_dbm'] &&
              fact?['requiresConfirmation'] != true)
            correctReadings++;
        } else {
          absentReadings++;
          if (values['optical_rx_dbm'] == null) correctAbsent++;
        }
      }
      if (expected.containsKey('serving_asset')) {
        assets++;
        if (values['serving_asset'] == expected['serving_asset'])
          correctAssets++;
      }
      final expectedTerms = [
        'ont',
        'cbt',
        'csp',
        'pon',
        'los',
        'fttp',
        'dbm',
      ].where(ref.contains).toList();
      terms += expectedTerms.length;
      correctTerms += expectedTerms.where(hyp.contains).length;
      details.add({
        'id': row['id'],
        'category': c['category'],
        'reference': c['text'],
        'transcript': row['transcript'],
        'normalisedWordEdits': edits,
        'referenceWords': ref.length,
        'literalDbmReadings': literalReadings,
        'values': values,
        'expected': expected,
        'fieldMismatches': failures,
        'requiresReadingConfirmation': (mapping['facts'] as List).any(
          (f) =>
              f['fieldId'] == 'optical_rx_dbm' &&
              f['requiresConfirmation'] == true,
        ),
        'missingTerms': expectedTerms.where((t) => !hyp.contains(t)).toList(),
      });
    }
    final times = results.map((r) => (r['wallMs'] as num).toDouble()).toList();
    final paced = results.first['paced'] == true;
    final delay = results
        .map((r) => (r['controlledReplyDelayMs'] as num).toDouble())
        .toList();
    final peakRss =
        results
            .map((r) => (r['peakRssNativeUnits'] as num).toInt())
            .reduce(math.max) *
        (platform.startsWith('Android') ? 1024 : 1);
    final repeated = results.where((r) => r['run'] != 0).toList();
    final firstTranscripts = {for (final r in unique) r['id']: r['transcript']};
    final noise = unique.where((r) => r['id'] == 'noise-only').toList();
    final summary = <String, dynamic>{
      'platform': platform,
      'file': file.uri.pathSegments.last,
      'model': model,
      'paced': paced,
      'uniqueCases': unique.length,
      'timedRecognitions': results.length,
      'loadMs': loaded['loadMs'],
      'normalisedWerPercent': 100 * errors / math.max(1, totalWords),
      'wordEdits': errors,
      'referenceWords': totalWords,
      'exactReadingInTranscript': {
        'correct': correctTranscriptReadings,
        'total': readings,
      },
      'exactSignedReadingAndUnitInForm': {
        'correct': correctReadings,
        'total': readings,
      },
      'noFabricatedReading': {
        'correct': correctAbsent,
        'total': absentReadings,
      },
      'exactAssetReference': {'correct': correctAssets, 'total': assets},
      'engineeringTermRecall': {'correct': correctTerms, 'total': terms},
      'expectedFormFields': {'correct': correctFields, 'total': fieldChecks},
      'emptyNoiseControl': {
        'correct': noise
            .where((r) => (r['transcript'] as String).trim().isEmpty)
            .length,
        'total': noise.length,
      },
      'repeatTranscriptChanges': {
        'changed': repeated
            .where((r) => r['transcript'] != firstTranscripts[r['id']])
            .length,
        'total': repeated.length,
      },
      'processPeakRssBytes': peakRss,
      'computeP50Ms': paced ? null : percentile(times, .5),
      'computeP95Ms': paced ? null : percentile(times, .95),
      'controlledReplyDelayP50Ms': paced ? percentile(delay, .5) : null,
      'controlledReplyDelayP95Ms': paced ? percentile(delay, .95) : null,
      'details': details,
    };
    summaries.add(summary);
    all.addAll(results.map((r) => {...r, 'platform': platform}));
    stdout.writeln(jsonEncode({...summary}..remove('details')));
  }
  final report = {
    'date': '2026-10-25',
    'synthetic': true,
    'physicalPhoneTested': false,
    'sourceCorpusCases': cases.length,
    'referenceParserMismatches': referenceFailures,
    'normalisation':
        'Case/punctuation, spelled acronyms, fibre/fiber, numerical digits expanded to spoken English. No model-specific correction. WER includes style differences such as spoken dash/one-zero vs hyphenated asset IDs. Critical field metrics are reported separately.',
    'mappingScope':
        'Existing compact parser plus spoken-asset normalizer, before form validation and engineer confirmation. Needle3, extraction latency and full bot conversation are excluded.',
    'memoryScope':
        'Process peak RSS includes the runner, native runtime, weights and scratch buffers; not Flutter, TTS, extraction or a phone RAM requirement.',
    'latencyScope':
        'Bulk is warm complete-audio compute. Paced uses fixture-known endpoints with the same pause allowance (1800 ms S1, 450 ms focused); excludes microphone, natural VAD, extraction, TTS and playback. Simulator results are not physical-phone timings.',
    'iosLimitation':
        'EXPERIMENTAL simulator-only CPU port of published macOS ARM64 kernels, unchanged model weights. Not the Phonon-2 CoreML model and not a supported physical-iPhone build.',
    'summaries': summaries,
    'timings': all,
  };
  File(args.firstOrNull ?? '$lab/report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  if (referenceFailures.isNotEmpty)
    stderr.writeln('REFERENCE_PARSER_GAPS: ${referenceFailures.join(', ')}');
}
