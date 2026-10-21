import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../../core/location/location_capture.dart';
import 'cable_label.dart';

class CableScanScreen extends StatefulWidget {
  const CableScanScreen({
    super.key,
    required this.form,
    required this.existing,
    this.reader = const NativeLabelReader(),
  });
  final FormDefinition form;
  final Answers existing;
  final LabelReader reader;
  @override
  State<CableScanScreen> createState() => _CableScanScreenState();
}

class _CableScanScreenState extends State<CableScanScreen>
    with WidgetsBindingObserver {
  CameraController? camera;
  File? photo;
  CableLabelReadout? readout;
  bool opening = false, busy = false, torch = false;
  String error = '';
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _clearPhoto() async {
    final file = photo;
    photo = null;
    if (file != null) {
      await FileImage(file).evict();
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _releaseCamera() async {
    final old = camera;
    camera = null;
    await old?.dispose();
  }

  Future<void> _initialize() async {
    if (opening || !mounted) return;
    final attempt = ++generation;
    setState(() {
      opening = true;
      error = '';
      torch = false;
    });
    CameraController? next;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw const FormatException(
          'This device has no available camera. Enter the cable details manually.',
        );
      }
      final description =
          cameras
              .where((c) => c.lensDirection == CameraLensDirection.back)
              .firstOrNull ??
          cameras.first;
      next = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await next.initialize();
      if (!mounted || attempt != generation) {
        await next.dispose();
        return;
      }
      camera = next;
    } catch (e) {
      await next?.dispose();
      if (mounted && attempt == generation) {
        error = e is CameraException
            ? 'Camera access is unavailable (${e.code}). Allow camera access in Settings, or enter the details manually.'
            : e.toString().replaceFirst('FormatException: ', '');
      }
    } finally {
      if (mounted && attempt == generation) setState(() => opening = false);
    }
  }

  Future<void> _capture() async {
    final controller = camera;
    if (controller == null || busy) return;
    final attempt = generation;
    setState(() {
      busy = true;
      error = '';
    });
    File? original;
    try {
      final shot = await controller.takePicture();
      original = File(shot.path);
      if (!mounted || attempt != generation) return;
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, 'cable_label_scan'),
      );
      await dir.create(recursive: true);
      // Only this feature's stale private-cache images are reclaimed after a crash.
      await for (final item in dir.list()) {
        if (item is File &&
            DateTime.now().difference((await item.stat()).modified) >
                const Duration(minutes: 15)) {
          try {
            await item.delete();
          } catch (_) {}
        }
      }
      final owned = await original.copy(
        p.join(dir.path, '${const Uuid().v4()}.jpg'),
      );
      if (!mounted || attempt != generation) {
        await owned.delete();
        return;
      }
      photo = owned;
      await original.delete();
      original = null;
      await _releaseCamera();
      if (mounted) setState(() {});
      final text = await widget.reader.read(owned.path);
      if (!mounted || attempt != generation) return;
      setState(() => readout = CableLabelReadout.parse(text));
    } catch (e) {
      if (mounted && attempt == generation) {
        setState(
          () => error = e.toString().replaceFirst('FormatException: ', ''),
        );
      }
    } finally {
      if (original != null) {
        try {
          await original.delete();
        } catch (_) {}
      }
      if (mounted && attempt == generation) setState(() => busy = false);
    }
  }

  Future<void> _retake() async {
    generation++;
    await widget.reader.cancel();
    await _clearPhoto();
    if (!mounted) return;
    setState(() {
      readout = null;
      busy = false;
      error = '';
    });
    await _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive && !opening) {
      generation++;
      unawaited(widget.reader.cancel());
      unawaited(_releaseCamera());
      unawaited(_clearPhoto());
      if (mounted) {
        setState(() {
          busy = false;
          opening = false;
          readout = null;
          error =
              'Scanning stopped when the app left the foreground. Existing answers are retained.';
        });
      }
    } else if (state == AppLifecycleState.resumed &&
        camera == null &&
        readout == null &&
        !busy &&
        !opening) {
      unawaited(_initialize());
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.reader.cancel());
    unawaited(_releaseCamera());
    unawaited(_clearPhoto());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = readout;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          result == null ? 'Scan cable label' : 'Review scanned details',
        ),
      ),
      body: SafeArea(
        child: result != null
            ? CableLabelReview(
                form: widget.form,
                existing: widget.existing,
                readout: result,
                photo: photo,
                onRetake: _retake,
                onApply: (patch) => Navigator.pop(context, patch),
              )
            : Padding(
                padding: const EdgeInsets.all(23),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Cable identification',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w600,
                        color: context.colors.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Photograph the printed cable or drum label before opening it. Fill the frame, keep text sharp and avoid glare.',
                      style: TextStyle(
                        color: context.colors.muted,
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: ColoredBox(
                          color: context.colors.raised,
                          child: photo != null
                              ? Image.file(
                                  photo!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                                )
                              : camera?.value.isInitialized == true
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Center(child: CameraPreview(camera!)),
                                    IgnorePointer(
                                      child: Container(
                                        margin: const EdgeInsets.all(25),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: context.colors.teal,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Center(
                                  child: opening
                                      ? const CircularProgressIndicator()
                                      : const MotionIcon(
                                          Icons.camera_alt_outlined,
                                          size: 55,
                                        ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (error.isNotEmpty) ErrorNotice(error),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Flexible(
                              child: Text('Reading label on this device…'),
                            ),
                          ],
                        ),
                      ),
                    if (!opening && !busy && camera == null) ...[
                      OutlinedButton.icon(
                        onPressed: _retake,
                        icon: const MotionIcon(Icons.refresh_rounded),
                        label: const Text('Try camera again'),
                      ),
                      TextButton(
                        onPressed: () => const LocationCapture().openSettings(
                          deviceLocation: false,
                        ),
                        child: const Text('Open app settings'),
                      ),
                    ],
                    if (camera != null)
                      Row(
                        children: [
                          IconButton(
                            tooltip: torch ? 'Turn light off' : 'Turn light on',
                            onPressed: busy
                                ? null
                                : () async {
                                    try {
                                      await camera!.setFlashMode(
                                        torch ? FlashMode.off : FlashMode.torch,
                                      );
                                      if (mounted) {
                                        setState(() => torch = !torch);
                                      }
                                    } catch (_) {
                                      if (mounted) {
                                        setState(
                                          () => error =
                                              'Light is unavailable on this camera.',
                                        );
                                      }
                                    }
                                  },
                            icon: MotionIcon(
                              torch
                                  ? Icons.flash_on_rounded
                                  : Icons.flash_off_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy ? null : _capture,
                              icon: const MotionIcon(Icons.camera_alt_rounded),
                              label: const Text('Take photo & read label'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'On-device OCR · No photo upload\nReview before saving. Temporary photos are removed when you leave.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.7,
                        color: context.colors.muted,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class CableLabelReview extends StatefulWidget {
  const CableLabelReview({
    super.key,
    required this.form,
    required this.existing,
    required this.readout,
    required this.onApply,
    required this.onRetake,
    this.photo,
  });
  final FormDefinition form;
  final Answers existing;
  final CableLabelReadout readout;
  final File? photo;
  final ValueChanged<Answers> onApply;
  final VoidCallback onRetake;
  @override
  State<CableLabelReview> createState() => _CableLabelReviewState();
}

class _CableLabelReviewState extends State<CableLabelReview> {
  late final fields = scannableFields(widget.form, widget.existing);
  final controllers = <String, TextEditingController>{};
  final selected = <String>{};
  String error = '';
  @override
  void initState() {
    super.initState();
    final suggestions = validLabelSuggestions(
      widget.form,
      widget.existing,
      widget.readout,
    );
    for (final f in fields) {
      final value = suggestions[f.id];
      final raw = widget.readout.values[f.scanTarget] ?? '';
      controllers[f.id] = TextEditingController(
        text: value == null
            ? raw
            : f.kind == FieldKind.quantity
            ? f.display(value)
            : value.toJson().toString(),
      );
      if (value != null && missing(widget.existing[f.id])) selected.add(f.id);
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void apply() {
    final patch = <String, Answer?>{};
    for (final f in fields.where((f) => selected.contains(f.id))) {
      final answer = decodeLabelEntry(f, controllers[f.id]!.text);
      if (answer == null) {
        setState(
          () => error =
              'Check ${f.label}. Use a clear value, an explicit m/km unit for length, or YYYY-MM-DD for a date.',
        );
        return;
      }
      patch[f.id] = answer;
    }
    if (patch.isEmpty) {
      setState(
        () =>
            error = 'Select at least one field to apply, or retake the photo.',
      );
      return;
    }
    final check = validate(widget.form, {
      ...widget.existing,
      ...patch,
    }, requireComplete: false);
    final issue = check.issues
        .where((i) => patch.containsKey(i.fieldId))
        .firstOrNull;
    if (issue != null) {
      setState(
        () => error =
            '${fields.firstWhere((f) => f.id == issue.fieldId).label}: ${issue.message}',
      );
      return;
    }
    widget.onApply(patch);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(23),
          children: [
            Text(
              'Check the label. Keep control.',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w600,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'OCR can confuse letters and numbers. Edit the suggestions and select which fields to save. Existing values are not selected for replacement.',
              style: TextStyle(height: 1.7, color: context.colors.muted),
            ),
            if (widget.photo != null)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    widget.photo!,
                    height: 140,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            if (widget.readout.values.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 15),
                child: ErrorNotice(
                  'No clear label values were found. Retake a sharper photo or enter details below.',
                  isInfo: true,
                ),
              ),
            const SizedBox(height: 20),
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected.contains(f.id),
                      onChanged: (v) => setState(() {
                        v == true ? selected.add(f.id) : selected.remove(f.id);
                      }),
                      title: Text(f.label),
                      subtitle: !missing(widget.existing[f.id])
                          ? Text(
                              'Current: ${f.display(widget.existing[f.id])} · select to replace',
                            )
                          : null,
                    ),
                    if (widget.readout.ambiguous.contains(f.scanTarget))
                      const Text(
                        'Conflicting printed values found. Enter the correct one.',
                      ),
                    TextField(
                      controller: controllers[f.id],
                      decoration: InputDecoration(
                        labelText: f.label,
                        hintText: f.kind == FieldKind.quantity
                            ? 'e.g. 1000 m'
                            : f.kind == FieldKind.date
                            ? 'YYYY-MM-DD'
                            : 'Not clearly read — enter manually',
                      ),
                      onChanged: (_) {
                        if (missing(widget.existing[f.id])) {
                          setState(() => selected.add(f.id));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Text read from the photo'),
              children: [
                SelectableText(
                  widget.readout.rawText.isEmpty
                      ? 'No text detected.'
                      : widget.readout.rawText,
                ),
              ],
            ),
            ErrorNotice(error),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(23, 12, 23, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.onRetake,
                child: const Text('Retake'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: apply,
                icon: const MotionIcon(Icons.check_rounded),
                label: const Text('Apply to report'),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
