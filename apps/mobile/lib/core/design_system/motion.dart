import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// A single feedback layer for every Material button, including keyboard presses.
/// Material continues to own activation, focus, disabled state and semantics.
Widget tactileButton(
  BuildContext context,
  Set<WidgetState> states,
  Widget? child,
) => TactileFeedback(
  pressed: states.contains(WidgetState.pressed),
  child: child!,
);

class TactileFeedback extends StatefulWidget {
  const TactileFeedback({
    super.key,
    required this.pressed,
    required this.child,
  });
  final bool pressed;
  final Widget child;
  @override
  State<TactileFeedback> createState() => _TactileFeedbackState();
}

class _TactileFeedbackState extends State<TactileFeedback>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController.unbounded(vsync: this, value: 0);
  bool reduced = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced) {
      motion.stop();
      motion.value = 0;
    }
  }

  @override
  void didUpdateWidget(TactileFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pressed == widget.pressed) return;
    if (widget.pressed) HapticFeedback.selectionClick();
    if (reduced) {
      motion.value = 0;
      return;
    }
    motion.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 620, damping: 32),
        motion.value,
        widget.pressed ? 1 : 0,
        motion.velocity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: motion,
    builder: (context, child) => _PressScope(
      amount: motion.value,
      child: Transform.translate(
        offset: Offset(0, motion.value * 1.2),
        child: Transform.scale(scale: 1 - motion.value * .035, child: child),
      ),
    ),
    child: widget.child,
  );
  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }
}

class _PressScope extends InheritedWidget {
  const _PressScope({required this.amount, required super.child});
  final double amount;
  @override
  bool updateShouldNotify(_PressScope oldWidget) => amount != oldWidget.amount;
}

/// Vector icons respond to their button's pressure and morph on real state changes.
/// No loops, downloaded animations or invented activity indicators.
class MotionIcon extends StatelessWidget {
  const MotionIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });
  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final amount = reduced
        ? 0.0
        : context.dependOnInheritedWidgetOfExactType<_PressScope>()?.amount ??
              0;
    final turn =
        icon == Icons.settings_outlined ||
        icon == Icons.sync_rounded ||
        icon == Icons.refresh_rounded;
    final arrow =
        icon == Icons.arrow_forward_rounded ||
        icon == Icons.chevron_right_rounded;
    return Transform.translate(
      offset: Offset(arrow ? amount * 4 : 0, 0),
      child: Transform.rotate(
        angle: turn ? amount * math.pi / 5 : 0,
        child: AnimatedSwitcher(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: .8, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: Icon(
            icon,
            key: ValueKey(icon),
            size: size,
            color: color,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
    );
  }
}

class FieldEntrance extends StatelessWidget {
  const FieldEntrance({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delay),
      curve: Interval(delay / (420 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class SuccessMark extends StatelessWidget {
  const SuccessMark({super.key, this.color = const Color(0xff91e5c7)});
  final Color color;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(
      begin: MediaQuery.disableAnimationsOf(context) ? 1 : 0,
      end: 1,
    ),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 500),
    curve: Curves.easeOutCubic,
    builder: (context, value, _) => CustomPaint(
      size: const Size.square(62),
      painter: _CheckPainter(value, color),
    ),
  );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.progress, this.color);
  final double progress;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .2, size.height * .51)
      ..lineTo(size.width * .42, size.height * .72)
      ..lineTo(size.width * .82, size.height * .28);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      progress != oldDelegate.progress || color != oldDelegate.color;
}
