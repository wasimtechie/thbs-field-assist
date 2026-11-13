import '../../core/contracts.dart';
import '../voice/spoken_numbers.dart';
import '../voice/speech_repair.dart';

class OpticalNumber {
  const OpticalNumber(this.value, {this.needsConfirmation = false});
  final num value;
  final bool needsConfirmation;
}

// ASR full stops/commas after a spoken sign or "point" are pauses, provided
// the next token is another explicit part of that same number. Never change
// digits, remove an extra number, or supply a missing sign.
String _numberPauses(String text) => text.replaceAllMapped(
  RegExp(
    r'\b(minus|negative|point)[.,:]\s*(?=(?:[−+-]?\d|zero\b|oh\b|one\b|two\b|three\b|four\b|five\b|six\b|seven\b|eight\b|nine\b|ten\b|eleven\b|twelve\b|thirteen\b|fourteen\b|fifteen\b|sixteen\b|seventeen\b|eighteen\b|nineteen\b|twenty\b|thirty\b|forty\b|fifty\b|sixty\b|seventy\b|eighty\b|ninety\b))',
    caseSensitive: false,
  ),
  (match) => '${match[1]} ',
);

/// Numeric normalization only. Two adjacent number parts remain a proposal
/// until the engineer confirms them; a model never supplies the measurement.
OpticalNumber? opticalNumber(String raw) {
  var text = _numberPauses(raw).toLowerCase().trim().replaceAll('−', '-');
  text = text.replaceFirstMapped(
    RegExp(r'^(minus|negative)(?=\d)'),
    (m) => '${m[1]} ',
  );
  if (RegExp(r'^(?:minus|negative)\s*-').hasMatch(text)) return null;
  final exact = spokenNumber(text);
  if (exact != null) return OpticalNumber(exact);
  final split = RegExp(
    r'^(?:(minus|negative)\s+)?(-?\d+)\s+0\.(\d+)$',
  ).firstMatch(text);
  if (split == null) return null;
  final whole = int.parse(split[2]!);
  if (whole == 0) return null;
  final negative = split[1] != null || whole < 0;
  final value = num.parse('${whole.abs()}.${split[3]}');
  return OpticalNumber(negative ? -value : value, needsConfirmation: true);
}

final _numberStart = RegExp(
  r'(?<![a-z0-9.])(?:[−+-]?\d|minus(?=\d|\b)|negative(?=\d|\b)|zero\b|oh\b|one\b|two\b|three\b|four\b|five\b|six\b|seven\b|eight\b|nine\b|ten\b|eleven\b|twelve\b|thirteen\b|fourteen\b|fifteen\b|sixteen\b|seventeen\b|eighteen\b|nineteen\b|twenty\b|thirty\b|forty\b|fifty\b|sixty\b|seventy\b|eighty\b|ninety\b)',
  caseSensitive: false,
);
final _opticalUnit = RegExp(
  r'(?<![a-z])(?:d[ .]*b(?:[ .]*m)?|decibels)\b',
  caseSensitive: false,
);

Json withOpticalUnit(Json fact, String? unit) {
  if (unit == null ||
      unit.replaceAll(RegExp(r'[ .]'), '').toLowerCase() == 'dbm') {
    return fact;
  }
  return {
    ...fact,
    'requiresConfirmation': true,
    'unitNeedsConfirmation': true,
    'ambiguityReason':
        'Speech contained dB rather than dBm. Confirm the measured optical receive reading and its unit.',
  };
}

final _readingLabel = RegExp(
  r'\b(?:optical\s+(?:(?:receive|received)(?:\s+(?:power|measurements?|readings?|level))?|rx|readings?|level|power)|received\s+(?:power|measurements?)|receive\s+(?:power|measurements?|readings?)|rx|readings?)\b',
  caseSensitive: false,
);
final _readingBoundary = RegExp(
  r'[,;!?\n]|(?<!\d)\.(?!\s*(?:is|was|has|have|are|were)\b)(?=\s|$)|\.(?!\s*(?:is|was|has|have|are|were)\b)(?=\s+[a-z])|\b(?:and|but)\b|\b(?:the\s+)?(?:service|connectivity|activation|operational)\s+(?:tests?|checks?)\b',
  caseSensitive: false,
);
final _notReceive = RegExp(
  r'\b(?:transmit|tx|launch|target|expected|threshold|limit|range|noise|splice|loss)\b',
  caseSensitive: false,
);
final _uncertainReading = RegExp(
  r"\b(?:maybe|might|not sure|unconfirmed|think|possibly|not|never|didn't|haven't|no)\b",
  caseSensitive: false,
);

/// Parse all measurements in a receive-reading clause before choosing a value.
/// An explicit repair retracts its old value; unrelated competing values do not.
List<Json> opticalNarrativeFacts(String raw, {bool allowUnitless = false}) {
  final repaired = interpretSpokenRepairs(raw);
  final interpretation = InterpretedSpeech(
    raw,
    _numberPauses(repaired.text),
    repaired.repairs,
  );
  final text = interpretation.text;
  final labels = _readingLabel.allMatches(text).toList();
  final facts = <Json>[];
  void unclear(String span, String reason) => facts.add({
    'fieldId': 'optical_rx_dbm',
    'value': null,
    'sourceSpan': span,
    'sourceType': 'speech',
    'verificationStatus': 'candidate',
    'ambiguityReason': reason,
  });
  for (var i = 0; i < labels.length; i++) {
    final label = labels[i];
    final rest = text.substring(
      label.end,
      i + 1 < labels.length ? labels[i + 1].start : text.length,
    );
    final stop = _readingBoundary.firstMatch(rest)?.start ?? rest.length;
    final tail = rest.substring(0, stop);
    final number = _numberStart.firstMatch(tail);
    if (number == null) continue;
    final before = text.substring(0, label.start).split(_readingBoundary).last;
    final context =
        '$before ${label.group(0)} ${tail.substring(0, number.start)}';
    if (_notReceive.hasMatch(context)) continue;
    final source = text.substring(label.start, label.end + stop).trim();
    if (_uncertainReading.hasMatch(context)) {
      unclear(source, 'The receive measurement was uncertain or negated.');
      continue;
    }
    final units = _opticalUnit.allMatches(tail).toList();
    if (units.isEmpty) {
      if (!allowUnitless) continue;
      final parsed = opticalNumber(
        tail
            .substring(number.start)
            .trim()
            .replaceFirst(RegExp(r'[.!?]+$'), ''),
      );
      if (parsed == null) {
        unclear(
          source,
          'More than one number or an unclear measurement was spoken.',
        );
      } else {
        facts.add({
          ...opticalFact(parsed, source),
          'unitSource': 'field_definition',
        });
      }
      continue;
    }
    var from = 0;
    for (final unit in units) {
      final unitText = unit.group(0)!;
      if (unitText.replaceAll(RegExp(r'[ .]'), '').toLowerCase() != 'dbm' &&
          !RegExp(
            r'\b(?:optical|received\s+power|rx)\b',
            caseSensitive: false,
          ).hasMatch(context)) {
        from = unit.end;
        continue;
      }
      final segment = tail.substring(from, unit.start);
      final at = _numberStart.firstMatch(segment);
      if (at != null) {
        final qualifier = segment.substring(0, at.start);
        final parsed = opticalNumber(segment.substring(at.start).trim());
        if (_notReceive.hasMatch(qualifier)) {
          // A target/transmit value in the same sentence is not receive power.
        } else if (_uncertainReading.hasMatch(qualifier) || parsed == null) {
          unclear(
            source,
            'The receive measurement was unclear or contained alternatives.',
          );
        } else {
          facts.add(withOpticalUnit(opticalFact(parsed, source), unitText));
        }
      }
      from = unit.end;
    }
    // An alternative can omit its repeated unit: "-18.2 dBm or -19.1".
    final suffix = tail.substring(units.last.end);
    if (_numberStart.hasMatch(suffix)) {
      unclear(
        source,
        'Another number followed the reading without an explicit correction.',
      );
    }
  }
  if (facts.any((f) => f['value'] == null) ||
      facts.map((f) => f['value']).toSet().length > 1) {
    return [
      interpretation.ground({
        'fieldId': 'optical_rx_dbm',
        'value': null,
        'sourceSpan': text,
        'sourceType': 'speech',
        'verificationStatus': 'candidate',
        'ambiguityReason':
            'Uncertain or conflicting receive readings; ask for the measured value.',
      }),
    ];
  }
  return facts.map(interpretation.ground).toList();
}

Json opticalFact(OpticalNumber parsed, String source) => {
  'fieldId': 'optical_rx_dbm',
  'value': parsed.value,
  'sourceSpan': source,
  'sourceType': 'speech',
  'verificationStatus': 'candidate',
  'confidence': null,
  if (parsed.needsConfirmation) ...{
    'requiresConfirmation': true,
    'ambiguityReason':
        'Speech recognition separated the whole and decimal parts. Confirm the proposed reading.',
  },
};

Json? focusedOpticalFact(String raw) {
  final labelled = opticalNarrativeFacts(raw, allowUnitless: true);
  if (labelled.isNotEmpty) return labelled.first;
  final interpretation = interpretSpokenRepairs(raw, numericAnswer: true);
  final text = interpretation.text;
  final unit = RegExp(
    r'(?:d[ .]*b(?:[ .]*m)?|decibels)[.!?]*$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  final value = text
      .trim()
      .replaceFirst(
        RegExp(
          r'\s*(?:d[ .]*b(?:[ .]*m)?|decibels)[.!?]*$',
          caseSensitive: false,
        ),
        '',
      )
      .replaceFirst(
        RegExp(r"^(?:it is|it was|it's)\s+", caseSensitive: false),
        '',
      )
      .replaceFirst(RegExp(r'[.!?]+$'), '');
  final parsed = opticalNumber(value);
  return parsed == null
      ? null
      : interpretation.ground(
          withOpticalUnit(
            opticalFact(parsed, text),
            unit?.group(0)?.replaceAll(RegExp(r'[.!?]+$'), ''),
          ),
        );
}
