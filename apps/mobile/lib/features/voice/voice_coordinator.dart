import 'dart:async';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import '../../core/contracts.dart';
import 'conversation.dart';
import 'field_extraction.dart';
import 'patch_rules.dart';
import 'spoken_numbers.dart';
import 'voice_audio.dart';

enum VoiceState {
  idle,
  preparingSpeech,
  listening,
  transcribing,
  extracting,
  saving,
  needsClarification,
  speaking,
  paused,
  readyToReview,
  error,
}

class VoiceCoordinator extends ChangeNotifier {
  VoiceCoordinator({
    required this.engine,
    required this.schema,
    required this.readValues,
    required this.onPatch,
    this.playback = true,
    this.speed = 1,
    SpeechSynthesizer? speech,
    VoiceAudio? audio,
    this.echoTail = const Duration(milliseconds: 180),
  }) : speech = speech ?? engine,
       audio = audio ?? DeviceVoiceAudio();
  final FieldVoice engine;
  final SpeechSynthesizer speech;
  final VoiceAudio audio;
  final FormDefinition schema;
  final Answers Function() readValues;
  final Future<void> Function(PatchResult, String source) onPatch;
  final bool playback;
  final double speed;
  final Duration echoTail;
  VoiceState state = VoiceState.idle;
  String transcript = '',
      question = '',
      error = '',
      savedMessage = '',
      savedFieldLabel = '';
  List<String> changed = [];
  // Durations/counts only: never audio or dictated/report text in diagnostics.
  final Map<String, int> lastTurnMetrics = {};
  FieldDefinition? activeField;
  double level = 0;
  final _pcm = BytesBuilder(copy: false);
  final _attempts = <String, int>{};
  final _skipped = <String>{};
  Future<void>? _activeTurn, _activeSave;
  bool _finishRequested = false;
  Timer? _limit;
  int _generation = 0, _emptyTurns = 0;
  bool _disposed = false;
  bool awaitingPermission = false;
  PatchResult? _pending;
  Answer? _numericSuggestion;
  Answer? get numericSuggestion => _numericSuggestion;
  String get suggestedValue => activeField?.display(_numericSuggestion) ?? '';
  String _pendingSource = 'voice';
  bool get hasUnsavedAnswer => _pending != null;
  List<FieldDefinition> get voiceFields =>
      schema.visibleFields(readValues()).where((f) => f.voiceEnabled).toList();
  bool _needsValue(FieldDefinition f) =>
      missing(readValues()[f.id]) ||
      validate(schema, readValues()).issues.any((i) => i.fieldId == f.id);
  int get answeredCount => voiceFields.where((f) => !_needsValue(f)).length;
  List<FieldDefinition> get remainingFields =>
      schema.visibleFields(readValues()).where(_needsValue).toList();
  List<FieldDefinition> get touchFields => remainingFields
      .where(
        (f) => f.required && (!f.voiceEnabled || (_attempts[f.id] ?? 0) >= 2),
      )
      .toList();
  Map<String, String> get savedValues => {
    for (final id in changed)
      schema.fields.firstWhere((f) => f.id == id).label: schema.fields
          .firstWhere((f) => f.id == id)
          .display(readValues()[id]),
  };
  FieldDefinition? _next(List<String> unresolved) => nextQuestion(
    schema,
    readValues(),
    unresolved,
    _attempts,
    skipped: _skipped,
  );
  bool get processing => [
    VoiceState.preparingSpeech,
    VoiceState.transcribing,
    VoiceState.extracting,
    VoiceState.saving,
  ].contains(state);
  bool get canChoose =>
      activeField != null &&
      ![
        VoiceState.transcribing,
        VoiceState.extracting,
        VoiceState.saving,
      ].contains(state) &&
      !hasUnsavedAnswer;
  String get label => awaitingPermission
      ? 'Allow microphone access to answer'
      : switch (state) {
          VoiceState.idle => 'Getting ready',
          VoiceState.preparingSpeech => 'Preparing your question',
          VoiceState.listening => 'Listening to you',
          VoiceState.transcribing => 'Hearing your answer',
          VoiceState.extracting => 'Understanding your answer',
          VoiceState.saving => 'Saving on this device',
          VoiceState.needsClarification => 'Your turn',
          VoiceState.speaking => 'Field Assist is speaking',
          VoiceState.paused => 'Conversation paused',
          VoiceState.readyToReview => 'Ready for your review',
          VoiceState.error => 'Let’s try that again',
        };
  void _set(VoiceState value) {
    state = value;
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  /// Opening voice mode speaks first; the microphone opens only after playback.
  Future<void> begin() async {
    if (_disposed || hasUnsavedAnswer) return;
    final generation = ++_generation;
    _finishRequested = false;
    error = '';
    _emptyTurns = 0;
    level = 0;
    activeField = _next([]);
    question = _numericSuggestion != null && activeField != null
        ? _numericConfirmationQuestion()
        : activeField == null
        ? _completionQuestion()
        : spokenQuestion(activeField!);
    try {
      await audio.configure(() => unawaited(pause()));
      if (!_current(generation)) return;
      await _ask(generation, listenAfter: activeField != null);
    } catch (e) {
      _fail(e, generation);
    }
  }

  /// A spoken introduction or touch-entry prompt never opens the microphone.
  Future<void> presentPrompt(String text) async {
    if (_disposed || hasUnsavedAnswer) return;
    await pause();
    final generation = ++_generation;
    _finishRequested = false;
    activeField = null;
    question = text;
    savedMessage = savedFieldLabel = transcript = '';
    changed = [];
    try {
      await audio.configure(() => unawaited(pause()));
      if (_current(generation)) await _ask(generation, listenAfter: false);
    } catch (e) {
      _fail(e, generation);
    }
  }

  String _numericConfirmationQuestion() =>
      'You gave an approximate value. Should I record $suggestedValue for ${activeField!.label.toLowerCase()}? Say yes to confirm, or no to answer again.';

  String _completionQuestion() {
    if (touchFields.isNotEmpty) {
      return 'Your spoken answers are saved. Complete ${touchFields.map((f) => f.label).join(', ')} in the form, then review your report.';
    }
    return validate(schema, readValues()).valid
        ? 'Your answers are saved. Review and confirm your report when you are ready.'
        : 'Your spoken answers are saved. Complete the remaining fields by touch, then review your report.';
  }

  Future<void> _ask(int generation, {required bool listenAfter}) async {
    if (!_current(generation)) return;
    if (_finishRequested) {
      _set(VoiceState.paused);
      return;
    }
    if (playback) {
      _set(VoiceState.preparingSpeech);
      if (savedMessage.isNotEmpty) {
        final acknowledgment = await speech.synthesize('Saved.', speed: speed);
        if (!_current(generation) || _finishRequested) return;
        _set(VoiceState.speaking);
        if (!await audio.play(acknowledgment, (_) {}) ||
            !_current(generation) ||
            _finishRequested) {
          return;
        }
        _set(VoiceState.preparingSpeech);
      }
      final synthesis = Stopwatch()..start();
      final spoken = await speech.synthesize(question, speed: speed);
      lastTurnMetrics['questionPreparationMs'] = synthesis.elapsedMilliseconds;
      if (!_current(generation) || _finishRequested) return;
      _set(VoiceState.speaking);
      final completed = await audio.play(spoken, (value) {
        if (_current(generation)) {
          level = value;
          notifyListeners();
        }
      });
      if (!_current(generation) || !completed) return;
      level = 0;
      if (listenAfter) await Future<void>.delayed(echoTail);
    }
    if (!_current(generation)) return;
    if (_finishRequested) return;
    if (listenAfter) {
      await _listen(generation);
    } else {
      _set(
        validate(schema, readValues()).valid
            ? VoiceState.readyToReview
            : VoiceState.needsClarification,
      );
    }
  }

  Future<void> start() async {
    if (_disposed ||
        hasUnsavedAnswer ||
        [
          VoiceState.transcribing,
          VoiceState.extracting,
          VoiceState.saving,
        ].contains(state)) {
      return;
    }
    final generation = ++_generation;
    _finishRequested = false;
    try {
      await audio.stopPlayback();
      await _listen(generation);
    } catch (e) {
      _fail(e, generation);
    }
  }

  Future<void> _listen(int generation) async {
    awaitingPermission = true;
    _set(VoiceState.needsClarification);
    bool allowed;
    try {
      allowed = await audio.hasPermission();
    } finally {
      awaitingPermission = false;
    }
    if (!allowed) {
      throw StateError(
        'Allow microphone access to answer by voice, or use the options and form by touch. Your saved answers are safe.',
      );
    }
    if (!_current(generation)) return;
    _pcm.clear();
    error = '';
    level = 0;
    final endpoint = TurnEndpoint(
      silence: Duration(
        milliseconds:
            [
              FieldKind.shortText,
              FieldKind.longText,
            ].contains(activeField?.kind)
            ? 1500
            : 1300,
      ),
    );
    var capturedTime = Duration.zero;
    await audio.capture(
      onBytes: (bytes) {
        if (_current(generation)) _pcm.add(bytes);
      },
      onLevel: (value) {
        if (!_current(generation) || state != VoiceState.listening) return;
        level = value;
        capturedTime += const Duration(milliseconds: 20);
        notifyListeners();
        if (endpoint.observe(value, capturedTime)) {
          unawaited(finish(noSpeech: !endpoint.heardSpeech));
        }
      },
      onError: (e) {
        if (_current(generation)) {
          unawaited(pause());
          error = 'Microphone capture stopped. Your saved answers are safe.';
          _set(VoiceState.error);
        }
      },
    );
    if (!_current(generation)) {
      await audio.stopCapture();
      return;
    }
    _set(VoiceState.listening);
    _limit?.cancel();
    _limit = Timer(const Duration(seconds: 20), () => unawaited(finish()));
  }

  Future<void> finish({bool noSpeech = false}) {
    if (_activeTurn != null) return _activeTurn!;
    if (state != VoiceState.listening) return Future.value();
    final turn = _finish(noSpeech: noSpeech);
    _activeTurn = turn;
    return turn.whenComplete(() {
      if (identical(_activeTurn, turn)) _activeTurn = null;
    });
  }

  Future<void> _finish({bool noSpeech = false}) async {
    if (state != VoiceState.listening) return;
    final generation = _generation;
    _set(VoiceState.transcribing);
    _limit?.cancel();
    level = 0;
    try {
      await audio.stopCapture();
      if (!_current(generation)) return;
      final bytes = _pcm.takeBytes();
      if (noSpeech || bytes.length < 2) {
        await _notHeard(generation);
        return;
      }
      final data = ByteData.sublistView(bytes),
          pcm = Float32List(bytes.length ~/ 2);
      for (var i = 0; i < pcm.length; i++) {
        pcm[i] = data.getInt16(i * 2, Endian.little) / 32768;
      }
      // Preserve the full captured utterance, including quiet negation and
      // word endings. Energy-based cropping regressed recognition in 2014.
      final input = pcm;
      lastTurnMetrics
        ..clear()
        ..['capturedSamples'] = pcm.length
        ..['recognitionSamples'] = input.length;
      final recognition = Stopwatch()..start();
      final heard = await engine.transcribe(input);
      lastTurnMetrics['recognitionMs'] = recognition.elapsedMilliseconds;
      if (!_current(generation)) return;
      if (heard.trim().isEmpty) {
        await _notHeard(generation);
        return;
      }
      transcript = heard;
      savedMessage = '';
      savedFieldLabel = '';
      _emptyTurns = 0;
      final known = readValues(), field = activeField;
      if (field != null && _numericSuggestion != null) {
        final confirmation = heard
            .toLowerCase()
            .replaceAll(RegExp(r'[.!?]'), '')
            .trim();
        if ([
          'yes',
          'yes please',
          'yes confirm',
          'correct',
          'confirm',
          'use it',
          'record it',
          "that's right",
          'that is correct',
        ].contains(confirmation)) {
          await _acceptNumericSuggestion('voice', generation);
          return;
        }
        if ([
          'no',
          'no thanks',
          'try again',
          'answer again',
          'incorrect',
        ].contains(confirmation)) {
          _numericSuggestion = null;
          question = spokenQuestion(field);
          await _ask(generation, listenAfter: true);
          return;
        }
        if (directNumericAnswer(field, heard) == null &&
            approximateNumericAnswer(field, heard) == null) {
          question = _numericConfirmationQuestion();
          await _ask(generation, listenAfter: true);
          return;
        }
        _numericSuggestion = null;
      }
      final estimate = field == null
          ? null
          : approximateNumericAnswer(field, heard);
      if (field != null &&
          estimate != null &&
          !validate(schema, {
            ...known,
            field.id: estimate,
          }, requireComplete: false).issues.any((i) => i.fieldId == field.id)) {
        _numericSuggestion = estimate;
        changed = [];
        question = _numericConfirmationQuestion();
        await _ask(generation, listenAfter: true);
        return;
      }
      final direct = field == null
          ? null
          : directSpokenAnswer(field, transcript);
      if (field != null && isCompletionQuestion(field) && direct == null) {
        // Completion is consequential. An unrelated ASR result such as
        // "excellent" must never be reinterpreted as successful completion.
        await _commit(PatchResult(known, [], [field.id]), 'voice', generation);
        return;
      }
      _set(VoiceState.extracting);
      final extraction = Stopwatch()..start();
      final output = direct != null
          ? <String, dynamic>{
              'confidence': 1.0,
              'function_calls': [
                {
                  'name': 'record_fields',
                  'arguments': {field!.id: direct.toJson()},
                },
              ],
            }
          : await extractFormFields(
              engine,
              schema,
              transcript,
              question: field?.question ?? question,
              knownValues: known,
              focusedFieldId: field?.id,
            );
      lastTurnMetrics['extractionMs'] = extraction.elapsedMilliseconds;
      if (!_current(generation)) return;
      final patch = mergeExtraction(
        schema,
        known,
        output,
        transcript,
        manualFields: known.keys.toSet(),
      );
      await _commit(patch, 'voice', generation);
    } catch (e) {
      _fail(e, generation);
    }
  }

  /// Ending a conversation finishes captured/in-flight speech before leaving.
  /// Pause remains an explicit interruption and may discard the current turn.
  Future<void> finishAndPause() async {
    _finishRequested = true;
    if ([VoiceState.preparingSpeech, VoiceState.speaking].contains(state)) {
      await pause();
      return;
    }
    if (state == VoiceState.listening) await finish();
    await _activeTurn;
    try {
      await _activeSave;
    } catch (_) {
      // The pending patch remains available for Retry or explicit discard.
    }
    await pause();
  }

  Future<void> skipOptional() async {
    final field = activeField;
    if (field == null || field.required || !canChoose || _finishRequested) {
      return;
    }
    final generation = ++_generation;
    _limit?.cancel();
    engine.cancel();
    await audio.stopCapture();
    await audio.stopPlayback();
    if (!_current(generation)) return;
    _skipped.add(field.id);
    _numericSuggestion = null;
    activeField = _next([]);
    transcript = savedMessage = savedFieldLabel = '';
    changed = [];
    question = activeField == null
        ? _completionQuestion()
        : spokenQuestion(activeField!);
    await _ask(generation, listenAfter: activeField != null);
  }

  Future<void> confirmNumericSuggestion() async {
    if (_numericSuggestion == null || !canChoose || _finishRequested) return;
    final generation = ++_generation;
    engine.cancel();
    _limit?.cancel();
    try {
      await audio.stopCapture();
      await audio.stopPlayback();
      if (_current(generation)) {
        await _acceptNumericSuggestion('manual', generation);
      }
    } catch (e) {
      _fail(e, generation);
    }
  }

  Future<void> _acceptNumericSuggestion(String source, int generation) async {
    final field = activeField, answer = _numericSuggestion;
    if (field == null || answer == null) return;
    final patch = mergeExtraction(
      schema,
      readValues(),
      {
        'confidence': 1.0,
        'function_calls': [
          {
            'name': 'record_fields',
            'arguments': {field.id: answer.toJson()},
          },
        ],
      },
      'Explicitly change ${field.label} to the confirmed value',
    );
    _numericSuggestion = null;
    await _commit(patch, source, generation);
  }

  Future<void> rejectNumericSuggestion() async {
    if (_numericSuggestion == null || !canChoose || _finishRequested) return;
    _numericSuggestion = null;
    question = spokenQuestion(activeField!);
    final generation = ++_generation;
    engine.cancel();
    _limit?.cancel();
    try {
      await audio.stopCapture();
      await audio.stopPlayback();
      await _ask(generation, listenAfter: true);
    } catch (e) {
      _fail(e, generation);
    }
  }

  Future<void> _notHeard(int generation) async {
    _emptyTurns++;
    question = _emptyTurns >= 2
        ? 'I could not hear an answer. Tap an option or return to the form when you are ready.'
        : 'I did not catch that. ${activeField == null ? 'Please try again.' : spokenQuestion(activeField!)}';
    await _ask(generation, listenAfter: _emptyTurns < 2);
  }

  Future<void> choose(Choice choice) async {
    final field = activeField;
    if (!canChoose ||
        field == null ||
        !field.options.any((o) => o.id == choice.id)) {
      return;
    }
    final generation = ++_generation;
    _finishRequested = false;
    _limit?.cancel();
    engine.cancel();
    try {
      await audio.stopCapture();
      await audio.stopPlayback();
      level = 0;
      if (!_current(generation)) return;
      transcript = voiceChoiceLabel(field, choice);
      savedMessage = '';
      savedFieldLabel = '';
      final patch = mergeExtraction(
        schema,
        readValues(),
        {
          'confidence': 1.0,
          'function_calls': [
            {
              'name': 'record_fields',
              'arguments': {field.id: choice.id},
            },
          ],
        },
        'Explicitly change ${field.label}',
        manualFields: const {},
      );
      await _commit(patch, 'manual', generation);
    } catch (e) {
      _fail(e, generation);
    }
  }

  Future<void> _commit(PatchResult patch, String source, int generation) async {
    changed = [];
    savedMessage = '';
    savedFieldLabel = '';
    if (patch.changed.isNotEmpty) {
      _pending = patch;
      _pendingSource = source;
      _set(VoiceState.saving);
      final saveClock = Stopwatch()..start();
      final saving = onPatch(patch, source);
      _activeSave = saving;
      try {
        await saving;
      } finally {
        if (identical(_activeSave, saving)) _activeSave = null;
      }
      _pending = null;
      lastTurnMetrics['saveMs'] = saveClock.elapsedMilliseconds;
      if (!_current(generation)) return;
      changed = patch.changed;
      savedFieldLabel = changed.length == 1
          ? schema.fields.firstWhere((f) => f.id == changed.single).label
          : 'Report fields';
      savedMessage = changed.length == 1
          ? 'Answer saved on this device'
          : '${changed.length} answers saved on this device';
    }
    if (!_current(generation)) return;
    final next = _next(patch.unresolved);
    if (activeField != null && next?.id == activeField!.id) {
      _attempts[activeField!.id] = (_attempts[activeField!.id] ?? 0) + 1;
    }
    activeField = _next(patch.unresolved);
    question = activeField == null
        ? _completionQuestion()
        : '${patch.changed.isEmpty ? 'That answer was not saved yet. ' : ''}${spokenQuestion(activeField!)}';
    await _ask(generation, listenAfter: activeField != null);
  }

  Future<void> retrySave() async {
    final patch = _pending;
    if (patch == null || state == VoiceState.saving) return;
    final generation = ++_generation;
    _finishRequested = false;
    error = '';
    try {
      await _commit(patch, _pendingSource, generation);
    } catch (e) {
      _fail(e, generation);
    }
  }

  void _fail(Object error, int generation) {
    if (_current(generation)) {
      this.error = error.toString();
      level = 0;
      _set(VoiceState.error);
    }
  }

  Future<void> stopSpeaking() => pause();
  Future<void> pause() async {
    _generation++;
    engine.cancel();
    _limit?.cancel();
    level = 0;
    if (!_disposed) _set(VoiceState.paused);
    await audio.stopCapture();
    await audio.stopPlayback();
    _pcm.clear();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    await pause();
    await audio.close();
    transcript = '';
    super.dispose();
  }
}
