import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class EvidenceCapture extends StatefulWidget {
  const EvidenceCapture({super.key});
  @override
  State<EvidenceCapture> createState() => _EvidenceCaptureState();
}

class _EvidenceCaptureState extends State<EvidenceCapture>
    with WidgetsBindingObserver {
  CameraController? camera;
  String error = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(open());
  }

  Future<void> open() async {
    CameraController? next;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera is available on this device.');
      }
      next = CameraController(
        cameras
                .where((c) => c.lensDirection == CameraLensDirection.back)
                .firstOrNull ??
            cameras.first,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() => camera = next);
    } catch (_) {
      await next?.dispose();
      if (mounted) {
        setState(
          () => error =
              'Camera unavailable. Allow camera access in device Settings, or return to your saved draft.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      final old = camera;
      camera = null;
      unawaited(old?.dispose());
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> capture() async {
    final controller = camera;
    if (controller == null || busy) return;
    setState(() => busy = true);
    File? file;
    try {
      file = File((await controller.takePicture()).path);
      final bytes = await file.readAsBytes();
      if (bytes.length > 120000) {
        throw StateError(
          'This photo is too large. Retake a closer, simpler view (maximum 120 KB for this demo).',
        );
      }
      if (mounted) Navigator.pop<Uint8List>(context, bytes);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (file != null && await file.exists()) await file.delete();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(camera?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Capture visit evidence')),
    body: Column(
      children: [
        if (error.isNotEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Text(error)),
        if (camera case final c? when c.value.isInitialized)
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: CameraPreview(c),
              ),
            ),
          )
        else
          const Expanded(
            child: Center(child: Icon(Icons.no_photography_outlined, size: 60)),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton.icon(
              onPressed: camera == null || busy ? null : capture,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(busy ? 'Saving…' : 'Use photo'),
            ),
          ),
        ),
      ],
    ),
  );
}
