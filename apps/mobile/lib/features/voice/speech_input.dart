import 'dart:math' as math;
import 'dart:typed_data';

/// Reduce recognition work after waiting for an answer. Only outer silence is
/// removed; internal pauses and 240 ms around speech stay intact. The threshold
/// is below endpoint detection so quiet words such as "not" are retained.
Float32List trimSpeechSilence(Float32List pcm16k) {
  const frame = 320, context = 3840; // 20 ms frames, 240 ms context at 16 kHz.
  const thresholdSquared = .001 * .001;
  int? first, last;
  for (var at = 0; at < pcm16k.length; at += frame) {
    final end = math.min(at + frame, pcm16k.length);
    var power = 0.0;
    for (var i = at; i < end; i++) {
      power += pcm16k[i] * pcm16k[i];
    }
    if (power / (end - at) >= thresholdSquared) {
      first ??= at;
      last = end;
    }
  }
  // Let the recognizer handle silence/very quiet audio; never fabricate words.
  if (first == null || last == null) return pcm16k;
  return Float32List.sublistView(
    pcm16k,
    math.max(0, first - context),
    math.min(pcm16k.length, last + context),
  );
}
