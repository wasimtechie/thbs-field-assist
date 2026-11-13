import '../../core/contracts.dart';
import '../voice/conversation.dart';
import '../voice/spoken_numbers.dart';
import '../voice/asset_reference.dart';
import '../voice/speech_repair.dart';
import 'closure_extraction.dart';
import 'optical_reading.dart';

/// Fixed, prepared speech contains no job data or engineer evidence.
const closureAssistantPrompts = {
  'assistant_greeting':
      'Hi. Talk me through this visit. I will fill in the details and ask if anything is missing.',
  'assistant_greeting_2':
      'Hello. How did this visit go? Tell me about the work, the tests, and anything left to do.',
  'assistant_greeting_3':
      'Ready when you are. Tell me what you got done, and we will put the visit report together.',
  'assistant_welcome_back':
      'Welcome back. Your answers are saved. Let us pick up with the details still missing.',
  'assistant_welcome_back_2':
      'Let us finish this report. I will just ask about the details we still need.',
  'assistant_welcome_back_3':
      'Your report is already started. We can carry on from where you left off.',
  'assistant_summary_invite':
      'Tell me what you did, what you tested, and what still needs attention.',
  'assistant_narrative_saved':
      'Summary added. I will ask for the remaining details.',
  'assistant_answer_saved': 'Added to the form.',
  'assistant_unclear':
      'Please give a clear answer, or choose an option. Say repeat to hear the question again.',
  'assistant_complete':
      'Voice capture complete. Say open draft to review your answers.',
  'assistant_anything_else': 'Anything else?',
  'assistant_guided_start': 'Let me ask you the details one at a time.',
  'assistant_summary_complete':
      'Your visit summary is ready. Review the answers, then press submit.',
  'assistant_paused':
      'Paused. Say resume to continue, or open draft to review.',
  'assistant_no_speech':
      'Ready for your answer. Say repeat, skip, pause, or open draft if needed.',
  'assistant_save_failed':
      'The answer could not be saved. Say retry to try again.',
};

String closureOpeningGreeting(int index, {bool resumed = false}) {
  final key = resumed ? 'assistant_welcome_back' : 'assistant_greeting';
  final variant = index % 3;
  return closureAssistantPrompts[variant == 0 ? key : '${key}_${variant + 1}']!;
}

/// Clarify the current question in speech. Unknown answers never become facts,
/// and a recognition mismatch does not force the engineer into a manual form.
String closureClarification(FieldDefinition field, String heard, int attempt) {
  if (field.id == 'serving_asset') {
    final type = spokenAssetType(heard);
    if (type != null) {
      return 'I heard ${type.toLowerCase()}. What is its number or reference? You can say the letters and numbers one at a time.';
    }
    return attempt == 1
        ? 'Please say the asset type, then its reference. For example, pole one two three. You can spell the letters.'
        : 'Let us try the reference one part at a time. Say pole or chamber, followed by the letters and numbers. Say skip if it is not available.';
  }
  if (field.kind == FieldKind.singleSelect) {
    return 'For this question, you can say ${field.options.map((o) => voiceChoiceLabel(field, o)).join(', ')}. Which one fits?';
  }
  if (field.kind == FieldKind.boolean) {
    return 'Just for this check, is that yes or no? You can say skip if you do not know.';
  }
  if ([
    FieldKind.integer,
    FieldKind.decimal,
    FieldKind.quantity,
  ].contains(field.kind)) {
    return field.id == 'optical_rx_dbm'
        ? 'Please say just the measured receive value, including minus and the decimal digits. I will confirm any unclear reading.'
        : 'Please say just the measured value. You can say the digits one at a time, or say not measured.';
  }
  return 'Let us try that once more. ${closureSpokenQuestion(field)}';
}

enum ClosureVoiceCommand { retry, repeat, skip, pause, resume, openDraft }

/// End summary collection only for an explicit conversational response. A bare
/// "completed" describes a job outcome and must not discard job information.
bool summaryFinished(String text) => RegExp(
  r"^(?:(?:nothing much|not really)[, ]+)?(?:(?:no|nope)[, ]*)?(?:that['’]?s (?:all|everything|it)|that is (?:all|everything|it)|nothing (?:else|more|much)|everything (?:is covered|has been covered)|i['’]?m done|i am done|all done|no)(?:[, ]*(?:thank you|thanks))?[.!?]*$",
  caseSensitive: false,
).hasMatch(text.trim());

/// Common empty/noise decodes and playback echoes are not visit evidence.
/// Keep this exclusion narrow: unfamiliar work descriptions remain valid.
bool hasSpokenReportContent(String text) {
  String words(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  final normalized = words(text);
  if (normalized.isEmpty || summaryFinished(text)) return false;
  if (closureAssistantPrompts.values.any((p) => words(p) == normalized)) {
    return false;
  }
  return !RegExp(
    r'^(?:hi|hello|hey|yes|yeah|yep|okay|ok|you|thanks|thank you(?: very much| for watching| for listening)?|(?:background )?(?:music|noise|silence)|inaudible|unintelligible|no speech|no audio)$',
  ).hasMatch(normalized);
}

ClosureVoiceCommand? closureVoiceCommand(String transcript) {
  final text = transcript
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[.!?,]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return const {
    'retry': ClosureVoiceCommand.retry,
    'try again': ClosureVoiceCommand.retry,
    'record again': ClosureVoiceCommand.retry,
    'start again': ClosureVoiceCommand.retry,
    'repeat': ClosureVoiceCommand.repeat,
    'repeat question': ClosureVoiceCommand.repeat,
    'repeat the question': ClosureVoiceCommand.repeat,
    'say that again': ClosureVoiceCommand.repeat,
    'skip': ClosureVoiceCommand.skip,
    'skip for now': ClosureVoiceCommand.skip,
    'skip summary': ClosureVoiceCommand.skip,
    'not measured': ClosureVoiceCommand.skip,
    'not available': ClosureVoiceCommand.skip,
    'skip question': ClosureVoiceCommand.skip,
    'skip this question': ClosureVoiceCommand.skip,
    'pause': ClosureVoiceCommand.pause,
    'pause conversation': ClosureVoiceCommand.pause,
    'resume': ClosureVoiceCommand.resume,
    'continue': ClosureVoiceCommand.resume,
    'open draft': ClosureVoiceCommand.openDraft,
    'open my draft': ClosureVoiceCommand.openDraft,
    'review draft': ClosureVoiceCommand.openDraft,
    'finish conversation': ClosureVoiceCommand.openDraft,
  }[text];
}

String closureSpokenValue(FieldDefinition field, Answer answer) {
  final raw = answer.toJson();
  if (raw is num) {
    final value = raw < 0 ? 'minus ${raw.abs()}' : raw.toString();
    if (field.id == 'optical_rx_dbm') return '$value dBm';
    if (['blockage_distance', 'route_distance'].contains(field.id)) {
      return '$value metres';
    }
    return value;
  }
  return field.display(answer);
}

List<String> closureSpeechChunks(String text) {
  final chunks = <String>[];
  var pending = '';
  for (final word in text.split(RegExp(r'\s+'))) {
    if (pending.isNotEmpty && pending.length + word.length + 1 > 180) {
      chunks.add(pending);
      pending = '';
    }
    pending = pending.isEmpty ? word : '$pending $word';
  }
  if (pending.isNotEmpty) chunks.add(pending);
  return chunks;
}

/// Fixed vocabulary normalization, never a paraphrase of engineer evidence.
String closureSpokenQuestion(FieldDefinition field) {
  const naturalQuestions = {
    'actual_work': 'What work did you complete on this visit?',
    'identity_verified':
        'Have you verified the work order and the premises? Say yes or no.',
    'serving_asset':
        'What is the reference of the serving CBT, pole or chamber?',
    'ont_serial': 'Please read out the ONT serial number or identifier.',
    'optical_rx_dbm':
        'What optical receive reading did you measure, in dBm? Include minus if the reading is negative.',
    'blockage_distance': 'How far along the route was the blockage, in metres?',
    'route_distance': 'What route distance did you measure, in metres?',
    'next_owner': 'Which team owns the next action, and what is the priority?',
  };
  var text =
      naturalQuestions[field.id] ??
      (field.id == 'claimed_outcome'
          ? 'What is the outcome for this work order? Say completed, partial, blocked, on hold, referral, stage completed, or network ready.'
          : spokenQuestion(field));
  for (final acronym in ['FTTP', 'FTTC', 'ONT', 'CBT', 'CSP', 'MDU']) {
    text = text.replaceAll(
      RegExp('\\b$acronym\\b'),
      acronym.split('').join(' '),
    );
  }
  if (text.trim().split(RegExp(r'\s+')).length <= 3) {
    text = 'Please tell me: $text';
  }
  return text;
}

Answer? closureSpokenAnswer(FieldDefinition field, String transcript) {
  if (field.id == 'optical_rx_dbm') {
    final fact = focusedOpticalFact(transcript);
    if (fact != null) {
      return fact['requiresConfirmation'] == true || fact['value'] is! num
          ? null
          : NumberAnswer(fact['value'] as num);
    }
    return null;
  }
  transcript = interpretSpokenRepairs(transcript).text;
  if (field.id == 'serving_asset') {
    final reference = spokenAssetReference(transcript);
    return reference == null ? null : TextAnswer(reference);
  }
  if ([FieldKind.decimal, FieldKind.integer].contains(field.kind)) {
    // The active question establishes the unit. Only an explicit number is
    // parsed; alternatives, corrections and uncertain readings remain missing.
    final text = transcript.trim().replaceFirst(
      RegExp(
        field.id == 'optical_rx_dbm'
            ? r'\s*(?:d\s*b\s*m)[.!?]*$'
            : ['blockage_distance', 'route_distance'].contains(field.id)
            ? r'\s*(?:m|metres?|meters?)[.!?]*$'
            : r'(?!)',
        caseSensitive: false,
      ),
      '',
    );
    return directNumericAnswer(field, text);
  }
  if (field.kind == FieldKind.boolean) {
    final text = transcript
        .toLowerCase()
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'[.,!?;]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final explicit = const {
      'yes i have': true,
      'yes we have': true,
      'yes we did': true,
      'yes it was': true,
      "yes that's correct": true,
      'yes that is correct': true,
      "no i haven't": false,
      "no we haven't": false,
      "no we didn't": false,
      "no it wasn't": false,
      'no i have not': false,
      'no we have not': false,
    }[text];
    if (explicit != null) return BoolAnswer(explicit);
    final facts = literalClosureFacts(
      transcript,
    ).where((f) => f['fieldId'] == field.id).toList();
    if (facts.length == 1 && facts.single['value'] is bool) {
      return BoolAnswer(facts.single['value'] as bool);
    }
  }
  return directSpokenAnswer(field, transcript);
}
