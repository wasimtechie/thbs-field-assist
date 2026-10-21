import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// Local decorative media for authentication pages only. Posters also cover
/// startup, playback failures, reduced motion and constrained-power devices.
class AuthVideoBackground extends StatefulWidget {
  const AuthVideoBackground({
    super.key,
    required this.child,
    this.paused = false,
    this.controllerFactory,
  });
  final Widget child;
  final bool paused;
  final VideoPlayerController Function(String asset)? controllerFactory;

  @override
  State<AuthVideoBackground> createState() => _AuthVideoBackgroundState();
}

class _AuthVideoBackgroundState extends State<AuthVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  String? _asset;
  bool _ready = false, _failed = false, _constrained = true;
  bool _resumed = true, _reduced = true, _visible = true;
  int _generation = 0;

  bool get _shouldPlay =>
      _resumed && !_reduced && _visible && !_constrained && !widget.paused;

  @override
  void initState() {
    super.initState();
    _resumed =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkPower());
  }

  Future<void> _checkPower() async {
    bool constrained;
    try {
      constrained =
          await const MethodChannel(
            'field_assist/security',
          ).invokeMethod<bool>('powerConstrained') ??
          true;
    } catch (_) {
      constrained = true;
    }
    if (!mounted) return;
    setState(() => _constrained = constrained);
    _updatePlayback();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final asset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/auth/dark.mp4'
        : 'assets/auth/light.mp4';
    _reduced = MediaQuery.disableAnimationsOf(context);
    _visible = TickerMode.valuesOf(context).enabled;
    if (_asset != asset) {
      _release();
      _asset = asset;
      _failed = false;
    }
    _updatePlayback();
  }

  @override
  void didUpdateWidget(AuthVideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePlayback();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _updatePlayback();
    if (_resumed) unawaited(_checkPower());
  }

  void _updatePlayback() {
    final controller = _controller;
    if (controller == null) {
      if (!_shouldPlay || _failed || _asset == null) return;
      final next =
          widget.controllerFactory?.call(_asset!) ??
          VideoPlayerController.asset(
            _asset!,
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          );
      _controller = next;
      unawaited(_prepare(next, _generation));
    } else if (_ready) {
      unawaited(
        (_shouldPlay ? controller.play() : controller.pause()).catchError(
          (Object _) {},
        ),
      );
    }
  }

  bool _current(VideoPlayerController controller, int generation) =>
      mounted &&
      generation == _generation &&
      identical(controller, _controller);

  Future<void> _prepare(
    VideoPlayerController controller,
    int generation,
  ) async {
    try {
      await controller.initialize();
      if (!_current(controller, generation)) return;
      // The supplied light clip contains audio. Mute before any play request.
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.setPreventsDisplaySleepDuringVideoPlayback(false);
      if (!_current(controller, generation)) return;
      setState(() => _ready = true);
      _updatePlayback();
    } catch (_) {
      if (!_current(controller, generation)) return;
      setState(() {
        _failed = true;
        _release();
      });
    }
  }

  void _release() {
    _generation++;
    final previous = _controller;
    _controller = null;
    _ready = false;
    if (previous != null) {
      unawaited(previous.dispose().catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  _asset!.replaceAll('.mp4', '.jpg'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
                if (_ready && !_reduced && !_constrained)
                  ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox.fromSize(
                        size: _controller!.value.size,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      widget.child,
    ],
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    super.dispose();
  }
}
