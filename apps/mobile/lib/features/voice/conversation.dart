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
  if (isCompletionQuestion(field)) {
    final completion = text
        .replaceAll('’', "'")
        .replaceFirst(
          RegExp(
            r"^(?:the (?:work|job|installation) is|it is|it's|i have|i've)\s+",
          ),
          '',
        )
        .replaceFirst(RegExp(r'\s+the (?:work|job|installation)$'), '');
    String? id;
    if (RegExp(
      r"^(?:(?:i have|i ve|i|it is|it s) )?(?:fully|fully completed|fully complete|completed fully|completed|complete|finished|all done)$",
    ).hasMatch(completion.replaceAll("'", ' '))) {
      id = 'completed';
    }
    if (RegExp(
      r"^(?:(?:i have|i ve|i|it is|it s) )?(?:partially|partial|partially completed|completed partially|partially complete|partly completed|partly done)$",
    ).hasMatch(completion.replaceAll("'", ' '))) {
      id = 'partial';
    }
    if ([
      'not completed',
      'not complete',
      'not done',
      'not yet',
      'unable',
      'unable to complete',
      'i have not completed',
      "i haven't completed",
      'i could not complete',
      "i couldn't complete",
      'i did not complete',
      'blocked',
    ].contains(completion)) {
      id = field.options
          .firstWhere(
            (o) => ['unable', 'blocked', 'not_completed'].contains(o.id),
          )
          .id;
    }
    if (id != null) return TextAnswer(id);
  }
  if (field.kind == FieldKind.singleSelect) {
    final matches = field.options
        .where(
          (o) => [
            o.label.toLowerCase(),
            o.id.toLowerCase().replaceAll('_', ' '),
          ].contains(text),
        )
        .toList();
    if (matches.length == 1) return TextAnswer(matches.single.id);
  }
  if (field.kind == FieldKind.boolean) {
    if (['yes', 'yes it is', 'yes i did'].contains(text)) {
      return const BoolAnswer(true);
    }
    if (['no', 'no it is not', 'no i did not'].contains(text)) {
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

class TurnEndpoint {
  TurnEndpoint({
    this.silence = const Duration(milliseconds: 1300),
    this.noSpeech = const Duration(seconds: 8),
  });
  final Duration silence, noSpeech;
  Duration _previous = Duration.zero,
      _voiced = Duration.zero,
      _burst = Duration.zero,
      _lastVoice = Duration.zero;
  bool get heardSpeech => _voiced >= const Duration(milliseconds: 180);
  bool observe(double level, Duration elapsed) {
    final delta = elapsed - _previous;
    _previous = elapsed;
    // Do not raise the release threshold after a loud word: a quieter "not"
    // or the end of a number remains part of the same answer.
    if (level >= .004) {
      _burst += Duration(milliseconds: delta.inMilliseconds.clamp(0, 200));
      _voiced = _burst > _voiced ? _burst : _voiced;
      _lastVoice = elapsed;
    } else {
      _burst = Duration.zero;
    }
    return heardSpeech ? elapsed - _lastVoice >= silence : elapsed >= noSpeech;
  }
}
