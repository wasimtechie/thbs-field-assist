import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/workspace.dart';
import '../voice/voice_coordinator.dart';
import 'cable_label.dart';

List<FieldDefinition> missingCableDetails(FormDefinition form, Answers values) {
  final issues = validate(form, values, requireComplete: false).issues;
  return scannableFields(form, values)
      .where(
        (f) => missing(values[f.id]) || issues.any((i) => i.fieldId == f.id),
      )
      .toList();
}

/// The signed form's camera/touch fields keep their entry policy. The assistant
/// guides this step without opening a microphone or inventing label values.
class CableIntakeScreen extends StatefulWidget {
  const CableIntakeScreen({
    super.key,
    required this.form,
    required this.readValues,
    required this.voice,
    required this.onScan,
    required this.onSave,
  });
  final FormDefinition form;
  final Answers Function() readValues;
  final VoiceCoordinator voice;
  final Future<bool> Function() onScan;
  final Future<void> Function(Answers) onSave;
  @override
  State<CableIntakeScreen> createState() => _CableIntakeScreenState();
}

class _CableIntakeScreenState extends State<CableIntakeScreen> {
  static const introduction =
      'Do you have the cable or drum label? You can scan it to fill the cable details.';
  bool working = false, reviewed = false;
  String error = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.voice.presentPrompt(introduction));
    });
  }

  Future<void> _details({required bool scan}) async {
    if (working) return;
    setState(() {
      working = true;
      error = '';
    });
    try {
      await widget.voice.pause();
      if (!mounted) return;
      if (scan) {
        if (!await widget.onScan()) return;
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => CableDetailsScreen(
              form: widget.form,
              readValues: widget.readValues,
              onSave: widget.onSave,
              voice: widget.voice,
            ),
          ),
        );
        if (!mounted) return;
      }
      if (!mounted) return;
      setState(() => reviewed = true);
      final remaining = missingCableDetails(widget.form, widget.readValues());
      unawaited(
        widget.voice.presentPrompt(
          remaining.isEmpty
              ? 'Your cable details are saved. Continue to the work questions when you are ready.'
              : 'Your saved cable details are ready. You can add missing details, or continue to the work questions.',
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _leave(bool continueVoice) async {
    if (working) return;
    await widget.voice.pause();
    if (mounted) Navigator.pop(context, continueVoice);
  }

  @override
  Widget build(BuildContext context) {
    final values = widget.readValues();
    final fields = scannableFields(widget.form, values);
    final missingFields = missingCableDetails(widget.form, values);
    final saved = fields
        .where((f) => !missingFields.any((m) => m.id == f.id))
        .toList();
    return PopScope(
      canPop: !working,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Field Assist Voice'),
          leading: IconButton(
            tooltip: 'Return to form',
            onPressed: working ? null : () => _leave(false),
            icon: const MotionIcon(Icons.close_rounded),
          ),
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: widget.voice,
            builder: (context, _) => Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Center(
                        child: StatusPill(
                          'Cable identification',
                          icon: Icons.document_scanner_outlined,
                          color: context.colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: AssistantOrb(
                          size: 112,
                          active: widget.voice.state == VoiceState.speaking,
                          level: widget.voice.level,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        reviewed
                            ? 'Cable details, ready for your review.'
                            : introduction,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Scan and check the printed label, or choose the missing details you can enter. Work questions come next.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (saved.isNotEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${saved.length} of ${fields.length} cable details saved',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                for (final field in saved)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '${field.label}: ${field.display(values[field.id])}',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (reviewed && missingFields.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            '${missingFields.length} details remain. Enter only what you can verify; optional details can stay blank.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.colors.muted),
                          ),
                        ),
                      ErrorNotice(error),
                      if (widget.voice.error.isNotEmpty)
                        const ErrorNotice(
                          'The spoken introduction is unavailable. You can continue using these options.',
                          isInfo: true,
                        ),
                      if (working)
                        const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: working ? null : () => _details(scan: true),
                        icon: const MotionIcon(Icons.document_scanner_outlined),
                        label: const Text('Scan label'),
                      ),
                      if (missingFields.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: working
                              ? null
                              : () => _details(scan: false),
                          icon: const MotionIcon(Icons.edit_outlined),
                          label: Text(
                            reviewed ? 'Add missing details' : 'Enter details',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (reviewed)
                        FilledButton.icon(
                          onPressed: working ? null : () => _leave(true),
                          icon: const MotionIcon(Icons.arrow_forward_rounded),
                          label: const Text('Continue to work questions'),
                        )
                      else
                        TextButton(
                          onPressed: working ? null : () => _leave(true),
                          child: const Text('Not available'),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Reviewed details save locally · Camera opens only when you choose',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.colors.muted,
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
    );
  }
}

class CableDetailsScreen extends StatefulWidget {
  const CableDetailsScreen({
    super.key,
    required this.form,
    required this.readValues,
    required this.onSave,
    required this.voice,
  });
  final FormDefinition form;
  final Answers Function() readValues;
  final Future<void> Function(Answers) onSave;
  final VoiceCoordinator voice;
  @override
  State<CableDetailsScreen> createState() => _CableDetailsScreenState();
}

class _CableDetailsScreenState extends State<CableDetailsScreen> {
  late final fields = missingCableDetails(widget.form, widget.readValues());
  final selected = <String>{};
  final input = TextEditingController();
  List<FieldDefinition>? questions;
  int index = 0;
  bool saving = false;
  String error = '';
  FieldDefinition? get current => questions == null ? null : questions![index];
  String _question(FieldDefinition field) => switch (field.scanTarget) {
    'manufacturer' => 'Who manufactured this cable?',
    'fibre_count' => 'How many fibres or cores are printed on the label?',
    'specification' => 'What cable specification is printed on the label?',
    'declared_length' =>
      'What cable length is printed on the label? Include metres or kilometres. This is separate from the installed length.',
    'manufactured_date' =>
      'What is the manufacture date? Enter year, month and day.',
    _ =>
      'What is the ${field.label.toLowerCase()}? Enter it exactly as printed, including leading zeros.',
  };
  Future<void> _begin() async {
    await widget.voice.pause();
    if (!mounted) return;
    setState(
      () => questions = fields.where((f) => selected.contains(f.id)).toList(),
    );
    if (questions!.isNotEmpty) {
      unawaited(widget.voice.presentPrompt(_question(current!)));
    }
  }

  Future<void> _next({bool skip = false}) async {
    final field = current;
    if (saving || field == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await widget.voice.pause();
      if (!skip) {
        final value = decodeLabelEntry(field, input.text);
        if (value == null) {
          throw FormatException(
            'Enter ${field.label} as printed. Include m/km for length or YYYY-MM-DD for a date.',
          );
        }
        final issues = validate(widget.form, {
          ...widget.readValues(),
          field.id: value,
        }, requireComplete: false).issues;
        final issue = issues.where((i) => i.fieldId == field.id).firstOrNull;
        if (issue != null) throw FormatException(issue.message);
        await widget.onSave({field.id: value});
      }
      if (!mounted) return;
      if (index + 1 >= questions!.length) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        index++;
        input.clear();
      });
      unawaited(widget.voice.presentPrompt(_question(current!)));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = current;
    return PopScope(
      canPop: !saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(field == null ? 'Choose cable details' : 'Cable details'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (field == null) ...[
                      Text(
                        'Which missing details can you provide?',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Choose only details you can verify. The assistant reads each selected prompt; enter the label text by touch. Already saved fields are left intact.',
                        style: TextStyle(
                          color: context.colors.muted,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final f in fields)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(f.label),
                          value: selected.contains(f.id),
                          onChanged: (value) => setState(() {
                            value == true
                                ? selected.add(f.id)
                                : selected.remove(f.id);
                          }),
                        ),
                    ] else ...[
                      Eyebrow('Detail ${index + 1} of ${questions!.length}'),
                      const SizedBox(height: 16),
                      Text(
                        _question(field),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: input,
                        enabled: !saving,
                        keyboardType: field.kind == FieldKind.integer
                            ? TextInputType.number
                            : field.kind == FieldKind.date
                            ? TextInputType.datetime
                            : TextInputType.text,
                        decoration: InputDecoration(
                          labelText: field.label,
                          hintText: field.kind == FieldKind.quantity
                              ? 'e.g. 1000 m'
                              : field.kind == FieldKind.date
                              ? 'YYYY-MM-DD'
                              : 'Exactly as printed',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Review the characters before saving. Each accepted detail is saved on this device.',
                        style: TextStyle(
                          color: context.colors.muted,
                          height: 1.6,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: saving
                            ? null
                            : () =>
                                  widget.voice.presentPrompt(_question(field)),
                        icon: const MotionIcon(Icons.volume_up_outlined),
                        label: const Text('Hear question again'),
                      ),
                      ErrorNotice(error),
                    ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (field == null)
                      FilledButton(
                        onPressed: selected.isEmpty ? null : _begin,
                        child: const Text('Enter selected details'),
                      )
                    else ...[
                      FilledButton(
                        onPressed: saving ? null : _next,
                        child: Text(
                          saving
                              ? 'Saving…'
                              : index + 1 == questions!.length
                              ? 'Save & continue'
                              : 'Save & next',
                        ),
                      ),
                      TextButton(
                        onPressed: saving ? null : () => _next(skip: true),
                        child: const Text('Skip this detail'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
