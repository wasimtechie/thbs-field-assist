import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../forms/form_screen.dart' show AnswerInput;
import '../time_tracking/site_time_card.dart';
import '../voice/prompt_audio_cache.dart';
import '../voice/voice_audio.dart';
import 'compact_narrative.dart';
import '../voice/speech_repair.dart';
import 'closure_speech.dart';
import 'closure_voice_assistant.dart';
import 'closure_voice_turn.dart';
import 'question_voice.dart';
import 'structured_visit_extraction.dart';
import 'optical_reading.dart';
import 'transcript_editor.dart';

const compactClosureLabels = {
  'actual_work': 'Work done',
  'claimed_outcome': 'Visit outcome',
  'optical_rx_dbm': 'Optical reading (dBm)',
  'operational_test': 'Test result',
  'next_action': 'Follow-up / next action',
};

/// Expanded S1 demo fields. These remain proposed visit facts, separate from
/// the full operational closure policy and its evidence requirements.
const provisionClosureLabels = {
  'actual_work': 'Work done',
  'claimed_outcome': 'Visit outcome',
  'access_permission': 'Customer access permission',
  'location_agreed': 'ONT location approved',
  'drop_route': 'Fibre route',
  'external_connection': 'External fibre / connection point installed',
  'internal_fibre': 'Internal fibre fitted to ONT',
  'ont_fitted': 'ONT installed',
  'ont_status_checked': 'ONT power and status checked',
  'optical_rx_dbm': 'Optical reading (dBm)',
  'operational_test': 'Test result',
  'service_live': 'Service live',
  'customer_handover': 'Customer shown the equipment',
  'site_handover_safe': 'Site left safe and tidy',
  'next_action': 'Follow-up / next action',
};

const provisionClosureQuestions = {
  'access_permission': 'Did the customer grant access for this visit?',
  'location_agreed': 'Did the customer approve the ONT location?',
  'drop_route':
      'Which fibre route did you use: existing, underground, or overhead?',
  'external_connection':
      'Did you install the external fibre and connection point?',
  'internal_fibre': 'Did you fit the internal fibre to the ONT?',
  'ont_fitted': 'Did you install the ONT?',
  'ont_status_checked': 'Did you check the ONT power and status?',
  'service_live': 'Is the service live and the customer online?',
  'customer_handover': 'Did you show the customer the equipment?',
  'site_handover_safe': 'Did you leave the site safe and tidy?',
  'next_action': 'Is any follow-up work required?',
};

Map<String, String> summaryReceiptLabels(Json values) => {
  for (final entry in provisionClosureLabels.entries)
    if (compactClosureLabels.containsKey(entry.key) ||
        values.containsKey(entry.key))
      entry.key: entry.value,
};

/// A local presentation summary, deliberately separate from operational closure.
/// Removing questions here must never satisfy the full closure policy.
FormDefinition compactClosureForm(
  FormDefinition full, {
  bool expanded = false,
}) => FormDefinition.fromJson({
  ...full.source,
  'title': 'Visit summary',
  'closurePolicy': null,
  'sections': [
    {'id': 'summary', 'label': 'Visit summary', 'order': 0},
  ],
  'fields': [
    for (final entry
        in (expanded ? provisionClosureLabels : compactClosureLabels).entries)
      {
        ...full.fields.firstWhere((f) => f.id == entry.key).source,
        'sectionId': 'summary',
        'order': (expanded ? provisionClosureLabels : compactClosureLabels).keys
            .toList()
            .indexOf(entry.key),
        'label': entry.value,
        if (expanded && provisionClosureQuestions.containsKey(entry.key))
          'voice': {
            ...full.fields.firstWhere((f) => f.id == entry.key).source['voice']
                as Json,
            'question': provisionClosureQuestions[entry.key],
          },
        'activation': null,
        'condition': null,
        'required': ['actual_work', 'claimed_outcome'].contains(entry.key),
        if (entry.key == 'claimed_outcome')
          'options': [
            {'id': 'completed', 'label': 'Work completed'},
            {'id': 'partial', 'label': 'Partially completed'},
            {'id': 'blocked', 'label': 'Blocked'},
            {'id': 'referred', 'label': 'Referral required'},
            {'id': 'hold', 'label': 'On hold'},
            {'id': 'stage_completed', 'label': 'Stage completed'},
            {'id': 'network_ready', 'label': 'Network ready (reported)'},
          ],
      },
  ],
});

class CompactClosureScreen extends ConsumerStatefulWidget {
  const CompactClosureScreen({
    super.key,
    required this.reportId,
    required this.fullChecklist,
  });
  final String reportId;
  final Widget Function() fullChecklist;
  @override
  ConsumerState<CompactClosureScreen> createState() =>
      _CompactClosureScreenState();
}

class _CompactClosureScreenState extends ConsumerState<CompactClosureScreen> {
  LocalReport? report;
  late FormDefinition form;
  Answers values = {};
  Json sources = {};
  Future<void> tail = Future.value();
  PromptAudioCache? speech;
  String speechSettingsKey = '';
  String error = '', saveStatus = 'Saved on this device';
  String? reviewedAt;
  bool manual = false,
      openingVoice = false,
      resetting = false,
      reviewing = false;
  int revision = 0, writeSerial = 0;
  bool allowsField(String id) => form.fields.any((f) => f.id == id);
  Timer? summaryTimer;
  int summaryMapping = 0;
  bool get needsReadingConfirmation =>
      sources['optical_rx_dbm']?['requiresConfirmation'] == true &&
      !missing(values['optical_rx_dbm']);

  final automaticRevisions = <String, int>{};
  String? editingField;
  bool get hasSpokenWords => sources.values.any(
    (s) =>
        s is Map && (s['sourceType'] == 'speech' || s['originalSpeech'] is Map),
  );

  String get metadataKey => 'closure-demo-summary:${widget.reportId}';

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final app = ref.read(appProvider.notifier);
      await app.assertAccess();
      final draft = await app.repository.get(widget.reportId);
      final saved = await app.repository.metadata(metadataKey) as Json?;
      if (!mounted) return;
      if (saved != null) {
        app.cacheSummaryDraft(widget.reportId, saved, ownerId: draft.ownerId);
      }
      setState(() {
        report = draft;
        form = compactClosureForm(
          draft.schema,
          // Assigned S1 visits use the expanded demonstration. Standalone
          // summaries and other scenarios retain their existing short form.
          expanded:
              draft.workOrderId != null &&
              draft.values['scenario']?.toJson() == 'S1',
        );
        final previous =
            saved?['values'] as Json? ?? encodeAnswers(draft.values);
        values = decodeAnswers({
          for (final id in form.fields.map((f) => f.id))
            if (previous.containsKey(id)) id: previous[id],
        });
        sources = {
          for (final entry in (saved?['sources'] as Json? ?? {}).entries)
            if (allowsField(entry.key)) entry.key: entry.value,
        };
        reviewedAt = saved?['reviewedAt'] as String?;
      });
      scheduleSummaryMapping(immediate: true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unlock the workspace and reopen this summary.');
      }
    }
  }

  Future<void> save(
    Answers next, {
    Json? nextSources,
    String? reviewTime,
  }) async {
    next = {
      for (final entry in next.entries)
        if (allowsField(entry.key)) entry.key: entry.value,
    };
    final retainedSources = {
      for (final entry in (nextSources ?? sources).entries)
        if (allowsField(entry.key)) entry.key: entry.value,
    };
    final serial = ++writeSerial;
    setState(() {
      values = {...next};
      sources = retainedSources;
      reviewedAt = reviewTime;
      saveStatus = 'Saving…';
      error = '';
    });
    final snapshot = <String, dynamic>{
      'formatVersion': 1,
      // Preserve the storage discriminator used by existing downloaded drafts.
      'kind': 'six-field-demo-summary',
      'fieldIds': form.fields.map((f) => f.id).toList(),
      'reportId': widget.reportId,
      'values': encodeAnswers(next),
      'sources': {...sources},
      'reviewedAt': reviewTime,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'operationalClosureApproved': false,
    };
    final app = ref.read(appProvider.notifier),
        owner = ref.read(appProvider).user?.id;
    final operation = tail.catchError((_) {}).then((_) async {
      if (owner == null) throw StateError('Workspace changed');
      // The captured snapshot belongs to the workspace, not this route's life.
      // Navigating to Reports must not cancel an already accepted edit.
      await app.saveSummaryDraft(widget.reportId, snapshot, ownerId: owner);
    });
    tail = operation;
    try {
      await operation;
      if (mounted && serial == writeSerial) {
        setState(() => saveStatus = 'Saved on this device');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = 'Could not save. Unlock and retry before leaving.';
          saveStatus = 'Retry required';
        });
      }
      rethrow;
    }
  }

  Future<void> change(FieldDefinition field, Answer? value) async {
    try {
      await save(
        {...values, field.id: value},
        nextSources: {
          ...sources,
          field.id: {
            'sourceType': 'manual',
            'sourceSpan': field.display(value),
          },
        },
      );
      if (field.id == 'actual_work') scheduleSummaryMapping();
    } catch (_) {
      /* The draft and retry message stay visible. */
    }
  }

  Future<void> editSpokenWords() async {
    if (openingVoice || resetting || !hasSpokenWords) return;
    summaryTimer?.cancel();
    final serial = ++summaryMapping;
    await tail;
    if (!mounted) return;
    final owner = ref.read(appProvider).user?.id;
    final target = await showModalBottomSheet<FieldDefinition>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Which spoken words would you like to edit?'),
              ),
              for (final field in form.fields)
                if (sources[field.id] is Map &&
                    (sources[field.id]['sourceType'] == 'speech' ||
                        sources[field.id]['originalSpeech'] is Map))
                  ListTile(
                    title: Text(field.label),
                    subtitle: Text(
                      '${sources[field.id]['sourceSpan'] ?? ''}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => Navigator.pop(sheetContext, field),
                  ),
            ],
          ),
        ),
      ),
    );
    if (target == null || !mounted) return;
    final previous = Map<String, dynamic>.from(sources[target.id] as Map);
    final text =
        previous['sourceSpan'] as String? ?? target.display(values[target.id]);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TranscriptEditor(
          label: target.label,
          text: text,
          save: (edited) async {
            final app = ref.read(appProvider.notifier);
            await app.assertAccess();
            bool current() =>
                mounted &&
                summaryMapping == serial &&
                ref.read(appProvider).user?.id == owner;
            if (!current()) throw StateError('Workspace changed');
            final trace = <String, dynamic>{
              'sourceType': 'text',
              'inputMethod': 'transcript_edit',
              'sourceSpan': edited,
              'originalSpeech': previous['originalSpeech'] ?? previous,
              'previousTranscript': text,
              'editedAt': DateTime.now().toUtc().toIso8601String(),
              if (previous['question'] != null)
                'question': previous['question'],
            };
            final next = {...values};
            if (target.id == 'actual_work') {
              next[target.id] = TextAnswer(edited);
            } else {
              final facts = await StructuredVisitExtractor(
                app.voice.summaryExtractor,
              ).extract(form, edited, current: current);
              if (!current()) throw StateError('Workspace changed');
              final fact =
                  facts.where((f) => f['fieldId'] == target.id).firstOrNull ??
                  (target.id == 'optical_rx_dbm'
                      ? focusedOpticalFact(edited)
                      : null);
              final answer = fact == null
                  ? closureSpokenAnswer(target, edited)
                  : decodeAnswers({target.id: fact['value']})[target.id];
              next.remove(target.id);
              if (answer != null &&
                  !validateVisitSummary(
                    form,
                    {...next, target.id: answer},
                    requireComplete: false,
                  ).issues.any((i) => i.fieldId == target.id)) {
                next[target.id] = answer;
              }
              if (fact != null) {
                trace.addAll({
                  ...fact,
                  'sourceType': 'text',
                  'sourceSpan': edited,
                });
              }
            }
            await save(next, nextSources: {...sources, target.id: trace});
            if (target.id == 'actual_work') {
              await fillFromSavedSummary(current: current);
            }
            if (mounted) {
              setState(() {
                manual = true;
                revision++;
              });
            }
          },
        ),
      ),
    );
  }

  void scheduleSummaryMapping({bool immediate = false}) {
    summaryTimer?.cancel();
    final serial = ++summaryMapping;
    final owner = ref.read(appProvider).user?.id;
    summaryTimer = Timer(Duration(milliseconds: immediate ? 0 : 650), () async {
      try {
        await fillFromSavedSummary(
          current: () =>
              mounted &&
              !openingVoice &&
              serial == summaryMapping &&
              ref.read(appProvider).user?.id == owner,
        );
      } catch (_) {
        // The typed summary remains saved; explicit missing questions stay available.
      }
    });
  }

  Future<bool> resetAnswers() async {
    if (resetting) return false;
    setState(() => resetting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reset all answers?'),
          content: const Text(
            'Clear the answers and voice transcript for this visit summary, then start again. The job and full closure checks will be kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep answers'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset answers'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return false;
      summaryTimer?.cancel();
      summaryMapping++;
      await tail.catchError((_) {});
      if (!mounted) return false;
      final previousValues = {...values}, previousSources = {...sources};
      final previousReview = reviewedAt;
      try {
        // Persist an explicit empty snapshot. Removing metadata would restore
        // the original full draft's values when this summary is reopened.
        await save({}, nextSources: {});
      } catch (_) {
        if (mounted) {
          setState(() {
            values = previousValues;
            sources = previousSources;
            reviewedAt = previousReview;
            error =
                'Could not reset. Your previous answers are retained. Retry when the workspace is unlocked.';
            revision++;
          });
        }
        rethrow;
      }
      if (!mounted) return true;
      setState(() {
        manual = false;
        revision++;
        saveStatus = 'Answers reset · Ready to start again';
      });
      return true;
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

  Future<void> voice() async {
    if (openingVoice) return;
    summaryTimer?.cancel();
    summaryMapping++;
    if (!ref.read(appProvider).voiceReady) {
      setState(
        () => error = 'Prepare the offline voice package in Profile first.',
      );
      await context.push('/settings');
      return;
    }
    setState(() => openingVoice = true);
    final app = ref.read(appProvider.notifier),
        owner = ref.read(appProvider).user?.id;
    Future<void> checkOwner() async {
      await app.assertAccess();
      if (!mounted || ref.read(appProvider).user?.id != owner) {
        throw StateError('Workspace changed');
      }
    }

    try {
      await tail;
      await checkOwner();
      await fillFromSavedSummary(
        current: () => mounted && ref.read(appProvider).user?.id == owner,
      );
      await checkOwner();
      // Cache checked, levelled prompts too; do not queue live synthesis while
      // the same inference worker is needed for the engineer's next answer.
      if (!mounted) return;
      final settings = ref.read(appProvider);
      final voiceKey = '${settings.speechVoiceId}:${settings.speechRate}';
      if (speech == null || speechSettingsKey != voiceKey) {
        speech?.clear();
        app.voice.selectSpeechVoice(settings.speechVoiceId);
        speech = PromptAudioCache(
          QuestionVoice(
            app.voice,
            bundle: DefaultAssetBundle.of(context),
            voiceId: settings.speechVoiceId,
            rate: settings.speechRate,
          ),
        );
        speechSettingsKey = voiceKey;
      }
      final greetingIndex = await app.nextVoiceGreetingIndex();
      if (!mounted) return;
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ClosureVoiceAssistant(
            jobTitle: 'Visit summary',
            greetingIndex: greetingIndex,
            needsNarrative: missing(values['actual_work']),
            recognizer: app.voice,
            synthesizer: speech!,
            announceSavedAnswers: false,
            collectSummaryFirst: true,
            closeWhenComplete: true,
            confirmationFor: (field) =>
                field.id == 'optical_rx_dbm' && needsReadingConfirmation
                ? ClosureVoiceFact(field, sources[field.id] as Json)
                : null,
            rejectConfirmation: (field) async {
              await checkOwner();
              await save(
                {...values}..remove(field.id),
                nextSources: {
                  ...sources,
                  field.id: {
                    ...sources[field.id] as Json,
                    'requiresConfirmation': false,
                    'verificationStatus': 'rejected',
                  },
                },
              );
            },
            isAnswered: (field) =>
                !(field.id == 'optical_rx_dbm' && needsReadingConfirmation) &&
                !missing(values[field.id]) &&
                !validateVisitSummary(
                  form,
                  values,
                  requireComplete: false,
                ).issues.any((i) => i.fieldId == field.id),
            completionPrompt:
                closureAssistantPrompts['assistant_summary_complete'],
            resetAnswers: resetAnswers,
            audio: ref.read(voiceAudioFactoryProvider)(),
            assertAccess: checkOwner,
            cancelInference: app.voice.cancel,
            nextQuestion: (skipped) =>
                needsReadingConfirmation && !skipped.contains('optical_rx_dbm')
                ? form.fields.firstWhere((f) => f.id == 'optical_rx_dbm')
                : form.fields
                      .where(
                        (f) =>
                            !skipped.contains(f.id) &&
                            (missing(values[f.id]) ||
                                validateVisitSummary(
                                  form,
                                  values,
                                  requireComplete: false,
                                ).issues.any((i) => i.fieldId == f.id)),
                      )
                      .firstOrNull,
            validAnswer: (field, answer) => !validateVisitSummary(form, {
              ...values,
              field.id: answer,
            }, requireComplete: false).issues.any((i) => i.fieldId == field.id),
            proposeNarrative: (text, current) async {
              if (!current()) return [];
              final extracted = await StructuredVisitExtractor(
                app.voice.summaryExtractor,
              ).extract(form, text, current: current);
              if (!current()) return [];
              final proposed = <String, Json>{
                for (final fact in extracted)
                  if (allowsField(fact['fieldId'] as String))
                    fact['fieldId'] as String: fact,
              };
              return [
                for (final field in form.fields)
                  if ((missing(values[field.id]) ||
                          sources[field.id]?['sourceType'] == 'speech' &&
                              sources[field.id]?['question'] == null) &&
                      proposed[field.id] != null)
                    ClosureVoiceFact(field, proposed[field.id]!),
              ];
            },
            prepareAnswer: (field, text, current) async {
              final extracted = await StructuredVisitExtractor(
                app.voice.summaryExtractor,
              ).extract(form, text, current: current);
              if (field.id == 'optical_rx_dbm' &&
                  !extracted.any((f) => f['fieldId'] == field.id)) {
                final numeric = focusedOpticalFact(text);
                if (numeric != null) extracted.add(numeric);
              }
              final target = extracted
                  .where((f) => f['fieldId'] == field.id)
                  .firstOrNull;
              return ClosureVoiceAnswer(
                text,
                target == null
                    ? closureSpokenAnswer(field, text)
                    : decodeAnswers({field.id: target['value']})[field.id],
                closureSpokenQuestion(field),
                facts: extracted,
              );
            },
            keepNarrative: (text, facts, selected) async {
              await checkOwner();
              final next = {...values}, trace = {...sources};
              for (final fact in facts) {
                final previousSource = trace[fact.field.id];
                trace[fact.field.id] = {
                  ...fact.source,
                  'derivedFrom': 'actual_work',
                  'derivedSummary': text,
                };
                if (fact.answer == null &&
                    previousSource?['sourceType'] == 'speech' &&
                    previousSource?['question'] == null) {
                  next.remove(fact.field.id);
                }
                if (selected.contains(fact.field.id) &&
                    fact.answer != null &&
                    !validateVisitSummary(
                      form,
                      {...next, fact.field.id: fact.answer},
                      requireComplete: false,
                    ).issues.any((i) => i.fieldId == fact.field.id)) {
                  next[fact.field.id] = fact.answer;
                } else if (previousSource?['sourceType'] == 'speech' &&
                    previousSource?['question'] == null &&
                    fact.field.id != 'actual_work') {
                  // A retracted/invalid new proposal must not leave the old
                  // inferred value looking like a valid, answered field.
                  next.remove(fact.field.id);
                }
              }
              // Display the resolved statement; retain verbatim speech separately.
              final interpretation = interpretSpokenRepairs(text);
              next['actual_work'] = TextAnswer(interpretation.text);
              trace['actual_work'] = interpretation.ground({
                'sourceType': 'speech',
                'sourceSpan': text,
                'interpretedSpan': interpretation.text,
              });
              await save(next, nextSources: trace);
            },
            keepAnswer: (field, response) async {
              await checkOwner();
              await keepAnswer(field, response);
            },
          ),
        ),
      );
      if (mounted) {
        await fillFromSavedSummary(
          current: () => mounted && ref.read(appProvider).user?.id == owner,
        );
        if (!mounted) return;
        setState(() {
          manual = true;
          revision++;
        });
        if (completed == true) await review();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Voice paused. Your saved summary is ready to continue.',
        );
      }
    } finally {
      if (mounted) setState(() => openingVoice = false);
    }
  }

  Future<void> fillFromSavedSummary({required bool Function() current}) async {
    final savedText = (values['actual_work'] as TextAnswer?)?.value;
    if (savedText == null || !hasSpokenReportContent(savedText)) return;
    final source = sources['actual_work'];
    final text =
        source?['interpretedSpan'] == savedText &&
            source?['rawTranscript'] is String
        ? source!['rawTranscript'] as String
        : savedText;
    final facts = await StructuredVisitExtractor(
      ref.read(appProvider.notifier).voice.summaryExtractor,
    ).extract(form, text, current: current);
    if (!current() ||
        (values['actual_work'] as TextAnswer?)?.value != savedText) {
      return;
    }
    // Read the latest values after inference; an edit made while it ran wins.
    final next = {...values}, trace = {...sources};
    final changed = <String>[];
    final byId = {for (final fact in facts) fact['fieldId'] as String: fact};
    for (final field in form.fields) {
      final id = field.id;
      if (id == 'actual_work' || editingField == id) continue;
      final previous = sources[id] as Json?;
      final derived =
          previous?['derivedFrom'] == 'actual_work' &&
          previous?['question'] == null &&
          previous?['verificationStatus'] != 'engineer_confirmed';
      if (!missing(values[id]) && !derived) continue;
      if (previous?['verificationStatus'] == 'rejected' &&
          previous?['derivedSummary'] == text) {
        continue;
      }
      final fact = byId[id];
      final value = fact == null
          ? null
          : decodeAnswers({id: fact['value']})[id];
      if (value == null) {
        // A changed summary may retract a previously inferred fact. Preserve
        // explicit answers, but never leave an old inferred measurement behind.
        if (derived &&
            previous?['derivedSummary'] != text &&
            !missing(next[id])) {
          next.remove(id);
          trace.remove(id);
          changed.add(id);
        }
        continue;
      }
      if (validateVisitSummary(form, {
        ...next,
        id: value,
      }, requireComplete: false).issues.any((i) => i.fieldId == id)) {
        if (derived && !missing(next[id])) {
          next.remove(id);
          trace[id] = fact!;
          changed.add(id);
        }
        continue;
      }
      if (jsonEncode(values[id]?.toJson()) == jsonEncode(value.toJson()) &&
          previous?['derivedSummary'] == text &&
          previous?['requiresConfirmation'] == fact?['requiresConfirmation']) {
        continue;
      }
      changed.add(id);
      next[id] = value;
      trace[id] = {
        ...fact!,
        'sourceType': sources['actual_work']?['sourceType'] == 'speech'
            ? 'speech'
            : 'text',
        'derivedFrom': 'actual_work',
        'derivedSummary': text,
      };
    }
    // Older drafts may contain the full summary only in Work done. Fill their
    // gaps, preserving existing answers and immutable submitted payloads.
    if (changed.isNotEmpty) {
      await save(next, nextSources: trace);
      if (mounted) {
        setState(() {
          for (final id in changed) {
            automaticRevisions[id] = (automaticRevisions[id] ?? 0) + 1;
          }
        });
      }
    }
  }

  Future<void> keepAnswer(
    FieldDefinition field,
    ClosureVoiceAnswer response,
  ) async {
    final next = {...values}, trace = {...sources};
    Json? targetFact;
    var additionalDetails = 0;
    if (response.sourceType == 'speech' || response.facts.isNotEmpty) {
      // Engineers may give their whole summary after a guided question, or
      // when resuming. Every speech turn must fill all explicit details, not
      // just the field currently being asked about.
      for (final source
          in response.facts.isNotEmpty
              ? response.facts
              : compactNarrativeFacts(form, response.transcript)) {
        final id = source['fieldId'] as String;
        if (id == 'actual_work' && field.id != id) continue;
        if (id == field.id) targetFact = source;
        if (id != 'actual_work' && source['value'] != null) additionalDetails++;
        final previous = trace[id];
        if (!missing(next[id]) &&
            !(previous?['sourceType'] == 'speech' &&
                previous?['question'] == null)) {
          continue;
        }
        final value = decodeAnswers({id: source['value']})[id];
        if (value == null) {
          if (previous?['sourceType'] == 'speech' &&
              previous?['question'] == null) {
            next.remove(id);
          }
          trace[id] = source;
        } else if (!validateVisitSummary(form, {
          ...next,
          id: value,
        }, requireComplete: false).issues.any((i) => i.fieldId == id)) {
          next[id] = value;
          trace[id] = source;
        }
      }
    }
    if (response.sourceType == 'speech' &&
        field.id != 'actual_work' &&
        additionalDetails >= 2) {
      // Preserve the whole resumed summary, including work details which have
      // no separate compact field, as well as its extracted values.
      final previous = (next['actual_work'] as TextAnswer?)?.value ?? '';
      final combined = previous.contains(response.transcript)
          ? previous
          : [
              previous,
              response.transcript,
            ].where((s) => s.isNotEmpty).join('\n');
      next['actual_work'] = TextAnswer(combined);
      trace['actual_work'] = {
        'sourceType':
            previous.isEmpty ||
                sources['actual_work']?['sourceType'] == 'speech'
            ? 'speech'
            : 'text',
        'sourceSpan': combined,
      };
    }
    // A compound summary without an asset or follow-up must not become an
    // arbitrary free-text answer to either of those questions.
    final compoundWithoutTarget =
        targetFact == null &&
        additionalDetails >= 2 &&
        ['serving_asset', 'next_action'].contains(field.id);
    final focused = targetFact != null
        ? decodeAnswers({field.id: targetFact['value']})[field.id]
        : compoundWithoutTarget
        ? null
        : response.answer;
    if (focused != null &&
        !validateVisitSummary(form, {
          ...next,
          field.id: focused,
        }, requireComplete: false).issues.any((i) => i.fieldId == field.id)) {
      next[field.id] = focused;
      trace[field.id] =
          (targetFact == null
              ? null
              : {...targetFact, 'question': response.question}) ??
          {
            'sourceType': response.sourceType,
            'sourceSpan': response.transcript,
            'question': response.question,
          };
    } else if (targetFact == null && !missing(values[field.id])) {
      trace[field.id] = {
        'sourceType': 'text',
        'sourceSpan':
            'Previously saved answer: ${field.display(values[field.id])}',
        ...?(sources[field.id] as Json?),
        'ambiguityReason':
            '${sources[field.id]?['ambiguityReason'] ?? ''}\nLater unmatched response was not applied: ${response.transcript}'
                .trim(),
      };
    } else if (targetFact == null) {
      trace[field.id] = {
        'sourceType': response.sourceType,
        'sourceSpan': response.transcript,
        'question': response.question,
      };
    }
    await save(next, nextSources: trace);
  }

  Future<void> review() async {
    if (reviewing) return;
    setState(() => reviewing = true);
    try {
      summaryTimer?.cancel();
      final serial = ++summaryMapping;
      final owner = ref.read(appProvider).user?.id;
      await fillFromSavedSummary(
        current: () =>
            mounted &&
            serial == summaryMapping &&
            ref.read(appProvider).user?.id == owner,
      );
      await tail;
      if (needsReadingConfirmation) {
        setState(
          () => error =
              'Confirm the proposed optical reading, or enter the measured value, before reviewing.',
        );
        return;
      }
      final issues = validateVisitSummary(form, values).issues;
      if (issues.isNotEmpty) {
        setState(() => error = issues.first.message);
        return;
      }
      if ([
            'partial',
            'blocked',
            'hold',
            'referred',
            'stage_completed',
            'network_ready',
          ].contains(values['claimed_outcome']?.toJson()) &&
          missing(values['next_action'])) {
        setState(
          () => error = 'Add the follow-up or next action for this outcome.',
        );
        return;
      }
      if (!mounted) return;
      final snapshot = {...values};
      var editWordsRequested = false;
      final accepted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (reviewContext) => _CompactReview(
            form: form,
            values: snapshot,
            editWords: hasSpokenWords
                ? () {
                    editWordsRequested = true;
                    Navigator.pop(reviewContext, false);
                  }
                : null,
            save: () async {
              final app = ref.read(appProvider.notifier);
              await save(
                snapshot,
                reviewTime: DateTime.now().toUtc().toIso8601String(),
              );
              return app.queueVisitSummary(
                reportId: widget.reportId,
                workOrderId: report!.workOrderId,
                values: snapshot,
                sources: {...sources},
              );
            },
          ),
        ),
      );
      if (mounted && editWordsRequested) await editSpokenWords();
      if (mounted && accepted == true) {
        context.go(
          snapshot['claimed_outcome']?.toJson() == 'completed'
              ? '/jobs?view=completed'
              : '/jobs',
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Save the summary before reviewing.');
    } finally {
      if (mounted) setState(() => reviewing = false);
    }
  }

  @override
  void dispose() {
    summaryMapping++;
    summaryTimer?.cancel();
    speech?.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = report;
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Visit summary')),
        body: Center(
          child: error.isEmpty
              ? const CircularProgressIndicator()
              : Text(error),
        ),
      );
    }
    if (draft.state != ReportState.draft) return widget.fullChecklist();
    final job = ref
        .watch(appProvider)
        .workOrders
        .where((j) => j.id == draft.workOrderId)
        .firstOrNull;
    final filled = form.fields.where((f) => !missing(values[f.id])).length;
    final submission = ref
        .watch(appProvider)
        .summarySubmissions
        .where(
          (s) =>
              (s['payload'] as Json)['clientReportId'] == widget.reportId &&
              jsonEncode((s['payload'] as Json)['values']) ==
                  jsonEncode(encodeAnswers(values)),
        )
        .lastOrNull;
    final deliveryStatus = reviewedAt != null && submission != null
        ? submission['status'] == 'received'
              ? 'Submitted · Dashboard → Submissions → Visit summaries'
              : submission['status'] == 'attention'
              ? 'Saved on this device · Sync needs attention'
              : 'Saved on this device · Waiting to sync'
        : saveStatus;
    return Scaffold(
      appBar: AppBar(title: const Text('Visit summary')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: openingVoice || resetting || reviewing ? null : review,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text('Review ${form.fields.length}-field summary'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (job != null)
            Card(
              child: ListTile(title: Text(job.title), subtitle: Text(job.site)),
            ),
          if (job != null) SiteTimeCard(job: job, collapsible: true),
          Text(
            '${form.fields.length} fields. One conversation.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '$filled of ${form.fields.length} filled · $deliveryStatus',
            style: TextStyle(color: context.colors.muted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: openingVoice || resetting ? null : voice,
            icon: const Icon(Icons.graphic_eq_rounded),
            label: const Text('Fill with voice AI'),
          ),
          if (hasSpokenWords)
            TextButton.icon(
              onPressed: openingVoice || resetting ? null : editSpokenWords,
              icon: const Icon(Icons.record_voice_over_outlined),
              label: const Text('Edit spoken words'),
            ),
          if (!manual)
            TextButton.icon(
              onPressed: resetting || openingVoice
                  ? null
                  : () => setState(() => manual = true),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Fill manually'),
            ),
          OutlinedButton.icon(
            onPressed:
                openingVoice || resetting || (filled == 0 && sources.isEmpty)
                ? null
                : () async {
                    try {
                      await resetAnswers();
                    } catch (_) {
                      // The retained answers and retry message are visible.
                    }
                  },
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset answers'),
          ),
          const SizedBox(height: 16),
          ErrorNotice(error),
          for (final field in form.fields)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${field.order + 1}. ${field.label}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    if (manual)
                      Focus(
                        onFocusChange: (focused) {
                          if (focused) {
                            editingField = field.id;
                          } else if (editingField == field.id) {
                            editingField = null;
                          }
                        },
                        child: AnswerInput(
                          key: ValueKey(
                            '${field.id}-$revision-${automaticRevisions[field.id] ?? 0}',
                          ),
                          field: field,
                          value: values[field.id],
                          enabled: !openingVoice && !resetting,
                          onChanged: (answer) =>
                              unawaited(change(field, answer)),
                        ),
                      )
                    else
                      Text(field.display(values[field.id])),
                    if (field.id == 'optical_rx_dbm' &&
                        needsReadingConfirmation) ...[
                      const SizedBox(height: 8),
                      Text(
                        sources[field.id]?['ambiguityReason'] as String? ??
                            'Confirm the proposed optical reading and its dBm unit.',
                      ),
                      TextButton.icon(
                        onPressed: openingVoice || resetting
                            ? null
                            : () => change(field, values[field.id]),
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          'Confirm ${field.display(values[field.id])} dBm',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            reviewedAt == null
                ? 'Synthetic demo summary · Review before saving.'
                : 'Demo summary reviewed · Edits will require a new review.',
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
          TextButton(
            onPressed: resetting || openingVoice
                ? null
                : () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => widget.fullChecklist()),
                  ),
            child: const Text('Open full closure checks'),
          ),
        ],
      ),
    );
  }
}

class _CompactReview extends ConsumerStatefulWidget {
  const _CompactReview({
    required this.form,
    required this.values,
    required this.save,
    this.editWords,
  });
  final FormDefinition form;
  final Answers values;
  final Future<Json> Function() save;
  final VoidCallback? editWords;
  @override
  ConsumerState<_CompactReview> createState() => _CompactReviewState();
}

class _CompactReviewState extends ConsumerState<_CompactReview> {
  bool busy = false;
  String error = '';
  Future<void> confirm() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final queued = await widget.save();
      if (mounted) context.go('/visit-summaries/${queued['id']}');
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error =
              'Could not queue this summary. Your draft is retained. Check device storage and retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Review visit summary')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: busy ? null : confirm,
            child: Text(
              busy
                  ? 'Submitting…'
                  : widget.values['claimed_outcome']?.toJson() == 'completed'
                  ? 'Complete visit & submit'
                  : 'Submit visit summary',
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.editWords != null)
            TextButton.icon(
              onPressed: busy ? null : widget.editWords,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Edit spoken words'),
            ),
          for (final field in widget.form.fields)
            Card(
              child: ListTile(
                title: Text(field.label),
                subtitle: Text(field.display(widget.values[field.id])),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Check your answers, then submit. Submission saves in encrypted storage on this device, including offline. Dashboard delivery happens when connected. Full operational closure checks remain separate.',
            ),
          ),
          ErrorNotice(error),
        ],
      ),
    ),
  );
}
