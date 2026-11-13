import 'package:flutter_test/flutter_test.dart';
import '../../../scripts/stt-ab/score.dart' as scoring;

void main() {
  test('timing percentiles interpolate the same way for both engines', () {
    expect(scoring.percentile([10, 20], .5), 15);
    expect(scoring.percentile([10, 20], .95), closeTo(19.5, .0001));
    expect(scoring.percentile([5], .95), 5);
  });
  test('shared WER normalisation accepts standard ASR numeric orthography', () {
    expect(
      scoring.words('O N T optical receive minus eighteen point two d B M.'),
      scoring.words('ONT optical receive -18.2dBm.'),
    );
    expect(scoring.words('Fibre route'), scoring.words('fiber route'));
    expect(
      scoring.distance(
        ['service', 'test', 'passed'],
        ['service', 'test', 'failed'],
      ),
      1,
    );
  });
  test('literal reading score preserves the spoken sign and unit', () {
    expect(scoring.transcriptReadings('Reading was minus 18.2 dBm.'), [-18.2]);
    expect(scoring.transcriptReadings('Reading was -18.2 d B M.'), [-18.2]);
    expect(scoring.transcriptReadings('Reading was 18.2 dBm.'), [18.2]);
    expect(scoring.transcriptReadings('The splice loss was 0.2 dB.'), isEmpty);
    expect(
      scoring.transcriptReadings('I have not measured the optical power.'),
      isEmpty,
    );
  });
  test('contradictory ASR numbers remain distinct for critical scoring', () {
    expect(scoring.transcriptReadings('Reading 8.2 dBm was -8.2 dBm.'), [
      8.2,
      -8.2,
    ]);
    expect(scoring.transcriptReadings('Reading -8.2 dBm. Reading -8.2 dBm.'), [
      -8.2,
    ]);
  });
}
