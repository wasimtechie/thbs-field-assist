import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/contracts.dart';
import '../voice/conversation.dart';
import '../voice/speech_input.dart';
import '../voice/streaming_capture.dart';
import '../voice/speech_repair.dart';
import '../voice/asset_reference.dart';
import '../voice/voice_audio.dart';
import 'closure_speech.dart';
import 'closure_voice_turn.dart' show ClosureVoiceAnswer;

class ClosureVoiceFact {
  const ClosureVoiceFact(this.field, this.source);
  final FieldDefinition field;
  final Json source;
  Answer? get answer => decodeAnswers({field.id: source['value']})[field.id];
}

enum _Phase {
  preparing,
  speaking,
  listening,
  typing,
  understanding,
  review,
  saving,
  paused,
  complete,
}

enum _Listen { answer, control }

/// A voice-led conversation that fills an editable draft automatically.
/// This route has no closure or submission action; final review is separate.
class ClosureVoiceAssistant extends StatefulWidget {
  const ClosureVoiceAssistant({
    super.key,
    required this.recognizer,
    required this.synthesizer,
    required this.audio,
    required this.assertAccess,
    required this.needsNarrative,
    required this.nextQuestion,
    required this.proposeNarrative,
    required this.keepNarrative,
    required this.keepAnswer,
    this.validAnswer,
    this.handoffDelay = const Duration(milliseconds: 40),
    this.jobTitle = 'Your field visit',
    this.cancelInference,
    this.completionPrompt,
    this.announceSavedAnswers = true,
    this.resetAnswers,
    this.collectSummaryFirst = false,
    this.closeWhenComplete = false,
    this.isAnswered,
    this.recognitionTimeout = const Duration(seconds: 15),
    this.prepareAnswer,
    this.confirmationFor,
    this.rejectConfirmation,
    this.greetingIndex = 0,
  });
  final SpeechRecognizer recognizer;
  final SpeechSynthesizer synthesizer;
  final VoiceAudio audio;
  final Future<void> Function() assertAccess;
  final bool needsNarrative;
  final FieldDefinition? Function(Set<String> skipped) nextQuestion;
  final Future<List<ClosureVoiceFact>> Function(
    String text,
    bool Function() current,
  )
  proposeNarrative;
  final Future<void> Function(
    String text,
    List<ClosureVoiceFact> facts,
    Set<String> selected,
  )
  keepNarrative;
  final Future<void> Function(FieldDefinition field, ClosureVoiceAnswer answer)
  keepAnswer;
  final bool Function(FieldDefinition field, Answer answer)? validAnswer;
  final Duration handoffDelay;
  final String jobTitle;
  final VoidCallback? cancelInference;
  final String? completionPrompt;
  final bool announceSavedAnswers;
  final Future<bool> Function()? resetAnswers;
  final bool collectSummaryFirst;
  final bool closeWhenComplete;
  final bool Function(FieldDefinition)? isAnswered;
  final Duration recognitionTimeout;
  final Future<ClosureVoiceAnswer> Function(
    FieldDefinition field,
    String text,
    bool Function() current,
  )?
  prepareAnswer;
  final ClosureVoiceFact? Function(FieldDefinition)? confirmationFor;
  final Future<void> Function(FieldDefinition)? rejectConfirmation;
  final int greetingIndex;

  @override
  State<ClosureVoiceAssistant> createState() => _ClosureVoiceAssistantState();
}

class _ClosureVoiceAssistantState extends State<ClosureVoiceAssistant>
    with WidgetsBindingObserver {
  _Phase phase = _Phase.preparing;
  late bool narrativeTurn = widget.needsNarrative;
  FieldDefinition? field;
  String spoken = '',
      transcript = '',
      error = '',
      inputSource = 'speech',
      inputMethod = 'speech';
  Answer? answer;
  List<ClosureVoiceFact> facts = [];
  List<Json> responseFacts = [];
  ClosureVoiceFact? confirmation;
  String get activeQuestion => confirmation == null
      ? closureSpokenQuestion(field!)
      : confirmation!.source['unitNeedsConfirmation'] == true
      ? 'Was the optical receive reading ${closureSpokenValue(field!, confirmation!.answer!)}? Say yes or no.'
      : 'I heard ${closureSpokenValue(field!, confirmation!.answer!)}. Is that correct? Say yes or no.';
  final selected = <String>{}, skipped = <String>{};
  final bytes = BytesBuilder(copy: false);
  final typedAnswer = TextEditingController();
  final answerFocus = FocusNode();
  Timer? limit, inputWatchdog;
  StreamingCapture? streamingCapture;
  Future<void>? pendingWrite;
  int generation = 0, captureSerial = 0, savedTurns = 0;
  double level = 0;
  bool reviewSpeaking = false,
      reviewNarrative = false,
      retryPending = false,
      sourceRetained = false;
  bool resettingAnswers = false;
  int emptyTurns = 0, unclearTurns = 0;
  bool addingSummary = false;
  String summaryText = '';
  String assetTypeContext = '', assetTypeWords = '';
  _Listen? listening;
  bool get reviewing => phase == _Phase.review;
  bool get working => [
    _Phase.preparing,
    _Phase.speaking,
    _Phase.listening,
    _Phase.understanding,
  ].contains(phase);
  bool current(int turn) => mounted && generation == turn;

  Future<bool> stopTurnAudio(int turn) async {
    final streaming = streamingCapture;
    streamingCapture = null;
    await widget.audio.stopCapture();
    await streaming?.cancel();
    if (!current(turn)) return false;
    await widget.audio.stopPlayback();
    return current(turn);
  }

  String get status => switch (phase) {
    _Phase.preparing => 'Getting ready',
    _Phase.speaking => 'Assistant speaking',
    _Phase.listening => 'Answer aloud or choose below',
    _Phase.typing => 'Type your answer · Voice paused',
    _Phase.understanding => 'Finding your details',
    _Phase.review => 'Added to your draft',
    _Phase.saving => 'Saving your answer',
    _Phase.paused =>
      listening == _Listen.control
          ? 'Paused · Say resume to continue'
          : 'Conversation paused',
    _Phase.complete => 'Say open draft to review',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    answerFocus.addListener(() {
      if (answerFocus.hasFocus &&
          phase != _Phase.typing &&
          phase != _Phase.saving) {
        unawaited(pauseForTyping());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(begin()));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(pause());
    }
  }

  @override
  void dispose() {
    generation++;
    captureSerial++;
    limit?.cancel();
    inputWatchdog?.cancel();
    typedAnswer.dispose();
    answerFocus.dispose();
    widget.cancelInference?.call();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.audio.close());
    unawaited(streamingCapture?.cancel());
    super.dispose();
  }

  Future<bool> say(String text, int turn) async {
    final clip = await widget.synthesizer.synthesize(text);
    if (!current(turn)) return false;
    await widget.assertAccess();
    if (!current(turn)) return false;
    final complete = await widget.audio.play(clip, (value) {
      if (current(turn)) setState(() => level = value);
    });
    if (!current(turn)) return false;
    setState(() => level = 0);
    if (!complete) throw StateError('Playback interrupted');
    return true;
  }

  Future<void> begin() async {
    if (!mounted) return;
    if (narrativeTurn) {
      await ask(closureOpeningGreeting(widget.greetingIndex));
    } else {
      await next(welcome: true);
    }
  }

  Future<void> resetConversation() async {
    if (resettingAnswers ||
        pendingWrite != null ||
        widget.resetAnswers == null) {
      return;
    }
    final turn = ++generation;
    limit?.cancel();
    captureSerial++;
    listening = null;
    bytes.clear();
    widget.cancelInference?.call();
    setState(() => resettingAnswers = true);
    try {
      if (!await stopTurnAudio(turn)) return;
      final cleared = await widget.resetAnswers!();
      if (!current(turn)) return;
      if (!cleared) {
        await next();
        return;
      }
      setState(() {
        narrativeTurn = true;
        addingSummary = false;
        summaryText = '';
        field = null;
        confirmation = null;
        transcript = '';
        answer = null;
        facts = [];
        selected.clear();
        skipped.clear();
        savedTurns = 0;
        retryPending = false;
        sourceRetained = false;
        error = '';
      });
      await begin();
    } catch (_) {
      if (current(turn)) {
        await pause(
          message:
              'Could not reset. Your saved answers are retained. Open the draft to retry.',
        );
      }
    } finally {
      if (mounted) setState(() => resettingAnswers = false);
    }
  }

  Future<void> next({bool welcome = false}) async {
    assetTypeContext = '';
    assetTypeWords = '';
    field = widget.nextQuestion(skipped);
    confirmation = field == null ? null : widget.confirmationFor?.call(field!);
    if (field == null) {
      final turn = ++generation;
      setState(() {
        phase = _Phase.complete;
        transcript = '';
        spoken = 'Your voice capture is complete.';
      });
      try {
        await widget.audio.configure(() => unawaited(pause()));
        if (await say(
          widget.completionPrompt ??
              closureAssistantPrompts['assistant_complete']!,
          turn,
        )) {
          if (widget.closeWhenComplete) {
            await close(completed: true);
          } else {
            await listen(turn, _Listen.control);
          }
        }
      } catch (_) {
        if (current(turn)) {
          setState(() => error = 'Open your draft to continue.');
        }
      }
      return;
    }
    await ask(activeQuestion, welcome: welcome);
  }

  Future<void> ask(
    String question, {
    bool welcome = false,
    bool speak = true,
  }) async {
    final turn = ++generation;
    limit?.cancel();
    inputWatchdog?.cancel();
    listening = null;
    captureSerial++;
    bytes.clear();
    setState(() {
      phase = _Phase.preparing;
      spoken = question;
      transcript = '';
      answer = null;
      facts = [];
      responseFacts = [];
      selected.clear();
      error = '';
      reviewSpeaking = false;
      retryPending = false;
      sourceRetained = false;
      typedAnswer.clear();
      inputSource = 'speech';
      inputMethod = 'speech';
      unclearTurns = 0;
    });
    try {
      if (!await stopTurnAudio(turn)) return;
      await widget.assertAccess();
      if (!current(turn)) return;
      await widget.audio.configure(() => unawaited(pause()));
      if (!current(turn)) return;
      setState(() => phase = _Phase.speaking);
      if (welcome &&
          !await say(
            closureOpeningGreeting(widget.greetingIndex, resumed: true),
            turn,
          )) {
        return;
      }
      if (!speak || await say(question, turn)) {
        await listen(turn, _Listen.answer);
      }
    } catch (_) {
      if (current(turn)) {
        await pause(
          message:
              'Voice could not start. Check microphone permission, then resume or choose an answer below.',
        );
      }
    }
  }

  Future<void> listen(int turn, _Listen mode) async {
    if (!current(turn)) return;
    final handoff = ++captureSerial;
    await Future<void>.delayed(widget.handoffDelay);
    if (!current(turn) || handoff != captureSerial) return;
    if (!await widget.audio.hasPermission()) {
      throw StateError('Microphone permission');
    }
    await widget.assertAccess();
    if (!current(turn)) return;
    bytes.clear();
    final endpoint = TurnEndpoint(
          // Narratives allow a longer thinking pause. Focused answers can move on
          // faster without requiring a Finish button.
          silence: narrativeTurn
              ? summarySpeechPause
              : const Duration(milliseconds: 700),
          noSpeech: additionalSpeechWait,
          adaptiveNoise: true,
        ),
        capture = ++captureSerial;
    setState(() {
      listening = mode;
      reviewSpeaking = false;
      if (mode == _Listen.answer) phase = _Phase.preparing;
    });
    final recognizer = widget.recognizer;
    final streamingRecognizer = recognizer is StreamingSpeechRecognizer
        ? recognizer as StreamingSpeechRecognizer
        : null;
    if (streamingRecognizer != null && streamingRecognizer.streamingAvailable) {
      final speechTurn = await streamingRecognizer.startSpeechTurn();
      if (!current(turn) || captureSerial != capture || listening != mode) {
        await speechTurn.cancel();
        return;
      }
      streamingCapture = StreamingCapture(
        turn: speechTurn,
        silence: narrativeTurn ? summarySpeechPause : answerSpeechPause,
        silenceFor: (progress) => hasPendingSpokenRepair(progress.text)
            ? const Duration(seconds: 3)
            : narrativeTurn
            ? summarySpeechPause
            : answerSpeechPause,
        noSpeech: additionalSpeechWait,
        onProgress: (progress) {
          if (current(turn) && captureSerial == capture && listening == mode) {
            setState(() => transcript = progress.text);
          }
        },
        onEnd: (empty) {
          if (current(turn) && captureSerial == capture && listening == mode) {
            unawaited(finish(noSpeech: empty));
          }
        },
        onError: (_) {
          if (current(turn) && captureSerial == capture && listening == mode) {
            unawaited(
              pause(
                message:
                    'Speech processing stopped. Your saved answers are retained. Resume to retry.',
              ),
            );
          }
        },
      );
    }
    await widget.audio.capture(
      onBytes: (chunk) {
        if (current(turn) &&
            captureSerial == capture &&
            listening == mode &&
            bytes.length + chunk.length <= 16000 * 2 * 60) {
          bytes.add(chunk);
          streamingCapture?.add(chunk);
        }
      },
      onLevel: (value) {
        if (!current(turn) || captureSerial != capture || listening != mode) {
          return;
        }
        setState(() => level = value);
        final elapsed = Duration(microseconds: bytes.length * 1000000 ~/ 32000);
        if (streamingCapture == null && endpoint.observe(value, elapsed)) {
          unawaited(finish(noSpeech: !endpoint.heardSpeech));
        }
      },
      onError: (_) {
        if (current(turn) && captureSerial == capture) {
          unawaited(
            pause(
              message: 'The microphone stopped. Your saved draft is retained.',
            ),
          );
        }
      },
    );
    if (!current(turn) || captureSerial != capture || listening != mode) {
      if (captureSerial == capture) await widget.audio.stopCapture();
      return;
    }
    // Show Listening only after the recorder is actually connected. Showing it
    // during permission/native setup invited answers into a deaf window.
    if (mode == _Listen.answer) setState(() => phase = _Phase.listening);
    limit?.cancel();
    limit = Timer(
      Duration(
        seconds: narrativeTurn
            ? 60
            : field?.kind == FieldKind.longText
            ? 30
            : 12,
      ),
      () => unawaited(
        finish(
          noSpeech: !(streamingCapture?.heardSpeech ?? endpoint.heardSpeech),
        ),
      ),
    );
    inputWatchdog?.cancel();
    inputWatchdog = Timer(const Duration(seconds: 3), () {
      if (current(turn) && captureSerial == capture && bytes.isEmpty) {
        unawaited(finish(noSpeech: true));
      }
    });
  }

  Future<void> noClearSpeech(int turn, _Listen mode) async {
    if (mode == _Listen.control) {
      await listen(turn, mode);
      return;
    }
    if (addingSummary) {
      if (++emptyTurns >= 2) {
        await pause(
          message:
              'Your earlier summary is saved. I could not recognise the extra detail. Resume to add it, or open the draft.',
        );
        return;
      }
      const prompt =
          'Your earlier summary is saved. What would you like to add?';
      setState(() {
        spoken = prompt;
        phase = _Phase.speaking;
      });
      if (await say(prompt, turn)) {
        await listen(turn, mode);
      }
      return;
    }
    if (widget.collectSummaryFirst && narrativeTurn && !addingSummary) {
      // No report has been heard. Offer the guided form instead of treating
      // silence as a summary or asking whether there is anything to add.
      await startGuidedQuestions(turn);
      return;
    }
    if (field != null && widget.isAnswered?.call(field!) == true) {
      await next();
      return;
    }
    if (++emptyTurns >= 2) {
      await pause(
        message:
            'No clear speech reached the assistant. Your saved answers are retained. Check the microphone, enable noise reduction, or choose an answer below, then resume.',
      );
      return;
    }
    if (mode != _Listen.control &&
        !await say(closureAssistantPrompts['assistant_no_speech']!, turn)) {
      return;
    }
    await listen(turn, mode);
  }

  Future<void> startGuidedQuestions(int turn) async {
    if (!current(turn)) return;
    narrativeTurn = false;
    addingSummary = false;
    emptyTurns = 0;
    if (await say(closureAssistantPrompts['assistant_guided_start']!, turn)) {
      await next();
    }
  }

  Future<void> finish({bool noSpeech = false}) async {
    final mode = listening;
    if (mode == null) return;
    final turn = generation;
    final streaming = streamingCapture;
    streamingCapture = null;
    limit?.cancel();
    inputWatchdog?.cancel();
    captureSerial++;
    setState(() {
      listening = null;
      level = 0;
      if (mode == _Listen.answer) phase = _Phase.understanding;
    });
    try {
      final pcm = bytes.takeBytes();
      await widget.audio.stopCapture();
      if (!current(turn)) return;
      if (pcm.length < 640 || (noSpeech && streaming == null)) {
        await streaming?.cancel();
        if (addingSummary && noSpeech) {
          await finishSummary();
          return;
        }
        await noClearSpeech(turn, mode);
        return;
      }
      final data = ByteData.sublistView(pcm),
          samples = Float32List(pcm.length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
      }
      await widget.assertAccess();
      if (!current(turn)) return;
      String text;
      try {
        text =
            (await (streaming != null
                        ? streaming.finish()
                        : widget.recognizer.transcribe(
                            trimSpeechSilence(samples),
                          ))
                    .timeout(widget.recognitionTimeout))
                .trim();
      } on TimeoutException {
        widget.cancelInference?.call();
        await pause(
          message:
              'Speech processing took too long. Your saved answers are retained. Resume to retry, or choose an answer below.',
        );
        return;
      }
      await widget.assertAccess();
      if (!current(turn)) return;
      if (text.isEmpty) {
        if (addingSummary && noSpeech) {
          await finishSummary();
          return;
        }
        await noClearSpeech(turn, mode);
        return;
      }
      emptyTurns = 0;
      if (addingSummary && summaryFinished(text)) {
        await finishSummary();
        return;
      }
      final command = closureVoiceCommand(text);
      if (command == ClosureVoiceCommand.openDraft) {
        await close();
        return;
      }
      if (command == ClosureVoiceCommand.pause) {
        await voicePause();
        return;
      }
      if (command == ClosureVoiceCommand.repeat) {
        await repeatQuestion();
        return;
      }
      if (command == ClosureVoiceCommand.resume) {
        await resume();
        return;
      }
      if (mode == _Listen.control) {
        if (await say(
          phase == _Phase.complete
              ? widget.completionPrompt ??
                    closureAssistantPrompts['assistant_complete']!
              : closureAssistantPrompts['assistant_paused']!,
          turn,
        )) {
          await listen(turn, mode);
        }
        return;
      }
      if (command == ClosureVoiceCommand.skip) {
        await skip(reason: text);
        return;
      }
      if (command == ClosureVoiceCommand.retry) {
        if (retryPending) {
          await store();
        } else {
          await resume();
        }
        return;
      }
      if (widget.collectSummaryFirst &&
          (narrativeTurn || field?.id == 'actual_work') &&
          !hasSpokenReportContent(text)) {
        if (addingSummary || !narrativeTurn) {
          await noClearSpeech(turn, mode);
        } else {
          await startGuidedQuestions(turn);
        }
        return;
      }
      inputSource = 'speech';
      inputMethod = 'speech';
      setState(() {
        transcript = text;
        sourceRetained = false;
      });
      if (narrativeTurn) {
        final combined = summaryText.isEmpty ? text : '$summaryText\n$text';
        // Closing or pausing during mapping must retain both summary turns.
        setState(() => transcript = combined);
        // Map and save before asking for more, so the next question always
        // sees the fields already supplied in the engineer's summary.
        final proposals = await widget.proposeNarrative(
          combined,
          () => current(turn),
        );
        if (!current(turn)) return;
        setState(() {
          transcript = combined;
          facts = proposals;
          selected.clear();
          selected.addAll(
            facts.where((f) => f.answer != null).map((f) => f.field.id),
          );
        });
        await store();
      } else {
        if (confirmation != null) {
          final reply = text
              .toLowerCase()
              .replaceAll('’', "'")
              .replaceAll(RegExp(r'[.!?,]'), '')
              .trim();
          if (RegExp(
            r"^(?:yes|yeah|yep|correct|that's correct|that is correct|yes that's correct|yes that is correct)$",
          ).hasMatch(reply)) {
            await confirmReading(true, text);
            return;
          }
          if (RegExp(
            r'^(?:no|nope|incorrect|not correct|no that is incorrect)$',
          ).hasMatch(reply)) {
            await confirmReading(false, text);
            return;
          }
        }
        final contextualAsset =
            field!.id == 'serving_asset' &&
            assetTypeContext.isNotEmpty &&
            spokenAssetReference(text) == null &&
            spokenAssetType(text) == null &&
            spokenAssetReference('$assetTypeContext $text') != null;
        final interpreted = contextualAsset ? '$assetTypeContext $text' : text;
        final evidence = contextualAsset ? '$assetTypeWords\n$text' : text;
        final prepared = widget.prepareAnswer == null
            ? ClosureVoiceAnswer(
                evidence,
                closureSpokenAnswer(field!, interpreted),
                closureSpokenQuestion(field!),
              )
            : await widget.prepareAnswer!(
                field!,
                interpreted,
                () => current(turn),
              );
        if (!current(turn)) return;
        final proposed = prepared.answer;
        responseFacts = [
          for (final fact in prepared.facts)
            if (contextualAsset && fact['fieldId'] == 'serving_asset')
              {...fact, 'sourceSpan': evidence, 'interpretedSpan': interpreted}
            else
              fact,
        ];
        if (proposed == null ||
            widget.validAnswer?.call(field!, proposed) == false) {
          transcript = evidence;
          await widget.keepAnswer(
            field!,
            ClosureVoiceAnswer(
              evidence,
              null,
              closureSpokenQuestion(field!),
              facts: responseFacts,
            ),
          );
          if (!current(turn)) return;
          sourceRetained = true;
          if (widget.isAnswered?.call(field!) == true) {
            await next();
          } else {
            final type = field!.id == 'serving_asset'
                ? spokenAssetType(text)
                : null;
            if (type != null) {
              assetTypeContext = type;
              assetTypeWords = text;
            }
            final clarification = confirmation != null
                ? activeQuestion
                : closureClarification(field!, text, ++unclearTurns);
            setState(() {
              spoken = clarification;
              phase = _Phase.speaking;
            });
            if (await say(clarification, turn)) {
              await listen(turn, _Listen.answer);
            }
          }
        } else {
          setState(() {
            transcript = evidence;
            answer = proposed;
          });
          await store();
        }
      }
    } catch (_) {
      await streaming?.cancel();
      if (current(turn)) {
        try {
          await noClearSpeech(turn, mode);
        } catch (_) {
          if (current(turn)) {
            await pause(
              message: 'Voice paused. Your saved answers are retained.',
            );
          }
        }
      }
    }
  }

  Future<void> store() async {
    if (phase == _Phase.saving || pendingWrite != null) return;
    final turn = ++generation;
    limit?.cancel();
    listening = null;
    captureSerial++;
    setState(() {
      phase = _Phase.saving;
      error = '';
      retryPending = true;
    });
    var committed = false;
    try {
      if (!await stopTurnAudio(turn)) return;
      await widget.assertAccess();
      if (!current(turn)) return;
      final wasNarrative = narrativeTurn;
      if (narrativeTurn) {
        pendingWrite = widget.keepNarrative(transcript, facts, {...selected});
        await pendingWrite;
        narrativeTurn = false;
      } else {
        final question = field!;
        pendingWrite = widget.keepAnswer(
          question,
          ClosureVoiceAnswer(
            transcript,
            answer,
            activeQuestion,
            sourceType: inputSource,
            inputMethod: inputMethod,
            facts: responseFacts,
          ),
        );
        await pendingWrite;
      }
      pendingWrite = null;
      committed = true;
      savedTurns++;
      retryPending = false;
      sourceRetained = true;
      if (!current(turn)) {
        transcript = '';
        facts = [];
        answer = null;
        field = null;
        if (mounted) setState(() {});
        return;
      }
      if (widget.announceSavedAnswers) {
        setState(() {
          phase = _Phase.review;
          reviewSpeaking = true;
          reviewNarrative = wasNarrative;
        });
        try {
          final acknowledgement = wasNarrative
              ? closureAssistantPrompts['assistant_narrative_saved']!
              : closureAssistantPrompts['assistant_answer_saved']!;
          for (final chunk in closureSpeechChunks(acknowledgement)) {
            if (!await say(chunk, turn)) return;
          }
        } catch (_) {
          /* A saved answer remains saved if its acknowledgement fails. */
        }
      }
      if (!current(turn)) return;
      if (wasNarrative && widget.collectSummaryFirst) {
        summaryText = transcript;
        if (addingSummary) {
          // One invitation to add details is enough. Once that addition ends,
          // continue directly to the remaining fields or final review.
          await finishSummary();
          return;
        }
        addingSummary = true;
        narrativeTurn = true;
        field = null;
        await ask(closureAssistantPrompts['assistant_anything_else']!);
        return;
      }
      transcript = '';
      facts = [];
      answer = null;
      field = null;
      await next();
    } catch (_) {
      pendingWrite = null;
      if (current(turn)) {
        if (committed) {
          retryPending = false;
          await pause(
            message:
                'Your answer is saved. Voice paused before the next question. Resume to continue.',
          );
          return;
        }
        setState(() {
          retryPending = true;
          phase = _Phase.listening;
          error = 'Could not save. Say retry, choose an answer, or open draft.';
          reviewSpeaking = false;
        });
        try {
          if (await say(
            closureAssistantPrompts['assistant_save_failed']!,
            turn,
          )) {
            await listen(turn, _Listen.answer);
          }
        } catch (_) {
          if (current(turn)) {
            await pause(message: 'Unlock the workspace and resume to retry.');
          }
        }
      }
    }
  }

  Future<void> finishSummary() async {
    if (pendingWrite != null) return;
    addingSummary = false;
    narrativeTurn = false;
    transcript = '';
    facts = [];
    answer = null;
    field = null;
    await next();
  }

  Future<void> confirmReading(
    bool accepted,
    String reply, {
    bool manual = false,
  }) async {
    if (phase == _Phase.saving || pendingWrite != null) return;
    final proposed = confirmation, target = field;
    if (proposed == null || target == null) return;
    if (!accepted) {
      await pause();
      final turn = generation;
      try {
        setState(() => phase = _Phase.saving);
        await widget.rejectConfirmation?.call(target);
        if (!current(turn)) return;
        confirmation = null;
        await ask(closureSpokenQuestion(target));
      } catch (_) {
        if (current(turn)) {
          await pause(message: 'Could not update the draft. Resume to retry.');
        }
      }
      return;
    }
    transcript = reply;
    answer = proposed.answer;
    inputSource = manual ? 'manual' : 'speech';
    inputMethod = manual ? 'option' : 'speech';
    responseFacts = [
      {
        ...proposed.source,
        'requiresConfirmation': false,
        'verificationStatus': 'engineer_confirmed',
        'confirmationSpan': reply,
        'question': activeQuestion,
        'sourceType': inputSource,
      },
    ];
    widget.cancelInference?.call();
    await store();
  }

  Future<void> choose(
    Answer value,
    String label, {
    String method = 'option',
  }) async {
    if (phase == _Phase.saving || reviewing || pendingWrite != null) return;
    if (addingSummary) {
      await pause();
      await finishSummary();
      return;
    }
    final target = field;
    if (target == null || widget.validAnswer?.call(target, value) == false) {
      return;
    }
    transcript = label;
    responseFacts = [];
    answer = value;
    inputSource = 'manual';
    inputMethod = method;
    sourceRetained = false;
    widget.cancelInference?.call();
    await store();
  }

  Future<void> submitTyped() async {
    final target = field, text = typedAnswer.text.trim();
    if (target == null || text.isEmpty) return;
    final value = closureSpokenAnswer(target, text);
    if (value == null || widget.validAnswer?.call(target, value) == false) {
      setState(() => error = 'Enter a clear value for this question.');
      return;
    }
    FocusScope.of(context).unfocus();
    await choose(value, text, method: 'typed');
  }

  Future<void> skip({
    String reason = 'Skipped for later review',
    String source = 'speech',
  }) async {
    if (phase == _Phase.saving || pendingWrite != null) return;
    final turn = ++generation;
    limit?.cancel();
    listening = null;
    captureSerial++;
    setState(() => phase = _Phase.saving);
    try {
      if (!await stopTurnAudio(turn)) return;
      await widget.assertAccess();
      if (!current(turn)) return;
      if (confirmation != null && field != null) {
        await widget.rejectConfirmation?.call(field!);
        if (!current(turn)) return;
        confirmation = null;
      }
      if (narrativeTurn) {
        if (transcript.isNotEmpty) {
          pendingWrite = widget.keepNarrative(transcript, facts, {});
          await pendingWrite;
        }
        narrativeTurn = false;
        skipped.add('actual_work');
      } else if (field != null) {
        pendingWrite = widget.keepAnswer(
          field!,
          ClosureVoiceAnswer(
            reason,
            null,
            closureSpokenQuestion(field!),
            sourceType: source,
            inputMethod: source == 'manual' ? 'option' : 'speech',
          ),
        );
        await pendingWrite;
        skipped.add(field!.id);
      }
      pendingWrite = null;
      transcript = '';
      facts = [];
      answer = null;
      field = null;
      if (current(turn)) await next();
    } catch (_) {
      pendingWrite = null;
      if (current(turn)) {
        await pause(
          message: 'Could not retain that transcript. Please resume to retry.',
        );
      }
    }
  }

  Future<void> pause({String message = ''}) async {
    final turn = ++generation;
    captureSerial++;
    limit?.cancel();
    inputWatchdog?.cancel();
    listening = null;
    bytes.clear();
    widget.cancelInference?.call();
    if (mounted) {
      setState(() {
        phase = _Phase.paused;
        level = 0;
        error = message;
        reviewSpeaking = false;
      });
    }
    try {
      await stopTurnAudio(turn);
    } catch (_) {
      // The paused state and retained answers remain usable if native cleanup fails.
    }
  }

  Future<void> toggleNoiseReduction() async {
    final audio = widget.audio;
    if (audio is! NoiseControlledVoiceAudio || pendingWrite != null) return;
    final controls = audio as NoiseControlledVoiceAudio;
    final enabled = !controls.noiseReduction;
    await pause();
    if (!mounted) return;
    controls.noiseReduction = enabled;
    emptyTurns = 0;
    await resume();
  }

  Future<void> voicePause() async {
    final turn = generation + 1;
    await pause();
    if (!current(turn)) return;
    try {
      if (await say(closureAssistantPrompts['assistant_paused']!, turn)) {
        await listen(turn, _Listen.control);
      }
    } catch (_) {
      if (current(turn)) {
        setState(() => error = 'Paused. Resume when the device is ready.');
      }
    }
  }

  Future<void> pauseForTyping() async {
    final turn = generation + 1;
    await pause();
    if (current(turn) && answerFocus.hasFocus) {
      setState(() => phase = _Phase.typing);
    }
  }

  Future<void> repeatQuestion() async {
    FocusScope.of(context).unfocus();
    if (pendingWrite != null) {
      await resume();
      return;
    }
    if (!narrativeTurn && field == null) {
      await next();
    } else {
      await ask(
        narrativeTurn
            ? closureAssistantPrompts[addingSummary
                  ? 'assistant_anything_else'
                  : 'assistant_summary_invite']!
            : activeQuestion,
      );
    }
  }

  Future<void> resume() async {
    final turn = generation;
    try {
      await pendingWrite;
    } catch (_) {
      // The failed write remains pending for an explicit retry below.
    }
    if (!current(turn)) return;
    if (retryPending) {
      await store();
    } else if (narrativeTurn) {
      await ask(
        closureAssistantPrompts[addingSummary
            ? 'assistant_anything_else'
            : 'assistant_summary_invite']!,
      );
    } else if (field != null) {
      await ask(activeQuestion);
    } else {
      await next();
    }
  }

  Future<void> close({bool completed = false}) async {
    if (phase == _Phase.saving || pendingWrite != null) return;
    final turn = generation + 1;
    await pause();
    if (!current(turn)) return;
    if (transcript.isNotEmpty && !sourceRetained && mounted) {
      setState(() => phase = _Phase.saving);
      try {
        await widget.assertAccess();
        if (!current(turn)) return;
        if (narrativeTurn) {
          final retained =
              summaryText.isEmpty || transcript.startsWith(summaryText)
              ? transcript
              : '$summaryText\n$transcript';
          if (hasSpokenReportContent(transcript) &&
              closureVoiceCommand(transcript) == null) {
            await widget.keepNarrative(retained, facts, {});
          }
        } else if (field != null) {
          await widget.keepAnswer(
            field!,
            ClosureVoiceAnswer(
              transcript,
              null,
              closureSpokenQuestion(field!),
              sourceType: inputSource,
              inputMethod: inputMethod,
            ),
          );
        }
      } catch (_) {
        if (current(turn)) {
          setState(() {
            phase = _Phase.paused;
            error = 'Could not keep this transcript. Resume to retry.';
          });
        }
        return;
      }
    }
    if (mounted && current(turn)) Navigator.pop(context, completed);
  }

  Widget answerChoices() {
    final target = field;
    final enabled =
        phase != _Phase.saving && !reviewing && pendingWrite == null;
    const color = Color(0xffb8d2ff);
    Widget option(String label, VoidCallback action, {IconData? icon}) =>
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xff132e4e),
            side: const BorderSide(color: Color(0xff33577e)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
          onPressed: enabled ? action : null,
          icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 17),
          label: Text(label),
        );
    final numeric =
        target != null &&
        [
          FieldKind.integer,
          FieldKind.decimal,
          FieldKind.quantity,
        ].contains(target.kind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (addingSummary)
          option('Nothing else · Continue', () async {
            await pause();
            await finishSummary();
          }),
        const Text(
          'SPEAK YOUR ANSWER OR CHOOSE',
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 10, letterSpacing: 1.4),
        ),
        const SizedBox(height: 12),
        if (confirmation != null)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              option(
                'Yes, use ${field!.display(confirmation!.answer)}',
                () => confirmReading(
                  true,
                  'Confirmed proposed reading',
                  manual: true,
                ),
                icon: Icons.check_rounded,
              ),
              option(
                'No, correct reading',
                () => confirmReading(
                  false,
                  'Rejected proposed reading',
                  manual: true,
                ),
                icon: Icons.close_rounded,
              ),
            ],
          )
        else if (target?.kind == FieldKind.boolean)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              option(
                'Yes',
                () => choose(const BoolAnswer(true), 'Yes'),
                icon: Icons.check_rounded,
              ),
              option(
                'No',
                () => choose(const BoolAnswer(false), 'No'),
                icon: Icons.close_rounded,
              ),
            ],
          )
        else if (target?.kind == FieldKind.singleSelect)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final choice in target!.options)
                option(
                  choice.label,
                  () => choose(TextAnswer(choice.id), choice.label),
                ),
            ],
          )
        else if (target != null) ...[
          TextField(
            key: ValueKey('voice-answer-${target.id}'),
            controller: typedAnswer,
            focusNode: answerFocus,
            enabled: enabled,
            maxLength: numeric ? 40 : 1500,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  )
                : TextInputType.text,
            textInputAction: TextInputAction.send,
            style: const TextStyle(color: Colors.white),
            onSubmitted: (_) => submitTyped(),
            decoration: InputDecoration(
              labelText: numeric
                  ? 'Enter a reading (optional)'
                  : 'Type an answer (optional)',
              labelStyle: const TextStyle(color: color),
              suffixText: target.id == 'optical_rx_dbm'
                  ? 'dBm'
                  : ['blockage_distance', 'route_distance'].contains(target.id)
                  ? 'metres'
                  : null,
              suffixIcon: IconButton(
                tooltip: 'Use typed answer',
                onPressed: enabled ? submitTyped : null,
                icon: const Icon(Icons.arrow_upward_rounded, color: color),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: enabled ? repeatQuestion : null,
              child: const Text(
                'Repeat question',
                style: TextStyle(color: color),
              ),
            ),
            TextButton(
              onPressed: enabled
                  ? () => skip(
                      reason: numeric ? 'Not measured' : 'Not available',
                      source: 'manual',
                    )
                  : null,
              child: Text(
                target == null
                    ? 'Skip summary'
                    : numeric
                    ? 'Not measured'
                    : 'Not available / skip',
                style: const TextStyle(color: color),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const white = Color(0xfff3f6ff), soft = Color(0xffa9b9d2);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final compact =
        field != null || reviewing || MediaQuery.sizeOf(context).height < 700;
    final title = phase == _Phase.complete
        ? 'Draft ready.\nOver to you.'
        : phase == _Phase.paused
        ? 'Take your time.'
        : reviewing
        ? 'Added to your draft.'
        : addingSummary
        ? spoken
        : narrativeTurn
        ? 'Let’s finish your\nvisit together.'
        : spoken;
    return PopScope(
      canPop:
          !working &&
          phase != _Phase.saving &&
          !reviewSpeaking &&
          pendingWrite == null,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Theme(
          data: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xff7bacff),
              surface: Color(0xff11233b),
              onSurface: white,
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff3478f6),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          child: Scaffold(
            backgroundColor: const Color(0xff061324),
            body: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.35),
                  radius: 1.1,
                  colors: [
                    Color(0xff102d4e),
                    Color(0xff061324),
                    Color(0xff040e1b),
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 10, 16, 8),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: phase == _Phase.paused
                                  ? soft
                                  : const Color(0xff65e1b5),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            phase == _Phase.paused ? 'Paused' : 'Voice AI',
                            style: const TextStyle(
                              color: white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          if (widget.audio is NoiseControlledVoiceAudio)
                            IconButton(
                              tooltip:
                                  (widget.audio as NoiseControlledVoiceAudio)
                                      .noiseReduction
                                  ? 'Noise reduction on · Tap to turn off'
                                  : 'Reduce background noise',
                              onPressed: phase == _Phase.saving
                                  ? null
                                  : toggleNoiseReduction,
                              icon: Icon(
                                Icons.noise_control_off,
                                color:
                                    (widget.audio as NoiseControlledVoiceAudio)
                                        .noiseReduction
                                    ? const Color(0xff65e1b5)
                                    : soft,
                              ),
                            ),
                          IconButton(
                            tooltip: 'Close voice assistant',
                            onPressed: phase == _Phase.saving ? null : close,
                            icon: const Icon(Icons.close_rounded, color: soft),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                0.0,
                                constraints.maxHeight - 20,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  widget.jobTitle,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: soft,
                                    fontSize: 12,
                                    letterSpacing: .3,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                RepaintBoundary(
                                  child: VoiceLight(
                                    active:
                                        working ||
                                        reviewSpeaking ||
                                        listening != null,
                                    listening: listening != null,
                                    level: level,
                                    height: compact ? 124 : 220,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    status.toUpperCase(),
                                    style: const TextStyle(
                                      color: Color(0xff8caefa),
                                      fontSize: 10,
                                      letterSpacing: 2,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: white,
                                    fontSize: narrativeTurn && !reviewing
                                        ? 28
                                        : 23,
                                    height: 1.3,
                                    letterSpacing: -.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (!reviewing && field == null)
                                  Text(
                                    switch (phase) {
                                      _Phase.listening =>
                                        narrativeTurn
                                            ? 'Tell me what you did, what you tested,\nand what still needs attention.'
                                            : 'Speak naturally. I’m listening.',
                                      _Phase.understanding =>
                                        'Matching your words to the report…',
                                      _Phase.complete =>
                                        'Say open draft to add evidence and review your closure.',
                                      _Phase.paused =>
                                        'Say resume when you’re ready. Your draft answers are saved.',
                                      _ =>
                                        'I’ll speak first, then open the microphone.',
                                    },
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: soft,
                                      fontSize: 15,
                                      height: 1.6,
                                    ),
                                  ),
                                if (!reviewing && phase != _Phase.complete) ...[
                                  const SizedBox(height: 24),
                                  if (transcript.isNotEmpty) ...[
                                    Text(
                                      'I heard: “$transcript”',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: soft,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  answerChoices(),
                                ],
                                if (reviewing) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: .055,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: .08,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'YOUR WORDS',
                                          style: TextStyle(
                                            color: soft,
                                            fontSize: 10,
                                            letterSpacing: 1.6,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '“$transcript”',
                                          style: const TextStyle(
                                            color: white,
                                            fontSize: 16,
                                            height: 1.5,
                                          ),
                                        ),
                                        if (!reviewNarrative) ...[
                                          const Divider(
                                            height: 28,
                                            color: Color(0xff2b405d),
                                          ),
                                          Text(
                                            field!.label,
                                            style: const TextStyle(
                                              color: soft,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            answer == null
                                                ? 'Needs clarification in the form'
                                                : field!.display(answer),
                                            style: const TextStyle(
                                              color: white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (reviewNarrative) ...[
                                    const SizedBox(height: 20),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'SUGGESTED DETAILS · ${facts.length}',
                                        style: const TextStyle(
                                          color: soft,
                                          fontSize: 10,
                                          letterSpacing: 1.4,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    for (final fact in facts)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: Icon(
                                          fact.answer == null
                                              ? Icons.help_outline
                                              : Icons.check_rounded,
                                          color: soft,
                                        ),
                                        title: Text(
                                          fact.field.label,
                                          style: const TextStyle(
                                            color: soft,
                                            fontSize: 12,
                                          ),
                                        ),
                                        subtitle: Text(
                                          fact.answer == null
                                              ? 'Unclear — check in the form'
                                              : fact.field.display(fact.answer),
                                          style: const TextStyle(
                                            color: white,
                                            fontSize: 15,
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    const Text(
                                      'Added to your draft. Review the closure before submitting.',
                                      style: TextStyle(
                                        color: soft,
                                        fontSize: 12,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ],
                                if (error.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 18),
                                    child: Text(
                                      error,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xffffc9c5),
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (keyboard)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Voice paused while typing',
                                style: TextStyle(color: soft, fontSize: 12),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: repeatQuestion,
                              icon: const Icon(Icons.mic_rounded),
                              label: const Text('Use voice'),
                            ),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (phase == _Phase.complete)
                              FilledButton.icon(
                                onPressed: resettingAnswers ? null : close,
                                icon: const Icon(Icons.fact_check_outlined),
                                label: const Text('Open my draft'),
                              )
                            else if (phase == _Phase.paused)
                              TextButton.icon(
                                onPressed: resume,
                                icon: const Icon(Icons.mic_rounded),
                                label: const Text('Resume conversation'),
                              )
                            else
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _VoiceControl(
                                    icon: Icons.article_outlined,
                                    label: 'Open draft',
                                    onPressed: phase == _Phase.saving
                                        ? null
                                        : close,
                                  ),
                                  _VoiceControl(
                                    icon: listening == _Listen.answer
                                        ? Icons.mic_rounded
                                        : Icons.graphic_eq_rounded,
                                    label: listening == _Listen.answer
                                        ? 'Auto listening'
                                        : 'Voice active',
                                    primary: true,
                                    onPressed: null,
                                  ),
                                  _VoiceControl(
                                    icon: Icons.pause_rounded,
                                    label: 'Pause',
                                    onPressed: phase == _Phase.saving
                                        ? null
                                        : () => pause(),
                                  ),
                                ],
                              ),
                            if (phase == _Phase.complete &&
                                widget.resetAnswers != null)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: soft,
                                ),
                                onPressed: resettingAnswers
                                    ? null
                                    : resetConversation,
                                icon: const Icon(Icons.restart_alt_rounded),
                                label: const Text('Reset answers'),
                              ),
                            const SizedBox(height: 12),
                            const Text(
                              'Say repeat, skip, pause or open draft',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: soft, fontSize: 12),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              savedTurns == 0
                                  ? 'Your voice stays on this phone'
                                  : '$savedTurns ${savedTurns == 1 ? 'answer' : 'answers'} saved · Voice stays on this phone',
                              style: const TextStyle(
                                color: Color(0xff7187a4),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceControl extends StatelessWidget {
  const _VoiceControl({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Container(
          width: primary ? 74 : 52,
          height: primary ? 74 : 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: primary ? const Color(0xff2877ff) : const Color(0xff18283d),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: const Color(0xff2274ff).withValues(alpha: .4),
                      blurRadius: 30,
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: IconButton(
            onPressed: onPressed,
            tooltip: label,
            icon: Icon(icon, size: primary ? 32 : 23, color: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(color: Color(0xffa9b9d2), fontSize: 11),
        ),
      ],
    ),
  );
}

/// Code-native light and waveform, with no video or additional model assets.
class VoiceLight extends StatefulWidget {
  const VoiceLight({
    super.key,
    this.active = false,
    this.listening = false,
    this.level = 0,
    this.height = 180,
  });
  final bool active, listening;
  final double level, height;
  @override
  State<VoiceLight> createState() => _VoiceLightState();
}

class _VoiceLightState extends State<VoiceLight>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(VoiceLight oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  void sync() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!animation.isAnimating) animation.repeat();
    } else {
      animation.stop();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, _) => CustomPaint(
          painter: _VoiceLightPainter(
            animation.value,
            widget.active,
            widget.listening,
            widget.level,
          ),
        ),
      ),
    ),
  );
}

class _VoiceLightPainter extends CustomPainter {
  _VoiceLightPainter(this.time, this.active, this.listening, this.level);
  final double time, level;
  final bool active, listening;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * .35);
    final radius = size.height * .21;
    final pulse = active ? 1 + .07 * math.sin(time * math.pi * 2) : 1.0;
    final r = radius * pulse;
    canvas.drawCircle(
      center,
      r * 1.5,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xff3886ff).withValues(alpha: .35),
            const Color(0xff1268e5).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r * 1.5)),
    );
    final star = Path()
      ..moveTo(center.dx, center.dy - r)
      ..cubicTo(
        center.dx + r * .24,
        center.dy - r * .23,
        center.dx + r * .23,
        center.dy - r * .24,
        center.dx + r,
        center.dy,
      )
      ..cubicTo(
        center.dx + r * .23,
        center.dy + r * .24,
        center.dx + r * .24,
        center.dy + r * .23,
        center.dx,
        center.dy + r,
      )
      ..cubicTo(
        center.dx - r * .24,
        center.dy + r * .23,
        center.dx - r * .23,
        center.dy + r * .24,
        center.dx - r,
        center.dy,
      )
      ..cubicTo(
        center.dx - r * .23,
        center.dy - r * .24,
        center.dx - r * .24,
        center.dy - r * .23,
        center.dx,
        center.dy - r,
      )
      ..close();
    canvas.drawPath(
      star,
      Paint()
        ..color = const Color(0xff347fff)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      star,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xfff5fcff), Color(0xffb1e5ff), Color(0xff4084ff)],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
    final y = size.height * .84,
        spacing = math.min(6.0, size.width / 47),
        waveWidth = spacing * 44;
    for (var i = 0; i < 45; i++) {
      final x = size.width / 2 - waveWidth / 2 + i * spacing,
          normalized = i / 44;
      final envelope = math.pow(math.sin(normalized * math.pi), 1.6).toDouble();
      final amplitude = active
          ? (listening ? .2 + (level * 8).clamp(0, 1) : .65)
          : .12;
      final ripple = .3 + .7 * math.sin(i * .83 - time * math.pi * 4).abs();
      final h = 2 + size.height * .13 * envelope * ripple * amplitude;
      final color = Color.lerp(
        const Color(0xff52d9ff),
        const Color(0xfff29cd9),
        normalized,
      )!;
      final path = Path()
        ..moveTo(x, y - h)
        ..lineTo(x, y + h);
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: .45)
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceLightPainter oldDelegate) =>
      time != oldDelegate.time ||
      active != oldDelegate.active ||
      level != oldDelegate.level ||
      listening != oldDelegate.listening;
}
