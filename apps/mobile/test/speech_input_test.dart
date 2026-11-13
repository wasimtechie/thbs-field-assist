import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/features/voice/speech_input.dart';
import 'package:field_assist/features/voice/conversation.dart';

void main() {
  test(
    'outer silence is trimmed but quiet negation and internal pauses remain',
    () {
      final pcm = Float32List.fromList([
        ...Float32List(16000 * 5),
        ...List.filled(3200, .002), // Quiet word below the endpoint threshold.
        ...Float32List(8000), // Pause inside the answer.
        ...List.filled(3200, .1),
        ...Float32List(32000),
      ]);
      final original = Float32List.fromList(pcm);
      final trimmed = trimSpeechSilence(pcm);
      expect(trimmed.length, 3840 * 2 + 3200 * 2 + 8000);
      expect(
        trimmed.sublist(3840, 7040),
        Float32List.fromList(List.filled(3200, .002)),
      );
      expect(trimmed.sublist(7040, 15040).every((v) => v == 0), isTrue);
      expect(pcm, original);
    },
  );
  test('silence and speech at either edge are never lost', () {
    final silence = Float32List(1000);
    expect(identical(trimSpeechSilence(silence), silence), isTrue);
    expect(trimSpeechSilence(Float32List(0)), isEmpty);
    final edgeSpeech = Float32List.fromList(List.filled(4000, .02));
    expect(trimSpeechSilence(edgeSpeech), edgeSpeech);
  });
  test(
    'focused answers end at 700 ms silence and preserve a pause in a number',
    () {
      final endpoint = TurnEndpoint(silence: const Duration(milliseconds: 700));
      endpoint.observe(.02, const Duration(milliseconds: 200));
      expect(endpoint.observe(0, const Duration(milliseconds: 700)), isFalse);
      endpoint.observe(.002, const Duration(milliseconds: 720));
      // A quieter fragment does not raise the release threshold.
      endpoint.observe(.006, const Duration(milliseconds: 740));
      expect(endpoint.observe(0, const Duration(milliseconds: 1420)), isFalse);
      expect(endpoint.observe(0, const Duration(milliseconds: 1440)), isTrue);
    },
  );
}
