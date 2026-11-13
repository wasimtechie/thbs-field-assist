import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:field_voice/field_voice.dart';
import '../../core/contracts.dart';
import '../voice/conversation.dart';
import '../voice/voice_audio.dart';
import 'closure_speech.dart';

class ClosureVoiceAnswer {
  const ClosureVoiceAnswer(
    this.transcript,
    this.answer,
    this.question, {
    this.sourceType = 'speech',
    this.inputMethod = 'speech',
    this.facts = const [],
  });
  final String transcript, question, sourceType, inputMethod;
  final Answer? answer;
  final List<Json> facts;
}

/// One grounded question per turn. Recognition is reviewed before returning;
/// this screen cannot save, confirm, or submit a report.
class ClosureVoiceTurn extends StatefulWidget {
  const ClosureVoiceTurn({
    super.key,
    required this.field,
    required this.recognizer,
    required this.synthesizer,
    required this.audio,
    required this.assertAccess,
    this.voiceDescription,
    this.cancelSpeech,
  });
  final FieldDefinition field;
  final SpeechRecognizer recognizer;
  final SpeechSynthesizer synthesizer;
  final VoiceAudio audio;
  final Future<void> Function() assertAccess;
  final String Function()? voiceDescription;
  final VoidCallback? cancelSpeech;
  @override
  State<ClosureVoiceTurn> createState() => _ClosureVoiceTurnState();
}

class _ClosureVoiceTurnState extends State<ClosureVoiceTurn>
    with WidgetsBindingObserver {
  String phase = 'Ready', transcript = '', error = '';
  Answer? proposed;
  final bytes = BytesBuilder(copy: false);
  Timer? clock;
  int generation = 0;
  double level = 0;
  bool get working => [
    'Preparing question',
    'Speaking',
    'Listening',
    'Understanding',
  ].contains(phase);
  String get question => closureSpokenQuestion(widget.field);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(start()));
  }

  @override
  void dispose() {
    widget.cancelSpeech?.call();
    generation++;
    clock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.audio.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(pause());
    }
  }

  Future<void> pause() async {
    widget.cancelSpeech?.call();
    generation++;
    clock?.cancel();
    bytes.clear();
    await widget.audio.stopCapture();
    await widget.audio.stopPlayback();
    if (mounted) {
      setState(() {
        phase = 'Paused';
        level = 0;
      });
    }
  }

  Future<void> start() async {
    final turn = ++generation;
    clock?.cancel();
    bytes.clear();
    setState(() {
      phase = 'Preparing question';
      error = '';
      transcript = '';
      proposed = null;
    });
    try {
      await widget.assertAccess();
      await widget.audio.configure(() => unawaited(pause()));
      final audio = await widget.synthesizer.synthesize(question);
      if (!mounted || turn != generation) return;
      await widget.assertAccess();
      if (!mounted || turn != generation) return;
      setState(() => phase = 'Speaking');
      final complete = await widget.audio.play(audio, (_) {});
      if (!mounted || turn != generation || !complete) return;
      if (!await widget.audio.hasPermission()) {
        throw StateError(
          'Microphone permission is needed. You can still answer in the form.',
        );
      }
      await widget.assertAccess();
      if (!mounted || turn != generation) return;
      final endpoint = TurnEndpoint(), watch = Stopwatch()..start();
      setState(() => phase = 'Listening');
      await widget.audio.capture(
        onBytes: (b) {
          if (turn == generation &&
              phase == 'Listening' &&
              bytes.length < 16000 * 2 * 45) {
            bytes.add(b);
          }
        },
        onLevel: (value) {
          if (!mounted || turn != generation || phase != 'Listening') return;
          setState(() => level = value);
          if (endpoint.observe(value, watch.elapsed)) unawaited(finish());
        },
        onError: (_) => unawaited(pause()),
      );
      if (!mounted || turn != generation) {
        await widget.audio.stopCapture();
        return;
      }
      clock = Timer(const Duration(seconds: 45), () => unawaited(finish()));
    } catch (_) {
      if (mounted && turn == generation) {
        setState(() {
          phase = 'Paused';
          error = 'Voice is unavailable. Retry or continue in the saved form.';
        });
      }
    }
  }

  Future<void> finish() async {
    if (phase != 'Listening') return;
    final turn = generation;
    clock?.cancel();
    setState(() {
      phase = 'Understanding';
      level = 0;
    });
    try {
      await widget.audio.stopCapture();
      final pcm = bytes.takeBytes();
      if (pcm.length < 640) throw StateError('No speech');
      final view = ByteData.sublistView(pcm),
          samples = Float32List(pcm.length ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = view.getInt16(i * 2, Endian.little) / 32768;
      }
      await widget.assertAccess();
      final text = (await widget.recognizer.transcribe(samples)).trim();
      await widget.assertAccess();
      if (!mounted || turn != generation) return;
      if (text.isEmpty) throw StateError('No speech');
      final candidate = closureSpokenAnswer(widget.field, text);
      setState(() {
        transcript = text;
        proposed = candidate;
        phase = 'Check what I heard';
      });
    } catch (_) {
      if (mounted && turn == generation) {
        setState(() {
          phase = 'Paused';
          error = 'No clear answer was captured. Retry or answer by touch.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !working,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Your field companion'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Close voice assistant',
            icon: const Icon(Icons.close),
            onPressed: () async {
              await pause();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (transcript.isNotEmpty && !working)
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await widget.assertAccess();
                      if (context.mounted) {
                        Navigator.pop(
                          context,
                          ClosureVoiceAnswer(transcript, proposed, question),
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error =
                              'Unlock the workspace before keeping this answer.',
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.check),
                  label: Text(
                    proposed == null
                        ? 'Keep transcript for review'
                        : 'Confirm this answer',
                  ),
                ),
              if (phase == 'Listening')
                FilledButton.icon(
                  onPressed: finish,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Finish answer'),
                ),
              if (!working)
                OutlinedButton.icon(
                  onPressed: start,
                  icon: const Icon(Icons.mic_none),
                  label: Text(
                    transcript.isEmpty ? 'Repeat question' : 'Try again',
                  ),
                ),
              if (working)
                TextButton(onPressed: pause, child: const Text('Pause')),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.voiceDescription?.call() ??
                  'ON-DEVICE VOICE · ENGINEER REVIEW REQUIRED',
              style: TextStyle(fontSize: 11, letterSpacing: 1.3),
            ),
            const SizedBox(height: 32),
            CircleAvatar(
              radius: 48,
              child: Icon(
                phase == 'Listening' ? Icons.mic : Icons.graphic_eq,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              phase,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 28),
            Text(question, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            const Text(
              'The microphone opens after the question finishes. Pause when it is unsafe to speak. Nothing is submitted by voice.',
            ),
            if (phase == 'Listening') ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(value: (level * 10).clamp(0, 1)),
            ],
            if (transcript.isNotEmpty) ...[
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('I heard'),
                      const SizedBox(height: 8),
                      Text(
                        '“$transcript”',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        proposed == null
                            ? 'This needs clarification. Keep the transcript and answer in the form.'
                            : 'Proposed answer: ${proposed!.toJson()}',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(error),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
}
