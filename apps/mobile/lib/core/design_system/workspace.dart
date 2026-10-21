import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme.dart';

/// Applied only to the signed-in workspace. Account-entry visuals stay separate.
ThemeData workspaceTheme(ThemeData base) {
  final c = base.extension<FieldColors>()!;
  final round = RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 30,
        height: 1.16,
        letterSpacing: -1,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 25,
        height: 1.2,
        letterSpacing: -.7,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 21),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 15),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      centerTitle: true,
      toolbarHeight: 68,
      actionsPadding: const EdgeInsets.only(right: 10),
      titleSpacing: 12,
      titleTextStyle: TextStyle(
        fontFamily: base.textTheme.bodyMedium?.fontFamily,
        color: c.ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -.4,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      shape: round,
      elevation: 1,
      shadowColor: c.ink.withValues(alpha: .045),
      margin: const EdgeInsets.symmetric(vertical: 5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base.filledButtonTheme.style?.copyWith(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base.outlinedButtonTheme.style?.copyWith(
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        backgroundColor: WidgetStatePropertyAll(c.panel),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: base.iconButtonTheme.style?.copyWith(
        shape: const WidgetStatePropertyAll(CircleBorder()),
        backgroundColor: WidgetStatePropertyAll(c.panel),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: c.canvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c.edge.withValues(alpha: .55)),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c.indigo, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide(color: c.edge.withValues(alpha: .7)),
      backgroundColor: c.panel,
      selectedColor: c.raised,
      labelStyle: TextStyle(
        fontFamily: base.textTheme.bodyMedium?.fontFamily,
        color: c.ink,
        fontSize: 12,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.muted,
      shape: round,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
      minVerticalPadding: 13,
      titleTextStyle: TextStyle(
        fontFamily: base.textTheme.bodyMedium?.fontFamily,
        color: c.ink,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: base.textTheme.bodyMedium?.fontFamily,
        color: c.muted,
        fontSize: 12,
        height: 1.6,
      ),
    ),
  );
}

class WorkspaceShell extends StatelessWidget {
  const WorkspaceShell({
    super.key,
    required this.location,
    required this.child,
  });
  final String location;
  final Widget child;
  static const destinations = <(String, String, IconData)>[
    ('/home', 'Home', Icons.home_rounded),
    ('/jobs', 'Jobs', Icons.work_outline_rounded),
    ('/queue', 'Reports', Icons.description_outlined),
    ('/messages', 'Team', Icons.forum_outlined),
    ('/settings', 'Profile', Icons.person_outline_rounded),
  ];
  @override
  Widget build(BuildContext context) {
    final showNav =
        destinations.any((d) => d.$1 == location) &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
    return Theme(
      data: workspaceTheme(Theme.of(context)),
      child: Builder(
        builder: (context) => Scaffold(
          resizeToAvoidBottomInset: false,
          body: child,
          bottomNavigationBar: !showNav
              ? null
              : Container(
                  decoration: BoxDecoration(
                    color: context.colors.panel,
                    border: Border(
                      top: BorderSide(
                        color: context.colors.edge.withValues(alpha: .55),
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: context.colors.ink.withValues(alpha: .025),
                        blurRadius: 24,
                        offset: const Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(9, 9, 9, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (path, label, icon) in destinations)
                            Expanded(
                              child: Semantics(
                                selected: location == path,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 7,
                                      horizontal: 2,
                                    ),
                                    foregroundColor: location == path
                                        ? context.colors.indigo
                                        : context.colors.muted,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  onPressed: () {
                                    if (location != path) context.go(path);
                                  },
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedContainer(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 180),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: location == path
                                              ? context.colors.raised
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: MotionIcon(icon, size: 22),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        label,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class WorkspaceIntro extends StatelessWidget {
  const WorkspaceIntro({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });
  final String title, subtitle;
  final IconData icon;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkspaceIcon(icon, size: 46),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 7),
              Text(
                subtitle,
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 12,
                  height: 1.65,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

class WorkspaceIcon extends StatelessWidget {
  const WorkspaceIcon(this.icon, {super.key, this.size = 42, this.color});
  final IconData icon;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: (color ?? context.colors.indigo).withValues(alpha: .09),
      borderRadius: BorderRadius.circular(size * .34),
    ),
    child: MotionIcon(
      icon,
      size: size * .48,
      color: color ?? context.colors.indigo,
    ),
  );
}

class WorkspaceSection extends StatelessWidget {
  const WorkspaceSection(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: context.colors.ink,
              letterSpacing: -.4,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(action!, style: const TextStyle(fontSize: 11)),
          ),
      ],
    ),
  );
}

class WorkspaceTabs<T> extends StatelessWidget {
  const WorkspaceTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
  });
  final List<(T, String)> values;
  final T selected;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final (value, label) in values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              showCheckmark: false,
              selected: selected == value,
              onSelected: (_) => onSelected(value),
              label: Text(label),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
          ),
      ],
    ),
  );
}

/// A code-native brand companion: only existing purple, teal and panel colours.
/// It animates on state changes, so idle screens do not run a perpetual ticker.
class AssistantOrb extends StatelessWidget {
  const AssistantOrb({
    super.key,
    this.size = 112,
    this.active = false,
    this.level = 0,
  });
  final double size, level;
  final bool active;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: active ? 1 + level.clamp(0, 1) * .1 : .96),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Transform.scale(
        scale: value,
        child: CustomPaint(
          size: Size.square(size),
          painter: _OrbPainter(context.colors, value),
        ),
      ),
    ),
  );
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.colors, this.phase);
  final FieldColors colors;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, center = Offset(w / 2, w / 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w / 2, w * .91),
        width: w * .66,
        height: w * .1,
      ),
      Paint()
        ..color = colors.indigo.withValues(alpha: .13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    final rect = Rect.fromLTWH(w * .06, w * .02, w * .88, w * .88);
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.5, -.65),
          radius: 1.1,
          colors: [
            Color.lerp(colors.panel, colors.indigo, .3)!,
            colors.indigo,
            Color.lerp(colors.indigo, colors.teal, .7)!,
          ],
          stops: const [0, .5, 1],
        ).createShader(rect),
    );
    canvas.drawOval(
      rect.deflate(w * .009),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .012
        ..color = colors.panel.withValues(alpha: .65),
    );
    canvas.drawOval(
      Rect.fromLTWH(w * .21, w * .09, w * .33, w * .12),
      Paint()
        ..color = colors.panel.withValues(alpha: .24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final eye = Paint()
      ..color = Colors.white
      ..strokeWidth = w * .057
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final x in [.37, .63]) {
      final path = Path()
        ..moveTo(w * (x - .045), w * .47)
        ..quadraticBezierTo(w * x, w * .34, w * (x + .045), w * .47);
      canvas.drawPath(path, eye);
    }
    canvas.drawArc(
      Rect.fromCenter(
        center: center.translate(0, w * .02),
        width: w * .19,
        height: w * .16,
      ),
      .15 * math.pi,
      .7 * math.pi,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: .85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .025
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.colors != colors || old.phase != phase;
}
