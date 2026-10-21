import 'package:flutter/material.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/appearance.dart';
import 'auth_video_background.dart';

/// Shared video-led frame for the public account entry screens.
/// The document scrolls as one surface when the keyboard or large text needs room.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.paused = false,
    this.onBack,
    this.scrollController,
  });
  final String title, subtitle;
  final Widget child;
  final bool paused;
  final VoidCallback? onBack;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: AuthVideoBackground(
        paused: paused,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: CustomScrollView(
              controller: scrollController,
              key: const PageStorageKey('account-entry-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colors.canvas.withValues(alpha: .54),
                          colors.canvas.withValues(alpha: .08),
                        ],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(26, 14, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (onBack != null) ...[
                                  IconButton.filledTonal(
                                    tooltip: 'Back to sign in',
                                    onPressed: onBack,
                                    style: IconButton.styleFrom(
                                      backgroundColor: colors.panel.withValues(
                                        alpha: .8,
                                      ),
                                    ),
                                    icon: const MotionIcon(
                                      Icons.arrow_back_rounded,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                const Expanded(child: _AuthBrand()),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.panel.withValues(alpha: .72),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: colors.edge.withValues(alpha: .7),
                                    ),
                                  ),
                                  child: const AppearanceButton(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 29),
                            FieldEntrance(
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 43,
                                  height: 1.03,
                                  letterSpacing: -1.7,
                                  fontWeight: FontWeight.w700,
                                  color: colors.ink,
                                ),
                              ),
                            ),
                            const SizedBox(height: 13),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: colors.ink.withValues(alpha: .75),
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Container(
                    key: const ValueKey('auth-form-panel'),
                    decoration: BoxDecoration(
                      color: colors.panel,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(36),
                      ),
                      border: Border.all(
                        color: colors.edge.withValues(alpha: .8),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.canvas.withValues(alpha: .25),
                          blurRadius: 24,
                          offset: const Offset(0, -8),
                        ),
                      ],
                    ),
                    padding: EdgeInsets.fromLTRB(
                      26,
                      28,
                      26,
                      22 + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: child,
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

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'THBS Field Assist',
    child: ExcludeSemantics(
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: const Color(0xff6554c8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.sensors_rounded,
              size: 25,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'T H B S',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: context.colors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Field Assist.',
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.7,
                    color: context.colors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class AuthPanelHeading extends StatelessWidget {
  const AuthPanelHeading({
    super.key,
    required this.title,
    required this.subtitle,
  });
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 27,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -.9,
                color: context.colors.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: context.colors.raised,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.waving_hand_outlined,
                color: context.colors.indigo,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Text(
        subtitle,
        style: TextStyle(
          fontSize: 13,
          height: 1.6,
          color: context.colors.muted,
        ),
      ),
    ],
  );
}

InputDecoration authInputDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  Widget? suffix,
}) => InputDecoration(
  labelText: label,
  prefixIcon: MotionIcon(icon, size: 20),
  suffixIcon: suffix,
  fillColor: context.colors.canvas,
  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: context.colors.edge.withValues(alpha: .65)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: context.colors.indigo, width: 1.5),
  ),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
);

ButtonStyle authPrimaryStyle() => FilledButton.styleFrom(
  minimumSize: const Size(double.infinity, 57),
  shape: const StadiumBorder(),
  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 17),
);

class AuthFootnote extends StatelessWidget {
  const AuthFootnote({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 14,
          color: context.colors.teal,
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            'Secure access. Your workspace, wherever work takes you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.6,
              color: context.colors.muted,
            ),
          ),
        ),
      ],
    ),
  );
}
