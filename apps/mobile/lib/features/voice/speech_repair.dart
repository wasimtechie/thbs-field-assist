import 'spoken_numbers.dart' show spokenNumber;

/// Resolve explicit restarts, not guesses about what the speaker intended.
/// Retain the raw transcript and every discarded/replacement span for review.
class InterpretedSpeech {
  const InterpretedSpeech(this.raw, this.text, this.repairs);
  final String raw, text;
  final List<Map<String, String>> repairs;
  bool get changed => text != raw.trim();

  Map<String, dynamic> ground(Map<String, dynamic> fact) {
    if (!changed) return fact;
    final span = fact['sourceSpan'] as String? ?? text;
    return {
      ...fact,
      'sourceSpan': raw.contains(span) ? span : raw,
      'rawTranscript': raw,
      'interpretedSpan': fact['interpretedSpan'] ?? span,
      if (repairs.isNotEmpty) 'speechRepairs': repairs,
    };
  }
}

final _repairCue = RegExp(
  r'\b(?:(?:no[\s,!.]+){2,}(?:sorry\b)?|no[\s,!.]+sorry\b|sorry(?:[\s,!.]+i mean\b)?|i mean\b|correction\b|make that\b)[\s,:;.!?]*',
  caseSensitive: false,
);
final _topics = <String, RegExp>{
  'reading': RegExp(
    r'\b(?:the\s+)?(?:optical\s+(?:(?:receive|received)(?:\s+(?:power|measurements?|readings?|level))?|rx|readings?|level|power)|received\s+(?:power|measurement)|receive\s+(?:power|measurements?|readings?)|rx|readings?)\b',
    caseSensitive: false,
  ),
  'test': RegExp(
    r'\b(?:the\s+)?(?:service|connectivity|activation|operational)\s+(?:tests?|checks?)\b',
    caseSensitive: false,
  ),
  'outcome': RegExp(
    r'\b(?:the\s+)?(?:job|work|installation|visit)\s+(?:(?:is|was|has been)\s+)?(?:fully\s+)?(?:completed?|finished|done|partial\w*|blocked|on hold)\b',
    caseSensitive: false,
  ),
  'asset': RegExp(
    r'\b(?:the\s+)?(?:(?:serving\s+)?asset(?:\s+reference)?|(?:serving\s+)?(?:CBT|CSP|pole|chamber)\s+(?:reference|identifier))\b',
    caseSensitive: false,
  ),
  'personal': RegExp(
    r"\b(?:(?:hello|hi|hey)[,\s]+)?(?:(?:i['’]m|i am)\s+[a-z]+(?:\s+[a-z]+){0,2}\s+from\b|my name is\b|i (?:stay|live)\b)",
    caseSensitive: false,
  ),
};
final _boundary = RegExp(
  r'[,;!?\n]+\s*|(?<!\d)\.(?=\s|$)\s*|\.(?=\s+[A-Z])\s*',
);
final _numberStart = RegExp(
  r'(?<![a-z0-9.])(?:[−+-]?\d|minus\b|negative\b|zero\b|oh\b|one\b|two\b|three\b|four\b|five\b|six\b|seven\b|eight\b|nine\b|ten\b|eleven\b|twelve\b|thirteen\b|fourteen\b|fifteen\b|sixteen\b|seventeen\b|eighteen\b|nineteen\b|twenty\b|thirty\b|forty\b|fifty\b|sixty\b|seventy\b|eighty\b|ninety\b)',
  caseSensitive: false,
);
final _unit = RegExp(r'\s*d[.\s]*b(?:[.\s]*m)?\b', caseSensitive: false);

/// A pause after a correction cue or decimal prefix is not a finished answer.
bool hasPendingSpokenRepair(String text) => RegExp(
  r'\b(?:no[,\s]+no|sorry|i mean|correction|make that|minus|negative|point)[,.!?\s]*$',
  caseSensitive: false,
).hasMatch(text);

bool _bareNumber(String text) {
  final value = text
      .toLowerCase()
      .replaceAll('−', '-')
      .replaceFirst(RegExp(r"^(?:it (?:is|was)|it's)\s+"), '')
      .replaceFirst(_unit, '')
      .replaceAll(RegExp(r'[.!?,;]+$'), '')
      .trim();
  return spokenNumber(value) != null;
}

InterpretedSpeech interpretSpokenRepairs(
  String raw, {
  bool numericAnswer = false,
}) {
  final markers = _repairCue.allMatches(raw).toList();
  // Keep work bounded; a malformed/very long restart chain stays reviewable.
  if (markers.length > 24) return InterpretedSpeech(raw, raw.trim(), const []);
  final repairs = <Map<String, String>>[];
  var result = markers.isEmpty ? raw : raw.substring(0, markers.first.start);
  for (var i = 0; i < markers.length; i++) {
    final marker = markers[i];
    final after = raw.substring(
      marker.end,
      i + 1 < markers.length ? markers[i + 1].start : raw.length,
    );
    final end = _boundary.firstMatch(after)?.end ?? after.length;
    final head = after.substring(0, end).trim();
    String? topic;
    for (final entry in _topics.entries) {
      if (entry.value.matchAsPrefix(head) != null) {
        topic = entry.key;
        break;
      }
    }
    final bare = topic == null && _bareNumber(head);
    if (bare) topic = 'reading';
    final previous = topic == null
        ? null
        : _topics[topic]!.allMatches(result).lastOrNull;
    if (previous == null &&
        bare &&
        numericAnswer &&
        _bareNumber(result.trim())) {
      repairs.add({
        'discarded': result.trim(),
        'cue': marker.group(0)!.trim(),
        'replacement': head,
      });
      result = after;
      continue;
    }
    if (previous == null || head.isEmpty) {
      result += '${marker.group(0)}$after';
      continue;
    }
    // Do not let a correction to transmit power retract a receive reading.
    final before = result.substring(0, previous.start).split(_boundary).last;
    if (topic == 'reading' &&
        RegExp(
          r'\b(?:transmit|tx|target|threshold|expected|loss|noise)\b',
          caseSensitive: false,
        ).hasMatch(before)) {
      result += '${marker.group(0)}$after';
      continue;
    }
    var start = previous.start;
    var oldEnd = _boundary.firstMatch(result.substring(previous.end));
    var stop = oldEnd == null ? result.length : previous.end + oldEnd.end;
    // Preserve a different field mentioned in the same sentence.
    for (final entry in _topics.entries.where((e) => e.key != topic)) {
      final next = entry.value.firstMatch(result.substring(previous.end));
      if (next != null && previous.end + next.start < stop) {
        stop = previous.end + next.start;
      }
    }
    var replacement = head;
    if (bare) {
      final tail = result.substring(previous.end, stop);
      final number = _numberStart.firstMatch(tail);
      if (number == null) {
        result += '${marker.group(0)}$after';
        continue;
      }
      start = previous.end + number.start;
      replacement = replacement.replaceFirst(
        RegExp(r"^(?:it (?:is|was)|it's)\s+", caseSensitive: false),
        '',
      );
      final inheritedUnit = _unit.firstMatch(tail)?.group(0)?.trim();
      if (!_unit.hasMatch(replacement) && inheritedUnit != null) {
        replacement =
            '${replacement.replaceFirst(RegExp(r'[.!?,;]+$'), '').trim()} $inheritedUnit.';
      }
    }
    final discarded = result.substring(start, stop).trim();
    repairs.add({
      'discarded': discarded,
      'cue': marker.group(0)!.trim(),
      'replacement': head,
    });
    result =
        '${result.substring(0, start)}$replacement ${result.substring(stop)} ${after.substring(end)}';
  }
  result = result.trim().replaceAll(RegExp(r'[ \t]+'), ' ');
  result = result.replaceFirst(
    RegExp(
      r"^(?:hello|hi|hey)[,.!\s]+(?=(?:i['’]m|i am|my name is)\b)",
      caseSensitive: false,
    ),
    '',
  );
  return InterpretedSpeech(raw, result.trim(), repairs);
}
