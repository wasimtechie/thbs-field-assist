import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/contracts.dart';
import '../../core/design_system/theme.dart';
import '../../core/design_system/workspace.dart';
import 'conversation.dart';
import 'voice_coordinator.dart';

class VoiceSessionScreen extends StatefulWidget {
  const VoiceSessionScreen({
    super.key,
    required this.coordinator,
    required this.schema,
  });
  final VoiceCoordinator coordinator;
  final FormDefinition schema;
  @override
  State<VoiceSessionScreen> createState() => _VoiceSessionScreenState();
}

class _VoiceSessionScreenState extends State<VoiceSessionScreen> {
  bool _allowPop = false, _ending = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.coordinator.begin());
    });
  }

  Future<void> end({bool review = false}) async {
    if (_ending) return;
    setState(() => _ending = true);
    try {
      final voice = widget.coordinator;
      await voice.finishAndPause();
      if (!mounted) return;
      if (voice.hasUnsavedAnswer) {
        final leave = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('This answer has not been saved'),
            content: const Text(
              'Stay to retry saving this answer. Previously saved answers are safe.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Leave without this answer'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Stay and retry'),
              ),
            ],
          ),
        );
        if (leave != true) return;
      }
      await voice.pause();
      if (mounted) {
        setState(() => _allowPop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, review);
      }
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final voice = widget.coordinator;
    final readableTeal = Theme.of(context).brightness == Brightness.light
        ? Color.lerp(context.colors.teal, context.colors.ink, .45)!
        : context.colors.teal;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.coordinator.state != VoiceState.saving) {
          unawaited(end());
        }
      },
      child: ListenableBuilder(
        listenable: voice,
        builder: (context, _) => Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.colors.raised,
                          shape: BoxShape.circle,
                        ),
                        child: MotionIcon(
                          Icons.graphic_eq_rounded,
                          size: 21,
                          color: context.colors.indigo,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Field Assist Voice',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close voice conversation',
                        onPressed: _ending || voice.state == VoiceState.saving
                            ? null
                            : () => end(),
                        icon: const MotionIcon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(26, 12, 26, 12),
                    children: [
                      Center(
                        child: StatusPill(
                          voice.label,
                          icon: voice.state == VoiceState.listening
                              ? Icons.mic_none_rounded
                              : voice.state == VoiceState.speaking
                              ? Icons.volume_up_outlined
                              : Icons.sensors_rounded,
                          color: voice.state == VoiceState.listening
                              ? context.colors.teal
                              : context.colors.indigo,
                          foregroundColor: voice.state == VoiceState.listening
                              ? readableTeal
                              : context.colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${voice.activeField?.label ?? 'Report'} · ${voice.answeredCount}/${voice.voiceFields.length} saved',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: AssistantOrb(
                          size: 96,
                          active:
                              voice.state == VoiceState.listening ||
                              voice.state == VoiceState.speaking,
                          level: voice.level,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          voice.question.isEmpty
                              ? 'Let’s get your report ready.'
                              : voice.question,
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.headlineMedium?.copyWith(height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (voice.numericSuggestion != null) ...[
                        Text(
                          'Waiting for confirmation · Not saved yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.muted),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: !_ending && voice.canChoose
                                  ? voice.confirmNumericSuggestion
                                  : null,
                              child: Text('Use ${voice.suggestedValue}'),
                            ),
                            OutlinedButton(
                              onPressed: !_ending && voice.canChoose
                                  ? voice.rejectNumericSuggestion
                                  : null,
                              child: const Text('Answer again'),
                            ),
                          ],
                        ),
                      ],
                      if (voice.activeField case final field?) ...[
                        if (!field.required)
                          TextButton(
                            onPressed: !_ending && voice.canChoose
                                ? voice.skipOptional
                                : null,
                            child: const Text('Skip optional question'),
                          ),
                      ],
                      if (voice.activeField case final field?
                          when field.kind == FieldKind.singleSelect)
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 9,
                          children: [
                            for (final choice in field.options)
                              OutlinedButton(
                                onPressed: !_ending && voice.canChoose
                                    ? () => voice.choose(choice)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: context.colors.panel,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 15,
                                  ),
                                ),
                                child: Text(
                                  voiceChoiceLabel(field, choice),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      if (voice.transcript.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: context.colors.panel,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.colors.edge),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Eyebrow(
                                voice.savedMessage.isEmpty
                                    ? 'Your answer'
                                    : '${voice.savedFieldLabel} saved',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '“${voice.transcript}”',
                                style: const TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (voice.savedMessage.isNotEmpty) ...[
                        for (final saved in voice.savedValues.entries)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              '${saved.key}: ${saved.value}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              MotionIcon(
                                Icons.check_circle_outline_rounded,
                                color: readableTeal,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  voice.savedMessage,
                                  style: TextStyle(
                                    color: readableTeal,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (voice.processing) ...[
                        const SizedBox(height: 20),
                        const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                      if (_ending) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Finishing your answer before returning to the form…',
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (voice.activeField == null &&
                          voice.touchFields.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Complete in the form: ${voice.touchFields.map((f) => f.label).join(', ')}.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ],
                      if (voice.error.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        ErrorNotice(voice.error),
                      ],
                      if (voice.hasUnsavedAnswer &&
                          voice.state != VoiceState.saving)
                        FilledButton.icon(
                          onPressed: voice.retrySave,
                          icon: const MotionIcon(Icons.refresh_rounded),
                          label: const Text('Retry saving this answer'),
                        ),
                      if (voice.state == VoiceState.readyToReview) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => end(review: true),
                          icon: const MotionIcon(Icons.fact_check_outlined),
                          label: const Text('Review saved report'),
                        ),
                      ] else if ([
                            VoiceState.paused,
                            VoiceState.error,
                            VoiceState.needsClarification,
                          ].contains(voice.state) &&
                          !voice.hasUnsavedAnswer)
                        Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: OutlinedButton.icon(
                            onPressed: _ending
                                ? null
                                : voice.activeField == null
                                ? () => end()
                                : voice.start,
                            icon: MotionIcon(
                              voice.activeField == null
                                  ? Icons.edit_outlined
                                  : Icons.mic_none_rounded,
                            ),
                            label: Text(
                              voice.activeField == null
                                  ? 'Continue by touch'
                                  : 'Answer by voice',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 190),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: VoiceGlow(
                            state: voice.state,
                            level: voice.level,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(25, 30, 25, 18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (voice.state == VoiceState.listening)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Finish naturally. Your answer saves automatically.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            if (voice.state == VoiceState.listening)
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: context.colors.panel,
                                ),
                                onPressed: _ending ? null : voice.finish,
                                icon: const MotionIcon(
                                  Icons.stop_rounded,
                                  size: 18,
                                ),
                                label: const Text('Done speaking'),
                              ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _VoiceControl(
                                  label: voice.state == VoiceState.paused
                                      ? 'Resume'
                                      : 'Pause',
                                  icon: voice.state == VoiceState.paused
                                      ? Icons.play_arrow_rounded
                                      : Icons.pause_rounded,
                                  onPressed:
                                      _ending ||
                                          voice.state == VoiceState.saving ||
                                          voice.hasUnsavedAnswer
                                      ? null
                                      : voice.state == VoiceState.paused
                                      ? voice.begin
                                      : voice.pause,
                                ),
                                const SizedBox(width: 34),
                                _VoiceControl(
                                  label: _ending ? 'Finishing…' : 'End',
                                  icon: Icons.close_rounded,
                                  color: context.colors.danger,
                                  onPressed:
                                      _ending ||
                                          voice.state == VoiceState.saving
                                      ? null
                                      : () => end(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.canvas,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Text(
                                'Answers save locally · Review before sending',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.colors.muted,
                                ),
                              ),
                            ),
                          ],
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

class _VoiceControl extends StatelessWidget {
  const _VoiceControl({
    required this.label,
    required this.icon,
    this.color,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      minimumSize: const Size(76, 92),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 58,
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color == null
                ? context.colors.panel
                : Color.alphaBlend(
                    color!.withValues(alpha: .08),
                    context.colors.panel,
                  ),
            border: Border.all(
              color: color?.withValues(alpha: .4) ?? context.colors.edge,
            ),
          ),
          child: MotionIcon(
            icon,
            size: 26,
            color: onPressed == null
                ? context.colors.muted
                : color == null
                ? context.colors.ink
                : Theme.of(context).brightness == Brightness.light
                ? Color.lerp(color, context.colors.ink, .25)
                : color,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: context.colors.canvas,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: onPressed == null
                  ? context.colors.muted
                  : context.colors.ink,
            ),
          ),
        ),
      ],
    ),
  );
}

/// The light moves with actual recording/playback levels. Processing and paused
/// states retain a static glow; they never masquerade as a live microphone.
class VoiceGlow extends StatefulWidget {
  const VoiceGlow({super.key, required this.state, required this.level});
  final VoiceState state;
  final double level;
  @override
  State<VoiceGlow> createState() => _VoiceGlowState();
}

class _VoiceGlowState extends State<VoiceGlow>
    with SingleTickerProviderStateMixin {
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  bool constrained = true;
  @override
  void initState() {
    super.initState();
    checkPower();
  }

  void checkPower() {
    const MethodChannel('field_assist/security')
        .invokeMethod<bool>('powerConstrained')
        .then((value) {
          if (mounted) setState(() => constrained = value ?? true);
        })
        .catchError((Object _) {});
  }

  @override
  void didUpdateWidget(VoiceGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) checkPower();
  }

  @override
  Widget build(BuildContext context) {
    final live = [
      VoiceState.listening,
      VoiceState.speaking,
    ].contains(widget.state);
    final animated =
        live &&
        !constrained &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animated && !animation.isAnimating) animation.repeat();
    if (!animated && animation.isAnimating) animation.stop();
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) => CustomPaint(
            painter: _GlowPainter(
              phase: animated ? animation.value * math.pi * 2 : 0,
              energy: animated ? math.sqrt(widget.level.clamp(0, 1)) : 0,
              live: live,
              primary: indigo,
              accent: teal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter({
    required this.phase,
    required this.energy,
    required this.live,
    required this.primary,
    required this.accent,
  });
  final double phase, energy;
  final bool live;
  final Color primary, accent;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    for (var layer = 0; layer < 3; layer++) {
      final color = layer == 1 ? accent : primary;
      final path = Path()..moveTo(0, size.height);
      final ridge = Path();
      for (var i = 0; i <= 60; i++) {
        final x = i / 60 * size.width;
        final wave = math.sin(i / 60 * math.pi * 2 + phase + layer * 1.7);
        final y = size.height * (.48 + layer * .05) + wave * (5 + energy * 29);
        path.lineTo(x, y);
        if (i == 0) {
          ridge.moveTo(x, y);
        } else {
          ridge.lineTo(x, y);
        }
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: .0),
              color.withValues(alpha: (live ? .48 : .18) + energy * .25),
              color.withValues(alpha: .015),
            ],
          ).createShader(bounds)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 17 + energy * 5),
      );
      canvas.drawPath(
        ridge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5 + energy * 5
          ..color = color.withValues(alpha: (live ? .55 : .18) + energy * .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      phase != old.phase ||
      energy != old.energy ||
      live != old.live ||
      primary != old.primary ||
      accent != old.accent;
}
