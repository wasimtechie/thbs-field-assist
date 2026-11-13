import 'dart:math' as math;
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';

/// Only for the assistant's synthesized output. Never process microphone PCM.
/// The target is an app playback setting, not a device-volume or LUFS claim.
const speechTargetRms = .10;
const speechPeakCeiling = .75;

List<double> _frames(Float32List samples, int width) => [
  for (var at = 0; at < samples.length; at += width)
    math.sqrt(
      samples
              .getRange(at, math.min(at + width, samples.length))
              .fold<double>(0, (sum, value) => sum + value * value) /
          math.min(width, samples.length - at),
    ),
];

double activeSpeechRms(SynthesizedAudio audio) {
  if (audio.samples.isEmpty || audio.sampleRate < 50) return 0;
  final frames = _frames(audio.samples, audio.sampleRate ~/ 50);
  final gate = math.max(.00001, frames.reduce(math.max) * .03);
  final active = frames.where((rms) => rms > gate).toList();
  return active.isEmpty
      ? 0
      : math.sqrt(
          active.fold<double>(0, (sum, rms) => sum + rms * rms) / active.length,
        );
}

/// Gently reduce differences within a clip, then match speech level between
/// clips. A soft peak limit leaves headroom without hard clipping. Timing,
/// pitch, sample rate and the original source buffer remain unchanged.
SynthesizedAudio levelSpeechOutput(SynthesizedAudio audio) {
  if (audio.sampleRate < 8000 || audio.samples.any((v) => !v.isFinite)) {
    throw const FormatException('Invalid synthesized speech.');
  }
  if (audio.samples.isEmpty) return audio;
  final width = audio.sampleRate ~/ 50;
  final frames = _frames(audio.samples, width);
  final highest = frames.reduce(math.max);
  if (highest < .00001) return audio;
  final gate = math.max(.00001, highest * .03);
  var held = 1.0;
  final gains = [
    for (final rms in frames)
      if (rms > gate)
        held = math.sqrt(speechTargetRms / rms).clamp(.5, 3.0)
      else
        held,
  ];
  final smooth = <double>[
    for (var i = 0; i < gains.length; i++)
      (gains[(i - 2).clamp(0, gains.length - 1)] +
              2 * gains[(i - 1).clamp(0, gains.length - 1)] +
              3 * gains[i] +
              2 * gains[(i + 1).clamp(0, gains.length - 1)] +
              gains[(i + 2).clamp(0, gains.length - 1)]) /
          9,
  ];
  final output = Float32List(audio.samples.length);
  for (var i = 0; i < output.length; i++) {
    final frame = i ~/ width, fraction = (i % width) / width;
    final gain =
        smooth[frame] * (1 - fraction) +
        smooth[math.min(frame + 1, smooth.length - 1)] * fraction;
    output[i] = audio.samples[i] * gain;
  }
  final adjusted = SynthesizedAudio(output, audio.sampleRate);
  final rms = activeSpeechRms(adjusted);
  if (rms == 0) return adjusted;
  final match = speechTargetRms / rms;
  const knee = .5, headroom = speechPeakCeiling - knee;
  for (var i = 0; i < output.length; i++) {
    final value = output[i] * match, magnitude = value.abs();
    output[i] = magnitude <= knee
        ? value
        : value.sign *
              (knee +
                  headroom * (1 - math.exp(-(magnitude - knee) / headroom)));
  }
  return adjusted;
}
