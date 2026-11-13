import '../../core/contracts.dart';
import 'spoken_numbers.dart';

bool isCompletionQuestion(FieldDefinition field) =>
    field.kind == FieldKind.singleSelect &&
    field.options.any((o) => o.id == 'completed') &&
    field.options.any((o) => o.id == 'partial') &&
    field.options.any(
      (o) => ['unable', 'blocked', 'not_completed'].contains(o.id),
    );

String voiceChoiceLabel(FieldDefinition field, Choice choice) {
  if (!isCompletionQuestion(field)) return choice.label;
  return switch (choice.id) {
    'completed' => 'Fully completed',
    'partial' => 'Partially completed',
    'blocked' => 'Not completed · blocked',
    'unable' || 'not_completed' => 'Not completed',
    _ => choice.label,
  };
}

String spokenQuestion(FieldDefinition field) {
  if (isCompletionQuestion(field)) {
    return 'Have you completed the work fully, partially, or not completed it?';
  }
  final prompt = field.question.isEmpty
      ? 'What is the ${field.label.toLowerCase()}?'
      : field.question;
  if (field.kind == FieldKind.singleSelect) {
    return '$prompt ${field.options.map((o) => o.label).join(', ')}.';
  }
  if (field.kind == FieldKind.boolean) return '$prompt Say yes or no.';
  return prompt;
}

/// Only explicit answers to the active question bypass model extraction. Values
/// still pass the normal type/constraint/merge rules and durable save callback.
Answer? directSpokenAnswer(FieldDefinition field, String transcript) {
  final numeric = directNumericAnswer(field, transcript);
  if (numeric != null) return numeric;
  final text = transcript.toLowerCase().replaceAll(RegExp(r'[.!?]'), '').trim();
  if (field.kind == FieldKind.singleSelect) {
    return spokenChoiceAnswer(field, transcript);
  }
  if (field.kind == FieldKind.boolean) {
    final booleanText = text
        .replaceAll(RegExp(r'[,;:"“”]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (['yes', 'yes it is', 'yes i did'].contains(booleanText)) {
      return const BoolAnswer(true);
    }
    if (['no', 'no it is not', 'no i did not'].contains(booleanText)) {
      return const BoolAnswer(false);
    }
  }
  // Dictation to a specific text question is saved verbatim, rather than asking
  // a model to invent a summary. Commands and uncertain answers need extraction.
  if ([FieldKind.shortText, FieldKind.longText].contains(field.kind) &&
      text.isNotEmpty &&
      !RegExp(
        r"\b(clear|remove|delete|change|correction|actually|ignore|submit|pause|stop|skip|don.t know|not sure)\b",
      ).hasMatch(text)) {
    return TextAnswer(transcript.trim());
  }
  return null;
}

String _choiceText(String text) => text
    .toLowerCase()
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'[^a-z0-9\s\x27]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Match a whole, explicit response in the active field's vocabulary. Sentence
/// frames are removed, never negation or qualifications. Substring/fuzzy matches
/// could silently turn "not passed" or two alternatives into a positive result.
Answer? spokenChoiceAnswer(FieldDefinition field, String transcript) {
  var text = _choiceText(transcript);
  text = text.replaceFirst(RegExp(r'^(?:yes|okay|ok)\s+'), '');
  text = text.replaceFirst(
    RegExp(
      r'^(?:(?:please )?(?:select|choose|pick)|(?:the |my )?answer is)\s+',
    ),
    '',
  );
  final ordinal = RegExp(
    r'^(?:the )?(?:(first|second|third|fourth|fifth|sixth|seventh)(?: option| one)?|option (one|two|three|four|five|six|seven|[1-7]))$',
  ).firstMatch(text);
  if (ordinal != null) {
    final value = ordinal.group(1) ?? ordinal.group(2)!;
    const ordinals = [
      'first',
      'second',
      'third',
      'fourth',
      'fifth',
      'sixth',
      'seventh',
    ];
    const numbers = ['one', 'two', 'three', 'four', 'five', 'six', 'seven'];
    final index = ordinals.contains(value)
        ? ordinals.indexOf(value)
        : numbers.contains(value)
        ? numbers.indexOf(value)
        : int.parse(value) - 1;
    return index < field.options.length
        ? TextAnswer(field.options[index].id)
        : null;
  }
  final candidates = <String>{text};
  text = text
      .replaceFirst(
        RegExp(r'^(?:(?:the |this )?(?:build )?stage) (?:is |was |has been )?'),
        'stage ',
      )
      .replaceFirst(RegExp(r'^(?:the )?network (?:is |was )'), 'network ');
  text = text
      .replaceFirst(
        RegExp(
          r"^(?:(?:the |this )?(?:work|job|installation|visit|outcome|result)(?: is| was| has been)?|(?:the )?(?:(?:service|connectivity|operational|activation|optical) )?test(?: is| was| has been| has)?|it is|it was|it's|it has been|it has|it|i have|i've|i am|i'm|i|we have|we've|we are|we're|we)\s+",
        ),
        '',
      )
      .replaceFirst(
        RegExp(
          r'\s+(?:(?:all )?(?:the |this )?(?:work|job|installation|visit)|it)$',
        ),
        '',
      );
  candidates.add(text);
  const aliases = <String, List<String>>{
    'completed': [
      'complete',
      'fully',
      'fully completed',
      'fully complete',
      'completed fully',
      'finished',
      'all done',
      'done',
      'fully done',
      'work completed',
    ],
    'partial': [
      'partially',
      'partially completed',
      'partially complete',
      'partly completed',
      'partly done',
      'completed partially',
      'partial installation',
    ],
    'blocked': ['blocked visit', 'not completed blocked'],
    'hold': ['on hold'],
    'referred': ['referral', 'referral required'],
    'stage_completed': [
      'stage complete',
      'stage completed',
      'this build stage completed',
    ],
    'network_ready': ['network ready', 'network ready reported'],
    // A bounded homophone in a field which actually offers a passing result.
    // Whole-response matching below still rejects "not past", alternatives
    // and references to a test in the past.
    'passed': ['pass', 'a pass', 'past', 'a past', 'successful'],
    'failed': ['fail', 'a fail'],
    'not_tested': ['not tested', 'not performed'],
  };
  const incomplete = [
    'not completed',
    'not complete',
    'not done',
    'not yet',
    'unable',
    'unable to complete',
    'have not completed',
    "haven't completed",
    'could not complete',
    "couldn't complete",
    'did not complete',
  ];
  final matches = <String>{};
  for (final choice in field.options) {
    final vocabulary = {
      _choiceText(choice.label),
      _choiceText(choice.id),
      _choiceText(voiceChoiceLabel(field, choice)),
      ...?aliases[choice.id],
      if (['unable', 'not_completed'].contains(choice.id)) ...incomplete,
    };
    if (candidates.any(vocabulary.contains)) matches.add(choice.id);
  }
  return matches.length == 1 ? TextAnswer(matches.single) : null;
}

class TurnEndpoint {
  TurnEndpoint({
    this.silence = const Duration(milliseconds: 1300),
    this.noSpeech = const Duration(seconds: 8),
    this.adaptiveNoise = false,
  });
  final Duration silence, noSpeech;
  final bool adaptiveNoise;
  final _ambient = <double>[];
  bool _calibrated = false;
  double _noiseFloor = .001;
  Duration _previous = Duration.zero,
      _voiced = Duration.zero,
      _burst = Duration.zero,
      _lastVoice = Duration.zero;
  bool get heardSpeech =>
      _voiced >= Duration(milliseconds: adaptiveNoise ? 80 : 180);
  bool observe(double level, Duration elapsed) {
    final delta = elapsed - _previous;
    _previous = elapsed;
    if (adaptiveNoise && !_calibrated) {
      // Keep all PCM, including speech during calibration. A clear opening word
      // freezes the floor immediately; it must not become the noise baseline.
      if (level >= .03) {
        if (_ambient.length >= 4) {
          final sorted = [..._ambient]..sort();
          _noiseFloor = sorted[sorted.length ~/ 5].clamp(.0005, .025);
        }
        _calibrated = true;
      } else {
        _ambient.add(level);
        if (elapsed >= const Duration(milliseconds: 400) &&
            _ambient.length >= 8) {
          final sorted = [..._ambient]..sort();
          _noiseFloor = sorted[sorted.length ~/ 5].clamp(.0005, .025);
          final stationary = sorted.last <= _noiseFloor * 1.35;
          if (stationary && _noiseFloor >= .0025) {
            _voiced = Duration.zero;
            _burst = Duration.zero;
          }
          _calibrated = true;
        }
      }
    }
    final minimum = adaptiveNoise ? .0025 : .004;
    final relative = _noiseFloor * (heardSpeech ? 1.3 : 1.8);
    final threshold = adaptiveNoise && _calibrated && relative > minimum
        ? relative
        : minimum;
    // The release floor is independent of speech peaks, preserving quiet words
    // after a louder syllable. Steady ambient noise no longer holds a turn open.
    if (level >= threshold) {
      _burst += Duration(milliseconds: delta.inMilliseconds.clamp(0, 200));
      _voiced = _burst > _voiced ? _burst : _voiced;
      _lastVoice = elapsed;
    } else {
      _burst = Duration.zero;
    }
    return heardSpeech ? elapsed - _lastVoice >= silence : elapsed >= noSpeech;
  }
}
