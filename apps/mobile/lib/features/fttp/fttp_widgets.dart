import '../../core/design_system/theme.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../app/app_controller.dart';
import '../../core/contracts.dart';
import '../jobs/work_order.dart';
import '../jobs/visit_progress.dart';
import 'fttp_workflow.dart';
import 'evidence_capture.dart';

class FttpToday extends ConsumerWidget {
  const FttpToday({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('FTTP · SERVICE DELIVERY DEMO'),
            const SizedBox(height: 10),
            Text(
              app.form?.source['closurePolicy'] != null
                  ? 'Your next field visit.'
                  : 'Your next installation.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Synthetic UK jobs · downloaded briefs and drafts stay available offline.',
            ),
            const SizedBox(height: 12),
            for (final job in app.workOrders.where(
              (j) => !VisitProgress(
                j,
                app.reports,
                app.summarySubmissions,
              ).inCompleted,
            ))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cable_rounded),
                title: Text(job.title),
                subtitle: Text(job.statusLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/jobs/${job.id}'),
              ),
            if (app.workOrders.isEmpty)
              const Text(
                'Refresh assignments to download the two demonstration jobs.',
              ),
          ],
        ),
      ),
    );
  }
}

class FttpBrief extends StatelessWidget {
  const FttpBrief({super.key, required this.job});
  final WorkOrder job;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('OFFLINE JOB PACK'),
          const SizedBox(height: 10),
          Text(job.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(job.site),
          const Divider(height: 28),
          Text(job.instructions, style: const TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          const Text(
            'Demonstration workflow. Job details, procedures and completion rules must be agreed with Openreach before operational use.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class FttpEvidencePanel extends ConsumerStatefulWidget {
  const FttpEvidencePanel({
    super.key,
    required this.report,
    this.onSaved,
    this.closure = false,
  });
  final Future<void> Function(List<Json>)? onSaved;
  final bool closure;
  final LocalReport report;
  @override
  ConsumerState<FttpEvidencePanel> createState() => _FttpEvidencePanelState();
}

class _FttpEvidencePanelState extends ConsumerState<FttpEvidencePanel> {
  List<Json> items = [];
  String stage = 'before', error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant FttpEvidencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.revision != widget.report.revision) load();
  }

  Future<void> load() async {
    try {
      final value = await ref
          .read(appProvider.notifier)
          .repository
          .evidence(widget.report.id);
      if (mounted) setState(() => items = value);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not open saved evidence. Reopen this draft.',
        );
      }
    }
  }

  Future<void> save(List<Json> next) async {
    await ref.read(appProvider.notifier).assertAccess();
    await ref
        .read(appProvider.notifier)
        .repository
        .saveEvidence(widget.report.id, next);
    if (mounted) setState(() => items = next);
    await widget.onSaved?.call(next);
  }

  Future<void> add(bool synthetic) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    final owner = ref.read(appProvider).user?.id;
    try {
      await ref.read(appProvider.notifier).assertAccess();
      if (!mounted) return;
      final bytes = synthetic
          ? await illustration(stage)
          : await Navigator.of(context).push<Uint8List>(
              MaterialPageRoute(builder: (_) => const EvidenceCapture()),
            );
      if (bytes == null) return;
      await ref.read(appProvider.notifier).assertAccess();
      if (ref.read(appProvider).user?.id != owner) {
        throw StateError('Unlock the original account and retry.');
      }
      final photo = <String, dynamic>{
        'id': const Uuid().v4(),
        'stage': stage,
        'caption': synthetic
            ? 'DEMO ILLUSTRATION · ${evidenceLabels[stage]}'
            : evidenceLabels[stage]!,
        'mimeType': synthetic ? 'image/png' : 'image/jpeg',
        'data': base64Encode(bytes),
        'sha256': sha256.convert(bytes).toString(),
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'synthetic': synthetic,
      };
      await save([...items.where((e) => e['stage'] != stage), photo]);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save this evidence. Your existing photos are retained; unlock the workspace and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        widget.closure
            ? 'Attach the evidence requested by the applicable checks. Images stay encrypted until confirmation and sync.'
            : 'Completed installs need before-work, installed-equipment and test-result images. Blocked or partial work needs blocker evidence. Images remain encrypted on this device until you confirm and sync.',
      ),
      const SizedBox(height: 16),
      for (final e in items)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.memory(
                  base64Decode(e['data'] as String),
                  height: 160,
                  fit: BoxFit.contain,
                  semanticLabel: e['caption'] as String,
                ),
                Text(e['caption'] as String),
                if (e['synthetic'] == true)
                  const Text(
                    'Synthetic illustration · not a site photograph',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                if (widget.report.state == ReportState.draft)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            try {
                              await save(
                                items.where((x) => x['id'] != e['id']).toList(),
                              );
                            } catch (_) {
                              if (mounted) {
                                setState(
                                  () => error =
                                      'Could not remove this photo. Reopen the draft and retry.',
                                );
                              }
                            }
                          },
                    child: const Text('Remove image'),
                  ),
              ],
            ),
          ),
        ),
      if (widget.report.state == ReportState.draft) ...[
        DropdownButtonFormField<String>(
          initialValue: stage,
          decoration: const InputDecoration(labelText: 'Evidence category'),
          items: evidenceStages
              .map(
                (s) =>
                    DropdownMenuItem(value: s, child: Text(evidenceLabels[s]!)),
              )
              .toList(),
          onChanged: busy ? null : (s) => setState(() => stage = s!),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : () => add(false),
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(busy ? 'Saving evidence…' : 'Take site photo'),
        ),
        TextButton.icon(
          onPressed: busy ? null : () => add(true),
          icon: const Icon(Icons.science_outlined),
          label: const Text('Attach labelled demo illustration'),
        ),
        const Text(
          'The simulator has no camera. Demo illustrations are visibly labelled and remain labelled in supervisor review.',
          style: TextStyle(fontSize: 12),
        ),
      ],
      ErrorNotice(error),
    ],
  );
}

Future<Uint8List> illustration(String stage) async {
  final recorder = ui.PictureRecorder();
  // Record a self-contained diagram rather than implying a real site photograph.
  final drawing = Canvas(recorder, const Rect.fromLTWH(0, 0, 640, 360));
  drawing.drawColor(const Color(0xffeef0fa), BlendMode.src);
  drawing.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(65, 100, 575, 245),
      const Radius.circular(18),
    ),
    Paint()..color = const Color(0xffd9d3fa),
  );
  drawing.drawLine(
    const Offset(120, 170),
    const Offset(400, 170),
    Paint()
      ..color = const Color(0xff6550bd)
      ..strokeWidth = 8,
  );
  drawing.drawRect(
    const Rect.fromLTWH(370, 130, 140, 90),
    Paint()..color = Colors.white,
  );
  for (final (text, y, size) in [
    ('DEMO · ILLUSTRATION', 24.0, 28.0),
    (evidenceLabels[stage]!, 70.0, 22.0),
    ('Fictional FTTP evidence — no live network', 286.0, 20.0),
  ]) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xff282342),
          fontSize: size,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 600);
    painter.paint(drawing, Offset(24, y));
  }
  final picture = recorder.endRecording(),
      image = await picture.toImage(640, 360);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Answers fttpExample(bool blocked) => decodeAnswers(
  blocked
      ? {
          'installation_outcome': 'blocked',
          'work_performed':
              'SYNTHETIC DEMO: inspected the accessible duct entry; installation did not proceed.',
          'connectivity_test': 'not_tested',
          'exception_reason':
              'SYNTHETIC DEMO: duct obstruction prevents the fibre pull.',
          'next_team': 'civils',
          'next_action':
              'SYNTHETIC DEMO: civils coordinator to inspect and clear the obstruction, then arrange customer access for a return installation visit.',
        }
      : {
          'installation_outcome': 'completed',
          'access_confirmed': true,
          'route_agreed': true,
          'site_checks': true,
          'work_performed':
              'SYNTHETIC DEMO: installed fibre to the agreed entry point, fitted the ONT and demonstrated the service.',
          'cable_id': 'DEMO-CBL-101',
          'csp_reference': 'DEMO-CSP-101',
          'cable_installed': {'amount': 12, 'unit': 'm'},
          'ont_serial': 'DEMO-ONT-101',
          'optical_reading': -22.4,
          'connectivity_test': 'passed',
          'tester_reference': 'DEMO-TEST-101',
          'customer_handover': true,
          'site_tidy': true,
        },
);
