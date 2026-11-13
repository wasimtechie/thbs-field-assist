import 'dart:async';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/app_controller.dart';
import '../closure/question_voice.dart';
import '../voice/voice_audio.dart';

class VoicePicker extends ConsumerStatefulWidget {
  const VoicePicker({super.key, this.bundle});
  final AssetBundle? bundle;
  @override
  ConsumerState<VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends ConsumerState<VoicePicker> {
  VoiceAudio? audio;
  String? playing;
  String error = '';
  int generation = 0;

  Future<void> stop() async {
    generation++;
    await audio?.stopPlayback();
    if (mounted) setState(() => playing = null);
  }

  Future<void> preview(OfflineSpeechVoice profile) async {
    if (playing == profile.id) {
      await stop();
      return;
    }
    await stop();
    final app = ref.read(appProvider.notifier);
    final owner = ref.read(appProvider).user?.id;
    final turn = ++generation;
    bool current() =>
        mounted &&
        generation == turn &&
        ref.read(appProvider).user?.id == owner;
    setState(() {
      playing = profile.id;
      error = '';
    });
    try {
      await app.assertAccess();
      if (!current()) return;
      if (!ref.read(appProvider).voiceReady) {
        throw StateError('Voice not ready');
      }
      audio ??= ref.read(voiceAudioFactoryProvider)();
      await audio!.configure(() => unawaited(stop()));
      if (!current()) return;
      final speech = QuestionVoice(
        VoiceAudition(app.voice, profile.id),
        bundle: widget.bundle,
        voiceId: profile.id,
        rate: ref.read(appProvider).speechRate,
      );
      final clip = await speech.synthesize(speechVoicePreview);
      if (!current()) return;
      await app.assertAccess();
      if (!current()) return;
      await audio!.play(clip, (_) {});
    } catch (_) {
      if (current()) {
        setState(
          () => error =
              'Voice preview is unavailable. Check Offline readiness and try again.',
        );
      }
    } finally {
      if (current()) setState(() => playing = null);
    }
  }

  Future<void> select(OfflineSpeechVoice profile) async {
    await stop();
    if (!mounted) return;
    try {
      await ref.read(appProvider.notifier).settings(voiceId: profile.id);
      if (mounted) setState(() => error = '');
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'Could not save your voice preference. Please try again.',
        );
      }
    }
  }

  @override
  void dispose() {
    generation++;
    unawaited(audio?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected =
        offlineSpeechVoice(ref.watch(appProvider).speechVoiceId) ??
        offlineSpeechVoices.first;
    return ExpansionTile(
      leading: const Icon(Icons.record_voice_over_outlined),
      title: const Text('AI voice'),
      subtitle: Text('${selected.name} · ${selected.description}'),
      shape: const Border(),
      collapsedShape: const Border(),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            'Listen to a sample, then choose your voice. All voices work offline.',
          ),
        ),
        for (final profile in offlineSpeechVoices)
          ListTile(
            key: ValueKey('select-voice-${profile.id}'),
            leading: Icon(
              profile.id == selected.id
                  ? Icons.check_circle
                  : Icons.circle_outlined,
            ),
            title: Text(profile.name),
            subtitle: Text(profile.description),
            selected: profile.id == selected.id,
            onTap: () => select(profile),
            trailing: IconButton(
              tooltip: playing == profile.id
                  ? 'Stop preview'
                  : 'Preview ${profile.name}',
              onPressed: () => preview(profile),
              icon: Icon(
                playing == profile.id
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outline,
              ),
            ),
          ),
        if (error.isNotEmpty)
          Padding(padding: const EdgeInsets.all(16), child: Text(error)),
      ],
    );
  }
}
