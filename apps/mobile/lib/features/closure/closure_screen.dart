import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../forms/form_screen.dart' show AnswerInput;
import '../fttp/fttp_widgets.dart';
import '../voice/field_extraction.dart';
import '../voice/patch_rules.dart';
import '../voice/voice_audio.dart';
import '../voice/prompt_audio_cache.dart';
import 'closure_extraction.dart';
import 'closure_voice_turn.dart';
import 'closure_voice_assistant.dart';
import 'question_voice.dart';
import 'compact_closure_screen.dart';

class ClosureScreen extends ConsumerStatefulWidget {
  const ClosureScreen({
    super.key,
    required this.reportId,
    this.fullChecklist = false,
  });
  final String reportId;
  final bool fullChecklist;
  @override
  ConsumerState<ClosureScreen> createState() => _ClosureScreenState();
}

class _ClosureScreenState extends ConsumerState<ClosureScreen>
    with WidgetsBindingObserver {
  LocalReport? report;
  Answers values = {};
  List<Json> photos = [], candidates = [];
  Json capture = {};
  final narrative = TextEditingController();
  Future<void> tail = Future.value();
  int sequence = 0, inputRevision = 0;
  bool busy = false, recording = false, missingOnly = false, manual = false;
  String error = '', saved = 'Loading…', sourceType = 'text', focused = '';
  VoiceAudio? audio;
  PromptAudioCache? spokenQuestions;
  final pcm = BytesBuilder(copy: false);
  Timer? limit;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.fullChecklist) load();
  }

  Future<void> load() async {
    try {
      final app = ref.read(appProvider.notifier);
      await app.assertAccess();
      final r = await app.repository.get(widget.reportId);
      final p = await app.repository.evidence(r.id);
      final c =
          await app.repository.metadata('closure-capture:${r.id}') as Json? ??
          {'startedAt': DateTime.now().toUtc().toIso8601String()};
      if (!mounted) return;
      setState(() {
        report = r;
        values = {...r.values};
        photos = p;
        capture = c;
        candidates = (c['candidates'] as List? ?? []).cast<Json>();
        narrative.text = c['transcript'] as String? ?? '';
        saved = 'Saved on this device';
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unlock the workspace and reopen this draft.');
      }
    }
  }

  Future<void> persistCapture() async {
    final app = ref.read(appProvider.notifier);
    await app.assertAccess();
    capture = {
      ...capture,
      'transcript': narrative.text,
      'candidates': candidates,
    };
    await app.repository.saveClosureCapture(widget.reportId, capture);
  }

  Future<void> save(Answers next, {String source = 'manual'}) {
    final serial = ++sequence;
    if (mounted) {
      setState(() {
        values = next;
        saved = 'Saving…';
        error = '';
      });
    }
    final operation = tail.catchError((_) {}).then((_) async {
      final app = ref.read(appProvider.notifier);
      await app.assertAccess();
      final r = await app.repository.save(
        widget.reportId,
        next,
        source: source,
      );
      await app.reloadReports();
      final retainedPhotos = await app.repository.evidence(widget.reportId);
      if (mounted) {
        setState(() {
          report = r;
          photos = retainedPhotos;
          if (serial == sequence) {
            values = {...r.values};
            saved = 'Saved on this device';
          }
        });
      }
    });
    tail = operation;
    unawaited(
      operation.catchError((_) {
        if (mounted) {
          setState(() {
            error = 'Could not save. Keep this draft open, unlock and retry.';
            saved = 'Retry required';
          });
        }
      }),
    );
    return operation;
  }

  Future<void> change(String id, Answer? value) async {
    capture['corrections'] = (capture['corrections'] as int? ?? 0) + 1;
    try {
      await save({...values, id: value});
      await persistCapture();
    } catch (_) {}
  }

  Future<void> extract({bool useModel = false}) async {
    if (busy || narrative.text.trim().isEmpty) return;
    final owner = ref.read(appProvider).user?.id, text = narrative.text.trim();
    final timer = Stopwatch()..start();
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await tail;
      await persistCapture();
      final history = ((capture['transcriptHistory'] as List?) ?? [])
          .cast<String>();
      capture['transcriptHistory'] = retainClosureSources(history, [text]);
      final proposed = <String, Json>{
        for (final c in candidates.where(
          (c) =>
              c['sourceType'] == 'job_pack' ||
              c['verificationStatus'] == 'accepted',
        ))
          c['fieldId'] as String: c,
        for (final c in literalClosureFacts(text, sourceType: sourceType))
          c['fieldId'] as String: c,
      };
      if (useModel) {
        if (!ref.read(appProvider).voiceReady) {
          throw StateError(
            'The local voice package is not ready. Use literal facts or continue by touch.',
          );
        }
        for (final field in closureNarrativeTargets(
          report!.schema,
          values,
          proposed.keys.toSet(),
        )) {
          final output = await extractFormFields(
            ref.read(appProvider.notifier).voice,
            report!.schema,
            text,
            knownValues: values,
            focusedFieldId: field.id,
          );
          final patch = mergeExtraction(report!.schema, values, output, text);
          if (patch.changed.contains(field.id)) {
            proposed[field.id] = {
              'fieldId': field.id,
              'value': patch.values[field.id]?.toJson(),
              'sourceSpan': text,
              'sourceType': sourceType,
              'confidence': (output['confidence'] as num?)?.toDouble(),
              'verificationStatus': 'candidate',
              'ambiguityReason':
                  'On-device model proposal; verify against the preserved narrative.',
            };
          }
        }
      }
      await ref.read(appProvider.notifier).assertAccess();
      if (ref.read(appProvider).user?.id != owner || !mounted) return;
      final fields = report!.schema.fields.map((f) => f.id).toSet();
      setState(() {
        candidates = proposed.values
            .where((c) => fields.contains(c['fieldId']))
            .toList();
        focused = '';
      });
      capture['extractionMs'] =
          (capture['extractionMs'] as int? ?? 0) + timer.elapsedMilliseconds;
      await persistCapture();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> applyFacts({
    Set<String>? fieldIds,
    bool propagateError = false,
    bool markReviewed = true,
  }) async {
    try {
      final updates = {...values};
      final acceptedIds = <String>{};
      for (var pass = 0; pass < report!.schema.fields.length; pass++) {
        var changed = false;
        for (final c in candidates) {
          final field = report!.schema.fields
              .where((f) => f.id == c['fieldId'])
              .firstOrNull;
          if (field == null ||
              (fieldIds != null && !fieldIds.contains(field.id)) ||
              acceptedIds.contains(field.id) ||
              !report!.schema.visible(field, updates) ||
              c['value'] == null ||
              c['verificationStatus'] != 'candidate') {
            continue;
          }
          final answer = decodeAnswers({c['fieldId'] as String: c['value']});
          final check = validate(report!.schema, {
            ...updates,
            ...answer,
          }, requireComplete: false);
          if (!check.issues.any((i) => i.fieldId == c['fieldId'])) {
            updates.addAll(answer);
            acceptedIds.add(field.id);
            changed = true;
          }
        }
        if (!changed) break;
      }
      await save(
        updates,
        source: sourceType == 'speech' ? 'voice' : 'narrative',
      );
      for (final c in candidates.where(
        (c) => acceptedIds.contains(c['fieldId']),
      )) {
        if (markReviewed) c['verificationStatus'] = 'accepted';
      }
      await persistCapture();
      if (mounted) {
        setState(() {
          inputRevision++;
          missingOnly = true;
        });
      }
    } catch (_) {
      if (propagateError) rethrow;
    }
  }

  Future<void> speech() async {
    if (recording) {
      await finishSpeech();
      return;
    }
    if (busy || !ref.read(appProvider).voiceReady) return;
    try {
      await ref.read(appProvider.notifier).assertAccess();
      audio = ref.read(voiceAudioFactoryProvider)();
      await audio!.configure(() => unawaited(interrupt()));
      if (!await audio!.hasPermission()) {
        throw StateError(
          'Microphone permission is required for dictation. Your draft is saved.',
        );
      }
      pcm.clear();
      if (!mounted) return;
      setState(() => recording = true);
      await audio!.capture(
        onBytes: (b) {
          if (pcm.length < 16000 * 2 * 60) pcm.add(b);
        },
        onLevel: (_) {},
        onError: (_) => unawaited(interrupt()),
      );
      limit = Timer(
        const Duration(seconds: 60),
        () => unawaited(finishSpeech()),
      );
    } catch (e) {
      await audio?.close();
      audio = null;
      if (mounted) {
        setState(() {
          recording = false;
          error = e.toString();
        });
      }
    }
  }

  Future<void> voiceQuestion(FieldDefinition field) =>
      startVoiceAssistant(initialField: field);

  Future<void> keepVoiceAnswer(
    FieldDefinition field,
    ClosureVoiceAnswer response,
  ) async {
    await ref.read(appProvider.notifier).assertAccess();
    final previous = narrative.text;
    final contextText =
        '${response.question}\nEngineer ${response.inputMethod == 'option'
            ? 'selected'
            : response.inputMethod == 'typed'
            ? 'typed'
            : 'said'}: ${response.transcript}';
    capture['transcriptHistory'] = retainClosureSources(
      ((capture['transcriptHistory'] as List?) ?? []).cast<String>(),
      [previous, contextText],
    );
    // Bot questions belong to the source ledger. They must never be fed back
    // into extraction as if the engineer had stated them as facts.
    final answer = response.answer;
    final check = validate(report!.schema, {
      ...values,
      field.id: answer,
    }, requireComplete: false);
    final accepted =
        answer != null &&
        report!.schema.visible(field, values) &&
        !check.issues.any((i) => i.fieldId == field.id);
    candidates = [
      ...candidates.where((c) => c['fieldId'] != field.id),
      {
        'fieldId': field.id,
        'value': answer?.toJson(),
        'sourceSpan': response.transcript,
        'sourceType': response.sourceType,
        'confidence': null,
        'verificationStatus': 'candidate',
        'ambiguityReason':
            'Draft answer from ${response.inputMethod == 'option'
                ? 'an option selection'
                : response.inputMethod == 'typed'
                ? 'typed input'
                : 'engineer speech'}; final closure review required. Question: ${response.question}',
      },
    ];
    capture['promptsShown'] = (capture['promptsShown'] as int? ?? 0) + 1;
    if (accepted) {
      await save({
        ...values,
        field.id: answer,
      }, source: response.sourceType == 'speech' ? 'voice' : 'manual');
    }
    await persistCapture();
    if (mounted) {
      setState(() {
        inputRevision++;
        missingOnly = true;
        focused = '';
      });
    }
  }

  FieldDefinition? nextVoiceField(Set<String> skipped) {
    final schema = report!.schema, raw = encodeAnswers(values);
    final policy = schema.source['closurePolicy'] as Json;
    return schema
        .visibleFields(values)
        .where(
          (f) =>
              closureRequired(f.id, f.required, raw, policy) &&
              missing(values[f.id]) &&
              f.voiceEnabled &&
              f.source['capture'] != 'evidence' &&
              !{'scenario', 'work_stage', ...skipped}.contains(f.id),
        )
        .firstOrNull;
  }

  Future<void> startVoiceAssistant({FieldDefinition? initialField}) async {
    if (busy || recording) return;
    if (!ref.read(appProvider).voiceReady) {
      setState(
        () => error =
            'Prepare the offline voice package in Profile to start the assistant.',
      );
      await context.push('/settings');
      return;
    }
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
      if (!mounted) return;
      spokenQuestions?.clear();
      spokenQuestions = PromptAudioCache(app.voice);
      final settings = ref.read(appProvider);
      app.voice.selectSpeechVoice(settings.speechVoiceId);
      final voice = QuestionVoice(
        spokenQuestions!,
        bundle: DefaultAssetBundle.of(context),
        voiceId: settings.speechVoiceId,
        rate: settings.speechRate,
      );
      final greetingIndex = await app.nextVoiceGreetingIndex();
      if (!mounted) return;
      var firstQuestion = initialField;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ClosureVoiceAssistant(
            greetingIndex: greetingIndex,
            jobTitle:
                ref
                    .read(appProvider)
                    .workOrders
                    .where((j) => j.id == report!.workOrderId)
                    .firstOrNull
                    ?.title ??
                'FTTP closure assistant',
            needsNarrative:
                initialField == null &&
                narrative.text.trim().isEmpty &&
                missing(values['actual_work']),
            recognizer: app.voice,
            synthesizer: voice,
            audio: ref.read(voiceAudioFactoryProvider)(),
            assertAccess: checkOwner,
            cancelInference: app.voice.cancel,
            isAnswered: (field) =>
                !missing(values[field.id]) &&
                !validate(
                  report!.schema,
                  values,
                  requireComplete: false,
                ).issues.any((i) => i.fieldId == field.id),
            nextQuestion: (skipped) {
              final first = firstQuestion;
              firstQuestion = null;
              return first ?? nextVoiceField(skipped);
            },
            validAnswer: (field, answer) =>
                report!.schema.visible(field, values) &&
                !validate(
                  report!.schema,
                  {...values, field.id: answer},
                  requireComplete: false,
                ).issues.any((i) => i.fieldId == field.id),
            proposeNarrative: (text, current) async {
              await checkOwner();
              final schema = report!.schema, known = {...values};
              final proposed = <String, Json>{
                for (final c in literalClosureFacts(text, sourceType: 'speech'))
                  c['fieldId'] as String: c,
              };
              for (final field in closureNarrativeTargets(
                schema,
                known,
                proposed.keys.toSet(),
              )) {
                if (!current()) return [];
                final output = await extractFormFields(
                  app.voice,
                  schema,
                  text,
                  knownValues: known,
                  focusedFieldId: field.id,
                );
                if (!current()) return [];
                final patch = mergeExtraction(schema, known, output, text);
                if (patch.changed.contains(field.id)) {
                  proposed[field.id] = {
                    'fieldId': field.id,
                    'value': patch.values[field.id]?.toJson(),
                    'sourceSpan': text,
                    'sourceType': 'speech',
                    'confidence': (output['confidence'] as num?)?.toDouble(),
                    'verificationStatus': 'candidate',
                    'ambiguityReason':
                        'On-device proposal; engineer review required.',
                  };
                }
              }
              await checkOwner();
              if (!current()) return [];
              // Preview fields from newly activated branches, without accepting them.
              final preview = {...known};
              for (final c in proposed.values.where(
                (c) => c['value'] != null,
              )) {
                preview.addAll(
                  decodeAnswers({c['fieldId'] as String: c['value']}),
                );
              }
              return [
                for (final field in schema.visibleFields(preview))
                  if (proposed.containsKey(field.id))
                    ClosureVoiceFact(field, proposed[field.id]!),
              ];
            },
            keepNarrative: (text, facts, selected) async {
              await checkOwner();
              capture['transcriptHistory'] = retainClosureSources(
                ((capture['transcriptHistory'] as List?) ?? []).cast<String>(),
                [narrative.text, text],
              );
              narrative.text = text;
              sourceType = 'speech';
              final ids = facts.map((f) => f.field.id).toSet();
              candidates = [
                ...candidates.where((c) => !ids.contains(c['fieldId'])),
                for (final fact in facts) {...fact.source},
              ];
              await persistCapture();
              await applyFacts(
                fieldIds: selected,
                propagateError: true,
                markReviewed: false,
              );
            },
            keepAnswer: (field, answer) async {
              await checkOwner();
              await keepVoiceAnswer(field, answer);
            },
          ),
        ),
      );
      if (mounted) {
        setState(() {
          manual = true;
          missingOnly = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'The assistant paused. Your saved draft is ready to continue.',
        );
      }
    }
  }

  Future<void> finishSpeech() async {
    if (!recording) return;
    setState(() {
      recording = false;
      busy = true;
    });
    limit?.cancel();
    final owner = ref.read(appProvider).user?.id;
    try {
      await audio?.stopCapture();
      final bytes = pcm.takeBytes(), data = ByteData.sublistView(bytes);
      final samples = Float32List(bytes.length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
      }
      await ref.read(appProvider.notifier).assertAccess();
      final text = await ref
          .read(appProvider.notifier)
          .voice
          .transcribe(samples);
      await ref.read(appProvider.notifier).assertAccess();
      if (!mounted || ref.read(appProvider).user?.id != owner) return;
      narrative.text = text;
      sourceType = 'speech';
      await persistCapture();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Dictation stopped. Your saved answers remain available; retry or type the narrative.',
        );
      }
    } finally {
      await audio?.close();
      audio = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> interrupt() async {
    limit?.cancel();
    await audio?.stopCapture();
    pcm.clear();
    if (mounted) {
      setState(() {
        recording = false;
        error = 'Dictation paused. Start again when it is safe to continue.';
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(interrupt());
    }
  }

  Future<void> loadExample() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Load a synthetic example?'),
        content: const Text(
          'Replace this draft’s answers with labelled demonstration facts. Existing photographs are retained and must be checked. Assigned job context stays unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Load example'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    try {
      final examples =
          jsonDecode(
                await rootBundle.loadString('assets/closure/examples.json'),
              )
              as Json;
      final raw = encodeAnswers(values);
      Json sample = Map<String, dynamic>.from(examples[raw['scenario']] as Map);
      if (raw['scenario'] == 'S5' && raw['work_stage'] != 'civils') {
        final paths =
            jsonDecode(
                  await rootBundle.loadString('assets/closure/pathways.json'),
                )
                as List;
        sample = Map<String, dynamic>.from(
          (paths.firstWhere(
                    (p) =>
                        p['id'] ==
                        (raw['work_stage'] == 'survey' ? 'T5-01' : 'T5-04'),
                  )
                  as Json)['values']
              as Map,
        );
      }
      sample['scenario'] = raw['scenario'];
      sample['work_stage'] = raw['work_stage'];
      final history = ((capture['transcriptHistory'] as List?) ?? [])
          .cast<String>();
      if (narrative.text.isNotEmpty) {
        capture['transcriptHistory'] = [
          ...{...history, narrative.text},
        ].reversed.take(8).toList().reversed.toList();
      }
      narrative.text = sample['actual_work'] as String;
      candidates = candidates
          .where((c) => c['sourceType'] == 'job_pack')
          .toList();
      for (final f in report!.schema.fields.where(
        (f) => f.source['capture'] == 'evidence',
      )) {
        sample[f.id] =
            photos.any((p) => p['stage'] == f.source['evidenceStage'])
            ? true
            : null;
      }
      await save(decodeAnswers(sample), source: 'demo_example');
      await persistCapture();
      if (mounted) {
        setState(() {
          inputRevision++;
          missingOnly = true;
          focused = '';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not load the example. Your saved draft is retained.',
        );
      }
    }
  }

  Future<void> catalogue() async {
    final data =
        jsonDecode(await rootBundle.loadString('assets/closure/catalogue.json'))
            as Json;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * .8,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Workflow catalogue',
              style: Theme.of(c).textTheme.headlineSmall,
            ),
            const Text(
              '15 types · 251 source fields · 70 proposed rules. Catalogue prepared for later expansion; this build implements the five FTTP scenarios.',
            ),
            for (final type in data['jobTypes'] as List)
              ListTile(
                title: Text(type['title'] as String),
                subtitle: Text(
                  '${type['id']} · ${(type['questions'] as List).length} fields · Prepared / synthetic',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> review() async {
    try {
      await tail;
      await persistCapture();
      if (!mounted) return;
      final field = await context.push<String>('/review/${widget.reportId}');
      if (mounted && field != null) {
        setState(() {
          focused = field;
          missingOnly = false;
          manual = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Save the draft before reviewing.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.fullChecklist) {
      return CompactClosureScreen(
        reportId: widget.reportId,
        fullChecklist: () =>
            ClosureScreen(reportId: widget.reportId, fullChecklist: true),
      );
    }
    final r = report;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Closure assistant')),
        body: Center(
          child: error.isEmpty
              ? const CircularProgressIndicator()
              : Text(error),
        ),
      );
    }
    final schema = r.schema,
        raw = encodeAnswers(values),
        policy = schema.source['closurePolicy'] as Json;
    final active = schema.visibleFields(values);
    final missingFields = active
        .where(
          (f) =>
              closureRequired(f.id, f.required, raw, policy) &&
              missing(values[f.id]),
        )
        .toList();
    final checks = checkClosure(schema.source, raw, photos);
    final job = ref
        .watch(appProvider)
        .workOrders
        .where((j) => j.id == r.workOrderId)
        .firstOrNull;
    final assigned = job?.source['closureContext'] as Json?;
    final editable = r.state == ReportState.draft;
    final displayFields = active
        .where(
          (f) => focused.isNotEmpty
              ? f.id == focused
              : !missingOnly || missingFields.contains(f),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('FTTP closure assistant'),
        actions: [
          IconButton(
            onPressed: catalogue,
            tooltip: '15-type catalogue',
            icon: const Icon(Icons.library_books_outlined),
          ),
        ],
      ),
      bottomNavigationBar: !manual
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: FilledButton.icon(
                  onPressed: editable && !busy && !recording ? review : null,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text('Review closure · ${missingFields.length} gaps'),
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 15,
                  color: context.colors.muted,
                ),
                const SizedBox(width: 7),
                Text(
                  'SYNTHETIC DEMO',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.3,
                    color: context.colors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (job != null)
              Card(
                child: ListTile(
                  title: Text(job.title),
                  subtitle: Text(
                    '${job.site}\nAssigned stage: ${(assigned?['workStage'] as String? ?? 'Unspecified').replaceAll('_', ' ')}',
                  ),
                  isThreeLine: true,
                ),
              ),
            const SizedBox(height: 20),
            if (!manual) ...[
              Text(
                'Finish the visit.\nWe’ll help with the report.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
            ],
            if (editable)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff102b4c), Color(0xff061426)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xffa5d2ff),
                          size: 22,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'YOUR FIELD ASSISTANT',
                          style: TextStyle(
                            color: Color(0xffa5bdd8),
                            fontSize: 10,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Say it once.\nWe’ll help fill the report.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'I’ll ask, listen and fill your draft. Speak your answer or choose an option, and I’ll move on automatically.',
                      style: TextStyle(
                        color: Color(0xffb0c2d8),
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff3478f6),
                      ),
                      onPressed: busy || recording
                          ? null
                          : () => startVoiceAssistant(),
                      icon: const Icon(Icons.graphic_eq_rounded),
                      label: const Text('Fill with voice AI'),
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.center,
                      child: Text(
                        'Answer aloud or tap · Auto advance',
                        style: TextStyle(
                          color: Color(0xff91a7c2),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (!manual) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => setState(() => manual = true),
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Fill manually'),
              ),
              const SizedBox(height: 18),
              Text(
                '${missingFields.length} applicable details to check · Saved on this device',
                style: TextStyle(color: context.colors.muted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Text(
                'Proposed workflow for demonstration. Question banks and closure gates require Openreach validation.',
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 11,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              ErrorNotice(error),
            ],
            if (manual) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tell us what happened',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Capture facts once. Review proposed answers, then resolve only the applicable gaps.',
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: narrative,
                        enabled: editable && !busy && !recording,
                        maxLength: 1500,
                        minLines: 3,
                        maxLines: 7,
                        decoration: const InputDecoration(
                          labelText: 'Original engineer narrative',
                          hintText:
                              'What was done, what was tested, and what remains?',
                        ),
                        onChanged: (_) {
                          sourceType = 'text';
                          unawaited(persistCapture().catchError((_) {}));
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                editable &&
                                    !busy &&
                                    ref.watch(appProvider).voiceReady
                                ? speech
                                : null,
                            icon: Icon(
                              recording
                                  ? Icons.stop_circle_outlined
                                  : Icons.mic_none,
                            ),
                            label: Text(
                              recording ? 'Stop & transcribe' : 'Dictate',
                            ),
                          ),
                          FilledButton(
                            onPressed: editable && !busy && !recording
                                ? () => extract()
                                : null,
                            child: Text(
                              busy ? 'Working…' : 'Find explicit facts',
                            ),
                          ),
                          TextButton(
                            onPressed:
                                editable &&
                                    !busy &&
                                    !recording &&
                                    ref.watch(appProvider).voiceReady
                                ? () => extract(useModel: true)
                                : null,
                            child: const Text('Use on-device AI'),
                          ),
                        ],
                      ),
                      const Text(
                        'Candidates are never treated as verified measurements, consent or safety clearance.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              if (candidates.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Candidate facts · check the source',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final c in candidates)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${schema.fields.firstWhere((f) => f.id == c['fieldId']).label}: ${c['value'] ?? 'Ambiguous — please clarify'}',
                            ),
                            subtitle: Text(
                              '“${c['sourceSpan']}”\n${c['sourceType']} · ${c['verificationStatus']}\n${c['ambiguityReason']}',
                            ),
                          ),
                        if (editable)
                          FilledButton(
                            onPressed: busy ? null : () => applyFacts(),
                            child: const Text(
                              'Accept these facts into the draft',
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (editable)
                TextButton.icon(
                  onPressed: busy ? null : loadExample,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Load labelled scenario example'),
                ),
              ErrorNotice(error),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${missingFields.length} applicable answers missing',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'Suggested disposition: ${checks.recommendation.replaceAll('_', ' ')}',
                      ),
                      Text(
                        checks.serviceLive
                            ? 'Service-live closure eligible after engineer confirmation.'
                            : 'Customer service is not recorded as live.',
                      ),
                      if (checks.issues.isNotEmpty)
                        Text(checks.issues.take(3).join('\n')),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show missing questions only'),
                        value: missingOnly,
                        onChanged: (v) => setState(() {
                          missingOnly = v;
                          focused = '';
                          capture['promptsShown'] =
                              (capture['promptsShown'] as int? ?? 0) +
                              missingFields.length;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              if (focused.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => focused = ''),
                  child: const Text('Show all applicable checks'),
                ),
              for (final f in displayFields)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${f.label}${closureRequired(f.id, f.required, raw, policy) ? ' *' : ''}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        for (final c in candidates.where(
                          (c) =>
                              c['fieldId'] == f.id &&
                              c['value'] != null &&
                              c['verificationStatus'] == 'candidate',
                        ))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('Already reported: ${c['value']}'),
                            subtitle: Text('“${c['sourceSpan']}”'),
                            trailing: TextButton(
                              onPressed: !editable || busy
                                  ? null
                                  : () async {
                                      try {
                                        await change(
                                          f.id,
                                          decodeAnswers({
                                            f.id: c['value'],
                                          })[f.id],
                                        );
                                        c['verificationStatus'] = 'accepted';
                                        await persistCapture();
                                        if (mounted) {
                                          setState(() => inputRevision++);
                                        }
                                      } catch (_) {}
                                    },
                              child: const Text('Use fact'),
                            ),
                          ),
                        if (f.source['capture'] == 'evidence')
                          Text(
                            photos.any(
                                  (p) =>
                                      p['stage'] == f.source['evidenceStage'],
                                )
                                ? 'Attached below · review image and purpose'
                                : 'Attach ${f.source['evidenceStage']} evidence below',
                          )
                        else
                          AnswerInput(
                            key: ValueKey('${f.id}-$inputRevision'),
                            field: f,
                            value: values[f.id],
                            enabled:
                                editable &&
                                !busy &&
                                !(assigned != null &&
                                    ['scenario', 'work_stage'].contains(f.id)),
                            onChanged: (v) => unawaited(change(f.id, v)),
                          ),
                        if (editable &&
                            f.voiceEnabled &&
                            f.source['capture'] != 'evidence' &&
                            !['scenario', 'work_stage'].contains(f.id))
                          TextButton.icon(
                            onPressed:
                                !busy &&
                                    !recording &&
                                    ref.watch(appProvider).voiceReady
                                ? () => voiceQuestion(f)
                                : null,
                            icon: const Icon(Icons.mic_none),
                            label: const Text('Answer by voice'),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          missing(values[f.id])
                              ? 'Awaiting your answer'
                              : 'Ready for final engineer review',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Linked visit evidence',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              FttpEvidencePanel(
                key: ValueKey('closure-evidence-${r.id}'),
                report: r,
                closure: true,
                onSaved: (p) async {
                  photos = p;
                  await save({
                    ...values,
                    for (final f
                        in schema
                            .visibleFields(values)
                            .where((f) => f.source['capture'] == 'evidence'))
                      f.id:
                          p.any((e) => e['stage'] == f.source['evidenceStage'])
                          ? const BoolAnswer(true)
                          : null,
                  }, source: 'evidence');
                },
              ),
              const SizedBox(height: 20),
              Text(saved, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: editable && !busy && !recording ? review : null,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review closure & sources'),
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    limit?.cancel();
    unawaited(audio?.close());
    spokenQuestions?.clear();
    narrative.dispose();
    super.dispose();
  }
}
