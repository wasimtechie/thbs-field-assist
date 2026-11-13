import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/features/closure/question_voice.dart';
import 'package:field_assist/features/voice/speech_output_level.dart';

SynthesizedAudio tone(double amplitude) => SynthesizedAudio(
  Float32List.fromList([
    for (var i = 0; i < 16000; i++)
      amplitude * math.sin(2 * math.pi * 200 * i / 16000),
  ]),
  16000,
);

void main() {
  test(
    'quiet and loud speech match without changing the source, duration or sample rate',
    () {
      final quiet = tone(.015), loud = tone(.5);
      final original = Float32List.fromList(quiet.samples);
      final a = levelSpeechOutput(quiet), b = levelSpeechOutput(loud);
      expect(activeSpeechRms(a), closeTo(speechTargetRms, .005));
      expect(activeSpeechRms(b), closeTo(activeSpeechRms(a), .005));
      expect(a.sampleRate, quiet.sampleRate);
      expect(a.samples.length, quiet.samples.length);
      expect(quiet.samples, original);
      expect(a.samples.every((v) => v.abs() <= speechPeakCeiling), true);
    },
  );
  test(
    'level changes inside a phrase are reduced while silence remains silent',
    () {
      final a = tone(.03), b = tone(.3);
      final input = SynthesizedAudio(
        Float32List.fromList([
          ...Float32List(3200),
          ...a.samples,
          ...b.samples,
          ...Float32List(3200),
        ]),
        16000,
      );
      final output = levelSpeechOutput(input);
      double section(int at) => activeSpeechRms(
        SynthesizedAudio(
          Float32List.sublistView(output.samples, at, at + 12000),
          16000,
        ),
      );
      expect(section(20800) / section(4800), lessThan(5));
      expect(output.samples.take(3200).every((v) => v == 0), true);
      expect(
        output.samples.skip(output.samples.length - 3200).every((v) => v == 0),
        true,
      );
    },
  );
  test('invalid samples are rejected and sharp peaks retain headroom', () {
    final input = tone(.05);
    for (var i = 0; i < input.samples.length; i += 600) {
      input.samples[i] = .99;
    }
    final output = levelSpeechOutput(input);
    expect(
      output.samples.every((v) => v.isFinite && v.abs() <= speechPeakCeiling),
      true,
    );
    expect(
      levelSpeechOutput(
        SynthesizedAudio(Float32List(160), 16000),
      ).samples.every((v) => v == 0),
      true,
    );
    expect(
      () => levelSpeechOutput(
        SynthesizedAudio(Float32List.fromList([double.nan]), 16000),
      ),
      throwsFormatException,
    );
  });
  test(
    'every prepared prompt plays at a consistent speech level with no clipped peaks',
    () {
      final pack = Directory('assets/voice_questions');
      final index =
          jsonDecode(File('${pack.path}/index.json').readAsStringSync())
              as Map<String, dynamic>;
      final rawLevels = <double>[], adjustedLevels = <double>[];
      final clips = <Map<String, dynamic>>[];
      for (final entry in (index['prompts'] as Map<String, dynamic>).values) {
        final raw = decodeQuestionWav(
          File('${pack.path}/${entry['file']}').readAsBytesSync(),
        );
        final adjusted = levelSpeechOutput(raw);
        final before = 20 * math.log(activeSpeechRms(raw)) / math.ln10;
        final after = 20 * math.log(activeSpeechRms(adjusted)) / math.ln10;
        final peak = adjusted.samples.fold<double>(
          0,
          (p, v) => math.max(p, v.abs()),
        );
        rawLevels.add(before);
        adjustedLevels.add(after);
        clips.add({
          'fieldId': entry['fieldId'],
          'beforeActiveRmsDbfs': before,
          'afterActiveRmsDbfs': after,
          'afterPeak': peak,
        });
        expect(adjusted.samples.length, raw.samples.length);
        expect(
          peak,
          lessThanOrEqualTo(speechPeakCeiling),
          reason: entry['fieldId'],
        );
        expect(after, inInclusiveRange(-21.0, -19.0), reason: entry['fieldId']);
      }
      final spread =
          adjustedLevels.reduce(math.max) - adjustedLevels.reduce(math.min);
      expect(spread, lessThan(1));
      // Opt-in repeatable evidence, with no microphone data or engineer text.
      if (Platform.environment['WRITE_VOICE_LEVEL_REPORT'] == '1') {
        File(
          '../../fixtures/voice/benchmarks/voice-output-levels.json',
        ).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert({'scope': 'Prepared synthetic prompts only; active frame RMS is not LUFS, subjective quality or a phone speaker measurement.', 'model': index['model'], 'voice': index['voice'], 'recordings': clips.length, 'targetRms': speechTargetRms, 'peakCeiling': speechPeakCeiling, 'rawSpreadDb': rawLevels.reduce(math.max) - rawLevels.reduce(math.min), 'playbackSpreadDb': spread, 'clips': clips})}\n',
        );
      }
    },
  );
}
