import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../../core/location/location_capture.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/workspace.dart';
import '../voice/voice_coordinator.dart';
import '../voice/voice_session_screen.dart';
import '../voice/voice_audio.dart';
import '../label_scan/cable_label.dart';
import '../label_scan/cable_scan_screen.dart';
import '../label_scan/cable_intake_screen.dart';

final cableScanPageProvider =
    Provider<Widget Function(FormDefinition, Answers)>(
      (ref) =>
          (form, existing) => CableScanScreen(form: form, existing: existing),
    );

class FormScreen extends ConsumerStatefulWidget {
  const FormScreen({super.key, required this.reportId});
  final String reportId;
  @override
  ConsumerState<FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends ConsumerState<FormScreen>
    with WidgetsBindingObserver {
  LocalReport? report;
  Answers values = {};
  String error = '', saveStatus = 'Loading…';
  int voiceRevision = 0, _saveSequence = 0;
  bool scanOpening = false;
  Future<void> _tail = Future.value();
  Answers? undo;
  VoiceCoordinator? coordinator;
  final scroll = ScrollController();
  final fieldKeys = <String, GlobalKey>{};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      await ref.read(appProvider.notifier).assertAccess();
      final r = await ref
          .read(appProvider.notifier)
          .repository
          .get(widget.reportId);
      if (mounted) {
        setState(() {
          report = r;
          values = {...r.values};
          voiceRevision++;
          saveStatus = 'Saved on this device';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  void _change(String id, Answer? answer) {
    final next = {...values, id: answer};
    setState(() => values = next);
    _save(next);
  }

  Future<void> _save(Answers snapshot, {String source = 'manual'}) {
    final sequence = ++_saveSequence;
    setState(() {
      saveStatus = 'Saving…';
      error = '';
    });
    final operation = _tail.catchError((_) {}).then((_) async {
      try {
        final app = ref.read(appProvider.notifier);
        await app.assertAccess();
        final saved = await app.repository.save(
          widget.reportId,
          snapshot,
          source: source,
        );
        if (mounted) {
          setState(() {
            report = saved;
            if (sequence == _saveSequence) saveStatus = 'Saved on this device';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            error = e.toString();
            saveStatus = 'Not saved · retry required';
          });
        }
        rethrow;
      }
    });
    _tail = operation;
    unawaited(operation.catchError((_) {}));
    return operation;
  }

  Future<bool> _scanLabel({
    bool propagateError = false,
    bool showAcknowledgement = true,
  }) async {
    final current = report;
    if (scanOpening || current == null || current.state != ReportState.draft) {
      return false;
    }
    setState(() => scanOpening = true);
    try {
      await _tail;
      await coordinator?.pause();
      final app = ref.read(appProvider.notifier);
      await app.assertAccess();
      final owner = ref.read(appProvider).user?.id;
      if (!mounted) return false;
      final patch = await Navigator.of(context).push<Answers>(
        MaterialPageRoute(
          builder: (_) => ref.read(cableScanPageProvider)(
            current.schema,
            Map.unmodifiable(values),
          ),
        ),
      );
      if (!mounted || patch == null || patch.isEmpty) return false;
      await app.assertAccess();
      final state = ref.read(appProvider);
      if (state.stage != AccessStage.ready || state.user?.id != owner) {
        throw StateError(
          'Unlock the original account and scan again. Existing answers are retained.',
        );
      }
      final before = Map<String, Answer?>.from(values);
      final next = {...values, ...patch};
      await _save(next, source: 'camera_ocr_reviewed');
      if (!mounted) return false;
      setState(() {
        undo = before;
        values = {...report!.values};
        voiceRevision++;
      });
      if (showAcknowledgement) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${patch.length} cable details saved on this device.',
            ),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      if (propagateError) rethrow;
      return false;
    } finally {
      if (mounted) setState(() => scanOpening = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        !(state == AppLifecycleState.inactive &&
            coordinator?.awaitingPermission == true)) {
      unawaited(coordinator?.pause());
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider);
    final r = report;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your report')),
        body: error.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: ErrorNotice(error),
              )
            : const Center(child: CircularProgressIndicator()),
      );
    }
    final validation = validate(r.schema, values);
    final job = app.workOrders.where((j) => j.id == r.workOrderId).firstOrNull;
    final visible = r.schema.visibleFields(values);
    final valid = visible
        .where(
          (f) =>
              !missing(values[f.id]) &&
              !validation.issues.any((i) => i.fieldId == f.id),
        )
        .length;
    final requiredFields = visible.where((f) => f.required).toList();
    final requiredComplete = requiredFields
        .where(
          (f) =>
              !missing(values[f.id]) &&
              !validation.issues.any((i) => i.fieldId == f.id),
        )
        .length;
    final cableFields = scannableFields(r.schema, values);
    final cableComplete =
        cableFields.length - missingCableDetails(r.schema, values).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.schema.title, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            cableFields.isEmpty
                ? 40
                : 24 + MediaQuery.textScalerOf(context).scale(30),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(23, 0, 23, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cableFields.isEmpty
                            ? '$valid of ${visible.length} fields complete'
                            : 'Required: $requiredComplete/${requiredFields.length} complete',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.muted,
                        ),
                      ),
                      if (cableFields.isNotEmpty)
                        Text(
                          'Cable: $cableComplete/${cableFields.length} · ${cableFields.any((f) => f.required) ? 'label details' : 'optional'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  'v${r.schema.versionNumber}',
                  style: TextStyle(fontSize: 11, color: context.colors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(
                end: cableFields.isEmpty
                    ? visible.isEmpty
                          ? 0
                          : valid / visible.length
                    : requiredFields.isEmpty
                    ? 1
                    : requiredComplete / requiredFields.length,
              ),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                color: context.colors.teal,
                backgroundColor: context.colors.raised,
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                key: PageStorageKey(widget.reportId),
                padding: const EdgeInsets.fromLTRB(23, 22, 23, 35),
                children: [
                  ErrorNotice(error),
                  if (job != null)
                    Card(
                      child: ListTile(
                        leading: MotionIcon(
                          Icons.assignment_outlined,
                          color: context.colors.indigo,
                        ),
                        title: Text(job.title),
                        subtitle: Text(job.site),
                        trailing: const MotionIcon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/jobs/${job.id}'),
                      ),
                    ),
                  if (r.state != ReportState.draft)
                    const ErrorNotice(
                      'This report is frozen. Manage its receipt or safe reopen from the queue.',
                      isInfo: true,
                    ),
                  for (final section in r.schema.sections) ...[
                    const SizedBox(height: 6),
                    WorkspaceSection(section.label),
                    const SizedBox(height: 4),
                    if (scannableFields(
                      r.schema,
                      values,
                      sectionId: section.id,
                    ).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Container(
                          padding: const EdgeInsets.all(17),
                          decoration: BoxDecoration(
                            color: context.colors.raised,
                            border: Border.all(color: context.colors.edge),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Read it from the label.',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Capture the cable or drum label before opening it. Review the recognized details, then save them to this form.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.7,
                                  color: context.colors.muted,
                                ),
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed:
                                    r.state == ReportState.draft && !scanOpening
                                    ? _scanLabel
                                    : null,
                                icon: const MotionIcon(
                                  Icons.document_scanner_outlined,
                                ),
                                label: Text(
                                  scanOpening
                                      ? 'Opening scanner…'
                                      : 'Scan cable label',
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Works offline · Camera opens only when you choose',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: context.colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final f in visible.where(
                      (f) => f.sectionId == section.id,
                    ))
                      Container(
                        key: fieldKeys.putIfAbsent(f.id, () => GlobalKey()),
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: context.colors.panel,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: context.colors.edge.withValues(alpha: .5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      text: f.label,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: context.colors.ink,
                                      ),
                                      children: [
                                        if (f.required)
                                          TextSpan(
                                            text: ' *',
                                            style: TextStyle(
                                              color: context.colors.danger,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (f.voiceEnabled)
                                  Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: MotionIcon(
                                      Icons.mic_none_rounded,
                                      size: 16,
                                      color: context.colors.teal,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            AnswerInput(
                              key: ValueKey('${f.id}:$voiceRevision'),
                              field: f,
                              value: values[f.id],
                              enabled: r.state == ReportState.draft,
                              onChanged: (v) => _change(f.id, v),
                            ),
                            if (validation.issues.any(
                                  (i) => i.fieldId == f.id,
                                ) &&
                                !missing(values[f.id]))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  validation.issues
                                      .firstWhere((i) => i.fieldId == f.id)
                                      .message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.colors.danger,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (undo != null)
                    OutlinedButton.icon(
                      onPressed: () async {
                        final prior = undo!;
                        setState(() {
                          values = prior;
                          undo = null;
                          voiceRevision++;
                        });
                        await _save(prior, source: 'undo');
                      },
                      icon: const MotionIcon(Icons.undo_rounded, size: 18),
                      label: const Text('Undo last assisted change'),
                    ),
                  if (saveStatus.startsWith('Not saved'))
                    OutlinedButton.icon(
                      onPressed: () => _save(values),
                      icon: const MotionIcon(Icons.refresh_rounded),
                      label: const Text('Retry saving'),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 13, 20, 0),
              decoration: BoxDecoration(
                color: context.colors.panel,
                border: Border(top: BorderSide(color: context.colors.edge)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MotionIcon(
                            saveStatus.startsWith('Saved')
                                ? Icons.check_circle_outline_rounded
                                : Icons.cloud_off_rounded,
                            size: 13,
                            color: saveStatus.startsWith('Saved')
                                ? context.colors.teal
                                : context.colors.muted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            saveStatus,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: r.state != ReportState.draft
                                ? null
                                : () => _voiceSheet(app),
                            icon: MotionIcon(
                              Icons.mic_none_rounded,
                              color: context.colors.teal,
                            ),
                            label: Text(
                              'Fill by voice',
                              style: TextStyle(
                                color: context.colors.teal,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: r.state != ReportState.draft
                                ? null
                                : () async {
                                    try {
                                      await _tail;
                                      if (!context.mounted) return;
                                      final field = await context.push<String>(
                                        '/review/${r.id}',
                                      );
                                      if (field != null &&
                                          context.mounted &&
                                          fieldKeys[field]?.currentContext !=
                                              null) {
                                        Scrollable.ensureVisible(
                                          fieldKeys[field]!.currentContext!,
                                          duration:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 250,
                                                ),
                                          alignment: .15,
                                        );
                                      }
                                    } catch (_) {}
                                  },
                            icon: const MotionIcon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Review',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _voiceSheet(AppState app) async {
    try {
      await ref.read(appProvider.notifier).assertAccess();
    } catch (e) {
      setState(() => error = e.toString());
      return;
    }
    if (!mounted) return;
    if (!app.voiceReady) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (c) => Padding(
          padding: const EdgeInsets.fromLTRB(25, 12, 25, 35),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MotionIcon(
                Icons.mic_off_outlined,
                size: 35,
                color: context.colors.teal,
              ),
              const SizedBox(height: 18),
              const Text(
                'Voice is not ready on this device',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Text(
                'Continue by touch. You can repair the local voice package online from Settings. There is no cloud speech fallback.',
                style: TextStyle(color: context.colors.muted, height: 1.8),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Continue by touch'),
              ),
            ],
          ),
        ),
      );
      return;
    }
    await _tail;
    coordinator = VoiceCoordinator(
      engine: ref.read(appProvider.notifier).voice,
      schema: report!.schema,
      readValues: () => values,
      playback: app.playback,
      speed: app.speechRate,
      speech: ref.read(appProvider.notifier).promptAudio,
      audio: ref.read(voiceAudioFactoryProvider)(),
      onPatch: (patch, source) async {
        final old = {...values};
        await _save(patch.values, source: source);
        if (mounted) {
          setState(() {
            undo = old;
            values = {...report!.values};
            voiceRevision++;
          });
        }
      },
    );
    if (!mounted) return;
    final session = coordinator!;
    if (missingCableDetails(report!.schema, values).isNotEmpty) {
      final continueVoice = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CableIntakeScreen(
            form: report!.schema,
            readValues: () => values,
            voice: session,
            onScan: () =>
                _scanLabel(propagateError: true, showAcknowledgement: false),
            onSave: (patch) async {
              final before = {...values};
              await _save({...values, ...patch}, source: 'manual');
              if (mounted) {
                setState(() {
                  undo = before;
                  values = {...report!.values};
                  voiceRevision++;
                });
              }
            },
          ),
        ),
      );
      await session.pause();
      if (continueVoice != true || !mounted) {
        await session.shutdown();
        coordinator = null;
        if (mounted) await ref.read(appProvider.notifier).reloadReports();
        return;
      }
    }
    final review = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            VoiceSessionScreen(coordinator: session, schema: report!.schema),
      ),
    );
    await session.shutdown();
    coordinator = null;
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    await ref.read(appProvider.notifier).reloadReports();
    if (review == true && mounted) {
      final field = await context.push<String>('/review/${report!.id}');
      if (mounted &&
          field != null &&
          fieldKeys[field]?.currentContext != null) {
        await Scrollable.ensureVisible(
          fieldKeys[field]!.currentContext!,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 250),
          alignment: .15,
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    scroll.dispose();
    unawaited(coordinator?.shutdown());
    super.dispose();
  }
}

class AnswerInput extends StatelessWidget {
  const AnswerInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final FieldDefinition field;
  final Answer? value;
  final ValueChanged<Answer?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final f = field;
    if (f.kind == FieldKind.boolean) {
      return Row(
        children: [
          for (final b in [true, false])
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: b ? 7 : 0, left: b ? 0 : 7),
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor:
                        value is BoolAnswer && (value as BoolAnswer).value == b
                        ? context.colors.raised
                        : context.colors.panel,
                    side: BorderSide(
                      color:
                          value is BoolAnswer &&
                              (value as BoolAnswer).value == b
                          ? context.colors.indigo
                          : context.colors.edge,
                    ),
                  ),
                  onPressed: enabled ? () => onChanged(BoolAnswer(b)) : null,
                  icon: MotionIcon(
                    b ? Icons.check_rounded : Icons.close_rounded,
                    size: 18,
                  ),
                  label: Text(b ? 'Yes' : 'No'),
                ),
              ),
            ),
        ],
      );
    }
    if (f.kind == FieldKind.singleSelect) {
      return DropdownButtonFormField<String>(
        initialValue:
            value is TextAnswer &&
                f.options.any((o) => o.id == (value as TextAnswer).value)
            ? (value as TextAnswer).value
            : null,
        isExpanded: true,
        decoration: const InputDecoration(hintText: 'Select an option'),
        items: f.options
            .map(
              (o) => DropdownMenuItem(
                value: o.id,
                child: Text(o.label, style: const TextStyle(fontSize: 16)),
              ),
            )
            .toList(),
        onChanged: enabled
            ? (v) => onChanged(v == null ? null : TextAnswer(v))
            : null,
      );
    }
    if (f.kind == FieldKind.quantity) {
      final q = value is QuantityAnswer ? value as QuantityAnswer : null;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              initialValue: q?.amount.toString() ?? '',
              enabled: enabled,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(hintText: 'Enter amount'),
              onChanged: (s) {
                if (s.isEmpty) {
                  onChanged(null);
                  return;
                }
                final number = num.tryParse(s);
                if (number != null) {
                  onChanged(
                    QuantityAnswer(number, q?.unit ?? f.canonicalUnit!),
                  );
                }
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 95,
            child: DropdownButtonFormField<String>(
              initialValue: q?.unit ?? f.canonicalUnit,
              items: f.units
                  .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                  .toList(),
              onChanged: enabled
                  ? (u) {
                      if (u != null && q != null) {
                        onChanged(QuantityAnswer(q.amount, u));
                      }
                    }
                  : null,
            ),
          ),
        ],
      );
    }
    final numeric = [FieldKind.decimal, FieldKind.integer].contains(f.kind);
    return TextFormField(
      initialValue: value == null
          ? ''
          : value is TextAnswer
          ? (value as TextAnswer).value
          : value is NumberAnswer
          ? (value as NumberAnswer).value.toString()
          : '',
      enabled: enabled,
      maxLines: f.kind == FieldKind.longText ? 4 : 1,
      maxLength: f.constraints['maxLength'] as int?,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : f.kind == FieldKind.date
          ? TextInputType.datetime
          : f.kind == FieldKind.longText
          ? TextInputType.multiline
          : TextInputType.text,
      decoration: InputDecoration(
        hintText: f.kind == FieldKind.date
            ? 'YYYY-MM-DD'
            : numeric
            ? 'Enter a number'
            : 'Enter details…',
        counterText: '',
      ),
      onChanged: (s) {
        if (s.isEmpty) {
          onChanged(null);
        } else if (numeric) {
          final n = num.tryParse(s);
          if (n != null) onChanged(NumberAnswer(n));
        } else {
          onChanged(TextAnswer(s));
        }
      },
    );
  }
}

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.reportId});
  final String reportId;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  LocalReport? report;
  bool confirmed = false, busy = false;
  String error = '';
  LocationCaptureFailure? locationError;
  LocationCaptureStage locationStage = LocationCaptureStage.permission;
  @override
  void initState() {
    super.initState();
    ref
        .read(appProvider.notifier)
        .repository
        .get(widget.reportId)
        .then((r) {
          if (mounted) setState(() => report = r);
        })
        .catchError((Object e) {
          if (mounted) setState(() => error = e.toString());
        });
  }

  @override
  Widget build(BuildContext context) {
    final r = report;
    if (r == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review report')),
        body: error.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(24),
                child: ErrorNotice(error),
              ),
      );
    }
    final result = validate(r.schema, r.values);
    return Scaffold(
      appBar: AppBar(title: const Text('Review your report')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(23),
          children: [
            const Eyebrow('One last look'),
            const SizedBox(height: 10),
            Text(r.schema.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Version ${r.schema.versionNumber}',
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 25),
            ErrorNotice(error),
            if (locationError?.canOpenSettings == true)
              TextButton.icon(
                onPressed: () async {
                  try {
                    await const LocationCapture().openSettings(
                      deviceLocation:
                          locationError?.code == 'LOCATION_DISABLED',
                    );
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => error =
                            'Open device Settings and allow Field Assist location access. Your draft is saved.',
                      );
                    }
                  }
                },
                icon: const Icon(Icons.settings_outlined),
                label: Text(
                  locationError?.code == 'LOCATION_DISABLED'
                      ? 'Open location settings'
                      : 'Open app permissions',
                ),
              ),
            if (!result.valid)
              ErrorNotice(
                '${result.issues.length} fields need your attention before this report can be confirmed.',
              ),
            for (final field in r.schema.visibleFields(r.values))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 17,
                      vertical: 7,
                    ),
                    title: Text(
                      field.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.muted,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.issues.any((i) => i.fieldId == field.id)
                                ? result.issues
                                      .firstWhere((i) => i.fieldId == field.id)
                                      .message
                                : field.display(r.values[field.id]),
                            style: TextStyle(
                              fontSize: 16,
                              color:
                                  result.issues.any(
                                    (i) => i.fieldId == field.id,
                                  )
                                  ? context.colors.danger
                                  : context.colors.ink,
                              height: 1.5,
                            ),
                          ),
                          if (r.provenance[field.id] case final List history
                              when history.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                switch ((history.last as Map)['source']) {
                                  'voice' =>
                                    'Added by voice · Check before confirming',
                                  'undo' => 'Restored with undo',
                                  _ => 'Entered by touch',
                                },
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.colors.muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Edit ${field.label}',
                      onPressed: () => context.pop(field.id),
                      icon: const MotionIcon(Icons.edit_outlined, size: 19),
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
            if (result.excluded.isNotEmpty)
              ErrorNotice(
                '${result.excluded.length} populated fields are hidden by the current answers. They are excluded from this report and kept only in draft history.',
                isInfo: true,
              ),
            const SizedBox(height: 13),
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.location_on_outlined,
                  color: context.colors.teal,
                ),
                title: const Text('Location required'),
                subtitle: const Text(
                  'When you confirm, allow location access and keep device location on. Coordinates, accuracy and capture time are saved securely with this report and shared with your team when it syncs.',
                ),
                isThreeLine: true,
              ),
            ),
            const SizedBox(height: 13),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: confirmed,
              onChanged: (v) => setState(() => confirmed = v ?? false),
              title: const Text(
                'I have reviewed these details and confirm they accurately describe my work.',
                style: TextStyle(fontSize: 14, height: 1.6),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: !confirmed || !result.valid || busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        error = '';
                        locationError = null;
                        locationStage = LocationCaptureStage.permission;
                      });
                      try {
                        final app = ref.read(appProvider.notifier);
                        await app.confirmReport(
                          r.id,
                          onLocationStage: (stage) {
                            if (mounted) setState(() => locationStage = stage);
                          },
                        );
                        if (context.mounted) context.go('/receipt/${r.id}');
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            error = e.toString();
                            locationError = e is LocationCaptureFailure
                                ? e
                                : null;
                          });
                        }
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
              icon: const MotionIcon(Icons.check_rounded),
              label: Text(
                busy
                    ? locationStage == LocationCaptureStage.permission
                          ? 'Checking location permission…'
                          : 'Finding your location and saving…'
                    : 'Confirm with location',
              ),
            ),
            const SizedBox(height: 17),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Allow access if your phone asks. If access is already allowed, no permission pop-up is needed. Please keep this screen open; one tap is enough.',
                  textAlign: TextAlign.center,
                ),
              ),
            Text(
              'This commits the report on your device. Server acceptance is shown separately after synchronization.',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.muted,
                height: 1.7,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
