import 'spoken_numbers.dart' show spokenNumber;

/// These words are interpreted only in an asset-reference question or an
/// explicit identifier. They are never rewritten in arbitrary engineer speech.
String? spokenAssetType(String text) {
  final word = text.toLowerCase().trim().replaceAll(RegExp(r'[.!?,]+$'), '');
  return const {
    'pole': 'POLE',
    'pol': 'POL',
    'paul': 'POLE',
    'paule': 'POLE',
    'chamber': 'CHAMBER',
    'chambe': 'CHAMBER',
    'chemba': 'CHAMBER',
    'cbt': 'CBT',
    'c b t': 'CBT',
    'csp': 'CSP',
    'c s p': 'CSP',
    'cabinet': 'CABINET',
    'cab': 'CAB',
    'ch': 'CH',
    'dp': 'DP',
  }[word];
}

/// Normalize explicit letter/number dictation, never a phonetic guess or an ID
/// copied from job context. An asset type alone ("pole") is not an identifier.
String? spokenAssetReference(String transcript, {bool allowHomophones = true}) {
  var text = transcript.trim().replaceAll(RegExp(r'[.!?,]+$'), '');
  final explicitContext = RegExp(
    r'^(?:the\s+)?(?:serving\s+)?asset\s+(?:reference|identifier|id|is|was)\b',
    caseSensitive: false,
  ).hasMatch(text);
  if (!allowHomophones &&
      !explicitContext &&
      RegExp(
        r'^(?:the\s+)?(?:paul|paule|chambe|chemba)\b',
        caseSensitive: false,
      ).hasMatch(text)) {
    return null;
  }
  text = text.replaceFirst(
    RegExp(
      r'^(?:(?:the |my )?(?:serving )?(?:asset\s+)?(?:reference|identifier|id)(?: is| was)?\s*[:=]?\s*|(?:the )?(?:serving )?asset (?:is|was)\s+|(?:it is|it was)\s+)',
      caseSensitive: false,
    ),
    '',
  );
  text = text.replaceFirstMapped(
    RegExp(
      r'^(?:the\s+)?(pole|pol|paul|paule|chamber|chambe|chemba|cbt|csp|cabinet|cab|ch|dp)\b\s*(?:(?:reference|identifier|number|id)\s*)?(?:(?:is|was)\s*)?',
      caseSensitive: false,
    ),
    (m) => '${spokenAssetType(m.group(1)!) ?? m.group(1)!} ',
  );
  for (final acronym in ['CBT', 'CSP', 'DP', 'CH', 'CAB', 'POL', 'SYN']) {
    text = text.replaceAll(
      RegExp('\\b${acronym.split('').join(r'[ .]*')}\\b', caseSensitive: false),
      acronym,
    );
  }
  text = text.replaceAll(
    RegExp(r'\b(?:dash|hyphen)\b', caseSensitive: false),
    '-',
  );
  final described = RegExp(
    r'^(POLE|POL|CHAMBER|CH|CBT|CSP|DP|CABINET|CAB)\s+((POLE|POL|CHAMBER|CH|CBT|CSP|DP|CABINET|CAB)[_-].+)$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (described != null) {
    String family(String value) => switch (value.toUpperCase()) {
      'POL' || 'POLE' => 'POLE',
      'CH' || 'CHAMBER' => 'CHAMBER',
      'CAB' || 'CABINET' => 'CABINET',
      _ => value.toUpperCase(),
    };
    if (family(described.group(1)!) != family(described.group(3)!)) return null;
    text = described.group(2)!;
  }
  final match = RegExp(
    r'^(CBT|CSP|DP|POLE|POL|CHAMBER|CH|CABINET|CAB)[ _-]*([a-z0-9 _-]+)$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) return null;
  var rest = match.group(2)!.trim();
  if (RegExp(
    r'\b(?:says|said|damaged|checked|repaired|replaced|near|was|were|has|had|not|unknown|unconfirmed|at|on)\b',
    caseSensitive: false,
  ).hasMatch(rest)) {
    return null;
  }
  // Read out "S Y N ten" and "SYN one zero" without inventing the suffix.
  final words = rest.split(RegExp(r'[ _-]+'));
  final digitsAt = words.indexWhere(
    (w) =>
        RegExp(r'^\d+$').hasMatch(w) || spokenNumber(w.toLowerCase()) != null,
  );
  if (digitsAt >= 0) {
    final numberWords = words.sublist(digitsAt);
    String? number;
    if (numberWords.every((w) => RegExp(r'^\d+$').hasMatch(w))) {
      // An identifier is not a measured quantity: keep explicit leading zeros.
      number = numberWords.join();
    } else if (numberWords.length > 1 &&
        numberWords.every((w) {
          final n = spokenNumber(w.toLowerCase());
          return n != null && n >= 0 && n <= 9;
        })) {
      number = numberWords
          .map((w) => spokenNumber(w.toLowerCase())!.toInt())
          .join();
    } else {
      final n = spokenNumber(numberWords.join(' ').toLowerCase());
      if (n != null && n >= 0 && n == n.toInt()) number = n.toInt().toString();
    }
    if (number != null) rest = [...words.take(digitsAt), number].join('-');
  }
  rest = rest.replaceAll(RegExp(r'[ _-]+'), '-').toUpperCase();
  if (!RegExp(r'\d').hasMatch(rest) ||
      rest.length > 100 ||
      !RegExp(r'^[A-Z0-9]+(?:-[A-Z0-9]+)*$').hasMatch(rest)) {
    return null;
  }
  return '${match.group(1)!.toUpperCase()}-$rest';
}
