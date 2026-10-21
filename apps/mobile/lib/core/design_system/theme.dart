import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'motion.dart';
export 'motion.dart';

// Original Field Assist brand colors are retained in light mode.
const ink = Color(0xff252a3b),
    indigo = Color(0xff6554c8),
    teal = Color(0xff1c9a89),
    muted = Color(0xff818999),
    canvas = Color(0xfff6f7fb);

@immutable
class FieldColors extends ThemeExtension<FieldColors> {
  const FieldColors({
    required this.ink,
    required this.indigo,
    required this.teal,
    required this.muted,
    required this.canvas,
    required this.panel,
    required this.raised,
    required this.edge,
    required this.danger,
  });
  final Color ink, indigo, teal, muted, canvas, panel, raised, edge, danger;
  static const light = FieldColors(
    ink: Color(0xff252a3b),
    indigo: Color(0xff6554c8),
    teal: Color(0xff1c9a89),
    muted: Color(0xff697386),
    canvas: Color(0xfff6f7fb),
    panel: Colors.white,
    raised: Color(0xffefebfc),
    edge: Color(0xffe2e5ef),
    danger: Color(0xffad5964),
  );
  static const dark = FieldColors(
    ink: Color(0xfff4f2fa),
    indigo: Color(0xffb5a3ff),
    teal: Color(0xff72d8c4),
    muted: Color(0xffa5adba),
    canvas: Color(0xff10121a),
    panel: Color(0xff1a1e2a),
    raised: Color(0xff292a40),
    edge: Color(0xff393e50),
    danger: Color(0xffffa6ae),
  );
  @override
  FieldColors copyWith() => this;
  @override
  FieldColors lerp(covariant FieldColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return FieldColors(
      ink: mix(ink, other.ink),
      indigo: mix(indigo, other.indigo),
      teal: mix(teal, other.teal),
      muted: mix(muted, other.muted),
      canvas: mix(canvas, other.canvas),
      panel: mix(panel, other.panel),
      raised: mix(raised, other.raised),
      edge: mix(edge, other.edge),
      danger: mix(danger, other.danger),
    );
  }
}

extension FieldColorContext on BuildContext {
  FieldColors get colors => Theme.of(this).extension<FieldColors>()!;
}

ThemeData fieldTheme({Brightness brightness = Brightness.light}) {
  final fontFamily = defaultTargetPlatform == TargetPlatform.iOS
      ? '.SF Pro Text'
      : 'Roboto';
  final colors = brightness == Brightness.dark
      ? FieldColors.dark
      : FieldColors.light;
  final ink = colors.ink,
      indigo = colors.indigo,
      teal = colors.teal,
      muted = colors.muted,
      canvas = colors.canvas,
      panel = colors.panel,
      raised = colors.raised,
      edge = colors.edge,
      danger = colors.danger;

  final scheme = ColorScheme.fromSeed(seedColor: indigo, brightness: brightness)
      .copyWith(
        primary: const Color(0xff6554c8),
        onPrimary: Colors.white,
        secondary: teal,
        onSecondary: canvas,
        surface: panel,
        onSurface: ink,
        onSurfaceVariant: muted,
        outline: edge,
        error: danger,
        onError: canvas,
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  final interaction = ButtonStyle(
    foregroundBuilder: tactileButton,
    animationDuration: const Duration(milliseconds: 160),
  );
  return ThemeData(
    extensions: [colors],
    fontFamily: fontFamily,
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    splashFactory: InkSparkle.splashFactory,
    dividerColor: edge,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.white : muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xff6554c8)
            : edge,
      ),
      trackOutlineColor: WidgetStatePropertyAll(muted.withValues(alpha: .45)),
    ),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 38,
        height: 1.12,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.6,
        color: ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 29,
        height: 1.16,
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 23,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: -.6,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 17,
        height: 1.5,
        color: ink,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        height: 1.5,
        color: ink,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        height: 1.5,
        color: muted,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -.4,
        color: ink,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: edge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: edge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: indigo, width: 1.5),
      ),
      labelStyle: TextStyle(fontFamily: fontFamily, color: muted, fontSize: 16),
      hintStyle: TextStyle(fontFamily: fontFamily, color: muted, fontSize: 16),
      prefixIconColor: muted,
      suffixIconColor: muted,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xff6554c8),
        disabledBackgroundColor: raised,
        disabledForegroundColor: muted,
        minimumSize: const Size(48, 56),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        shape: shape,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ).merge(interaction),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: shape,
        side: BorderSide(color: edge),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ).merge(interaction),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: indigo,
        minimumSize: const Size(48, 48),
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w600,
        ),
      ).merge(interaction),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: ink,
        minimumSize: const Size.square(48),
      ).merge(interaction),
    ),
    cardTheme: CardThemeData(
      color: panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: edge),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(backgroundColor: panel, shape: shape),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: raised,
      contentTextStyle: TextStyle(fontFamily: fontFamily, color: ink),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: teal,
      linearTrackColor: raised,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      textColor: ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key, this.small = false});
  final bool small;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: small ? 30 : 38,
        height: small ? 30 : 38,
        decoration: BoxDecoration(
          color: context.colors.indigo,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: context.colors.indigo.withValues(alpha: .4),
          ),
        ),
        child: Icon(
          Icons.sensors_rounded,
          color: Colors.white,
          size: small ? 21 : 27,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              text: 'field',
              style: TextStyle(
                fontSize: small ? 23 : 28,
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
                letterSpacing: -1.1,
              ),
              children: [
                TextSpan(
                  text: 'assist',
                  style: TextStyle(fontWeight: FontWeight.w400),
                ),
                TextSpan(
                  text: '.',
                  style: TextStyle(color: context.colors.indigo),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, {super.key, this.isInfo = false});
  final String message;
  final bool isInfo;
  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox.shrink();
    final color = isInfo ? context.colors.indigo : context.colors.danger;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 17),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MotionIcon(
              isInfo ? Icons.info_outline : Icons.error_outline,
              size: 20,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13, height: 1.6, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w700,
      color: context.colors.muted,
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.icon = Icons.circle,
    this.color,
    this.foregroundColor,
  });
  final String label;
  final IconData icon;
  final Color? color;
  final Color? foregroundColor;
  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MotionIcon(icon, size: 13, color: foregroundColor ?? color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: foregroundColor ?? color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FibreObject extends StatefulWidget {
  const FibreObject({super.key, this.size = 180, this.active = true});
  final double size;
  final bool active;
  @override
  State<FibreObject> createState() => _FibreObjectState();
}

class _FibreObjectState extends State<FibreObject>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  bool constrained = true, foreground = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkPower();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() => foreground = state == AppLifecycleState.resumed);
    if (foreground) checkPower();
  }

  void checkPower() {
    const MethodChannel('field_assist/security')
        .invokeMethod<bool>('powerConstrained')
        .then((v) {
          if (mounted) setState(() => constrained = v ?? true);
        })
        .catchError((_) {
          return null;
        });
  }

  @override
  Widget build(BuildContext context) {
    final animate =
        foreground &&
        widget.active &&
        !MediaQuery.disableAnimationsOf(context) &&
        !constrained &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !rotation.isAnimating) rotation.repeat();
    if (!animate && rotation.isAnimating) rotation.stop();
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: rotation,
          builder: (context, _) => CustomPaint(
            size: Size.square(widget.size),
            painter: _FibrePainter(
              animate
                  ? (rotation.value * 540).floor() / 540 * math.pi * 2
                  : .65,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rotation.dispose();
    super.dispose();
  }
}

class _FibrePainter extends CustomPainter {
  _FibrePainter(this.angle);
  final double angle;
  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [indigo.withValues(alpha: .16), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * .55),
        width: size.width,
        height: size.height * .8,
      ),
      glow,
    );
    final faces = <({Path path, double depth, double light})>[];
    Offset project(double x, double y, double z) {
      final a = angle + .5;
      final rx = x * math.cos(a) + z * math.sin(a),
          rz = -x * math.sin(a) + z * math.cos(a);
      final ry = y * math.cos(.8) - rz * math.sin(.8),
          depth = y * math.sin(.8) + rz * math.cos(.8);
      final perspective = 3 / (3 + depth);
      return Offset(
        size.width / 2 + rx * size.width * .32 * perspective,
        size.height / 2 + ry * size.height * .32 * perspective,
      );
    }

    for (var i = 0; i < 72; i++) {
      for (var j = 0; j < 16; j++) {
        final points = <Offset>[];
        var depth = 0.0;
        for (final corner in [
          [i, j],
          [i + 1, j],
          [i + 1, j + 1],
          [i, j + 1],
        ]) {
          final u = corner[0] / 72 * 2 * math.pi,
              v = corner[1] / 16 * 2 * math.pi;
          final radius = .95 + .24 * math.cos(v + u * 3);
          final x = radius * math.cos(u),
              y = radius * math.sin(u),
              z = .24 * math.sin(v + u * 3);
          points.add(project(x, y, z));
          depth += z * math.cos(.8) + y * math.sin(.8);
        }
        final path = Path()..moveTo(points[0].dx, points[0].dy);
        for (final p in points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        path.close();
        faces.add((
          path: path,
          depth: depth / 4,
          light: (math.cos(j / 16 * 2 * math.pi - .8) + 1) / 2,
        ));
      }
    }
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final f in faces) {
      canvas.drawPath(
        f.path,
        Paint()
          ..color = Color.lerp(
            const Color(0xff352c60),
            const Color(0xffe1dcfa),
            math.pow(f.light, 2).toDouble(),
          )!,
      );
    }
  }

  @override
  bool shouldRepaint(_FibrePainter old) => old.angle != angle;
}
