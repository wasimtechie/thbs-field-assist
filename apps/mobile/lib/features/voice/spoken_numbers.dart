import '../../core/contracts.dart';
import 'field_extraction.dart';

/// An estimate is a proposal, never a value to save without confirmation.
Answer? approximateNumericAnswer(FieldDefinition field, String transcript) {
  final text = transcript.toLowerCase().trim().replaceFirst(
    RegExp(
      r"^(?:it is|it's|the value is|the reading is|i installed|i replaced)\s+",
    ),
    '',
  );
  final match = RegExp(
    r'^(?:around|about|approximately|roughly)\s+(.+)$',
  ).firstMatch(text);
  return match == null ? null : directNumericAnswer(field, match.group(1)!);
}

/// Parse an explicit answer to the active numeric question. Ambiguous phrases,
/// negation and corrections fall back to extraction and the normal merge rules.
Answer? directNumericAnswer(FieldDefinition field, String transcript) {
  if (![
    FieldKind.integer,
    FieldKind.decimal,
    FieldKind.quantity,
  ].contains(field.kind)) {
    return null;
  }
  var text = transcript
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[.!?]+$'), '')
      .replaceAll(RegExp(r'(?<=[a-z])-(?=[a-z])'), ' ');
  text = text.replaceFirst(
    RegExp(
      r"^(?:it is|it's|the value is|the reading is|i installed|i replaced|installed|replaced)\s+",
    ),
    '',
  );
  String? unit;
  if (field.kind == FieldKind.quantity) {
    unit = explicitUnit(field, text, field.question);
    if (unit == null) return null;
    final aliases = voiceUnitAliases[unit] ?? [unit];
    text = text
        .replaceFirst(
          RegExp(
            '\\s*(?:${aliases.map(RegExp.escape).join('|')})\\s*\$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  } else if (RegExp(
    r'\bdbm\b',
    caseSensitive: false,
  ).hasMatch(field.question)) {
    text = text.replaceFirst(RegExp(r'\s+dbm$'), '');
  }
  final number = spokenNumber(text);
  if (number == null) return null;
  return unit == null ? NumberAnswer(number) : QuantityAnswer(number, unit);
}

num? spokenNumber(String text) {
  final literal = num.tryParse(text);
  if (literal != null) return literal.isFinite ? literal : null;
  var words = text.split(RegExp(r'\s+'));
  var sign = 1;
  if (words.firstOrNull == 'minus' || words.firstOrNull == 'negative') {
    sign = -1;
    words = words.sublist(1);
  }
  final signedLiteral = num.tryParse(words.join(' '));
  if (signedLiteral != null && signedLiteral.isFinite) {
    return sign * signedLiteral;
  }
  final point = words.indexOf('point');
  final whole = _integerWords(point < 0 ? words : words.sublist(0, point));
  if (whole == null) return null;
  if (point < 0) return sign * whole;
  final fraction = words.sublist(point + 1);
  if (fraction.isEmpty) return null;
  final digits = <int>[];
  for (final word in fraction) {
    final n = _small[word] ?? int.tryParse(word);
    if (n == null || n < 0 || n > 9) return null;
    digits.add(n);
  }
  return sign * num.parse('$whole.${digits.join()}');
}

const _small = {
  'zero': 0,
  'oh': 0,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
  'eleven': 11,
  'twelve': 12,
  'thirteen': 13,
  'fourteen': 14,
  'fifteen': 15,
  'sixteen': 16,
  'seventeen': 17,
  'eighteen': 18,
  'nineteen': 19,
};
const _tens = {
  'twenty': 20,
  'thirty': 30,
  'forty': 40,
  'fifty': 50,
  'sixty': 60,
  'seventy': 70,
  'eighty': 80,
  'ninety': 90,
};
int? _under100(List<String> words) {
  if (words.length == 1) return _small[words.single] ?? _tens[words.single];
  if (words.length == 2 &&
      _tens.containsKey(words[0]) &&
      (_small[words[1]] ?? 0) > 0 &&
      _small[words[1]]! < 10) {
    return _tens[words[0]]! + _small[words[1]]!;
  }
  return null;
}

int? _under1000(List<String> words) {
  if (words.length >= 2 &&
      words[1] == 'hundred' &&
      (_small[words[0]] ?? 0) > 0 &&
      _small[words[0]]! < 10) {
    var rest = words.sublist(2);
    if (rest.firstOrNull == 'and') rest = rest.sublist(1);
    final tail = rest.isEmpty ? 0 : _under100(rest);
    return tail == null ? null : _small[words[0]]! * 100 + tail;
  }
  return _under100(words);
}

int? _integerWords(List<String> words) {
  final thousand = words.indexOf('thousand');
  if (thousand < 0) return _under1000(words);
  final leading = _under1000(words.sublist(0, thousand));
  var rest = words.sublist(thousand + 1);
  if (rest.firstOrNull == 'and') rest = rest.sublist(1);
  final trailing = rest.isEmpty ? 0 : _under1000(rest);
  return leading == null || leading == 0 || trailing == null
      ? null
      : leading * 1000 + trailing;
}
