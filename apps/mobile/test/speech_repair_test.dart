import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/optical_reading.dart';
import 'package:field_assist/features/voice/speech_repair.dart';
import 'closure_journey_test.dart' as fixture;

void main() {
  final form = compactClosureForm(fixture.closureForm);
  final field = form.fields.firstWhere((f) => f.id == 'optical_rx_dbm');
  Map<String, dynamic> facts(String text) => {
    for (final f in compactNarrativeFacts(form, text))
      f['fieldId'] as String: f,
  };

  test('personal restarts keep the final stated identity, with raw evidence', () {
    const raw =
        "hello i'm waseem from local, sorry i stay here, sorry i'm waseem from bangalore.";
    final result = interpretSpokenRepairs(raw);
    expect(result.text, "i'm waseem from bangalore.");
    expect(result.raw, raw);
    expect(result.repairs, hasLength(2));
    expect(facts(raw)['actual_work']['value'], result.text);
    expect(facts(raw)['actual_work']['rawTranscript'], raw);
  });

  for (final raw in [
    'The reading is 18.2, no no sorry the readings is -18.19.',
    'The optical receive reading was 18.2 dBm. No, sorry, the optical receive reading was -18.19 dBm.',
    'The optical receive reading was 18.2 dBm, I mean minus eighteen point one nine dBm.',
    'The optical receive was 18.2 dBm, make that -18.19 dBm.',
  ]) {
    test('an explicit corrected reading wins: $raw', () {
      final f = facts(raw)['optical_rx_dbm'];
      expect(f['value'], -18.19);
      expect(f['requiresConfirmation'], isNot(true));
      expect(f['rawTranscript'], raw);
      expect(f['speechRepairs'], isNotEmpty);
      expect(raw.contains(f['sourceSpan'] as String), true);
      expect(closureSpokenAnswer(field, raw)?.toJson(), -18.19);
    });
  }

  test('correction to a bare number uses the active measurement question', () {
    expect(
      closureSpokenAnswer(field, 'minus eighteen point nineteen')?.toJson(),
      -18.19,
    );
    expect(
      closureSpokenAnswer(field, 'minus eighteen point ninety five')?.toJson(),
      -18.95,
    );
    expect(
      closureSpokenAnswer(field, '18.2, no no sorry -18.19')?.toJson(),
      -18.19,
    );
    expect(
      closureSpokenAnswer(
        field,
        'minus eighteen point two, sorry minus eighteen point one nine',
      )?.toJson(),
      -18.19,
    );
  });

  test(
    'a reading repair preserves other work and test facts, even across turns',
    () {
      const raw =
          'I installed the ONT. Optical receive reading was -18.2 dBm. '
          'The service test passed. The job is fully completed.\n'
          'Sorry the optical receive reading was -18.19 dBm.';
      final result = facts(raw);
      expect(result['actual_work']['value'], contains('I installed the ONT'));
      expect(
        result['actual_work']['value'],
        contains('The service test passed'),
      );
      expect(result['claimed_outcome']['value'], 'completed');
      expect(result['operational_test']['value'], 'passed');
      expect(result['optical_rx_dbm']['value'], -18.19);
    },
  );

  test('corrected test result removes only the retracted result', () {
    final result = facts(
      'I installed the ONT. The service test failed, sorry the service test passed. The job is fully completed.',
    );
    expect(result['operational_test']['value'], 'passed');
    expect(result['claimed_outcome']['value'], 'completed');
    expect(result['actual_work']['value'], contains('I installed the ONT'));
  });

  test('the observed received-measurement paraphrase fills the reading', () {
    expect(
      facts(
        'The optical received measurement was minus 17.8 dBm.',
      )['optical_rx_dbm']['value'],
      -17.8,
    );
  });

  for (final raw in [
    'Optical receive reading 8.2 dBm was -8.2 dBm.',
    'The optical receive reading was -18.2 or -19.1 dBm.',
    'The optical receive reading was -18.2 dBm or -19.1.',
    'The optical receive reading was -18.2 dBm. The reading was -19.1 dBm.',
  ]) {
    test('unresolved alternatives are not accepted: $raw', () {
      expect(facts(raw)['optical_rx_dbm']['value'], isNull);
      expect(closureSpokenAnswer(field, raw), isNull);
    });
  }

  test('units and signs are not silently repaired', () {
    expect(
      facts(
        'The optical receive reading was 18.2 dBm.',
      )['optical_rx_dbm']['value'],
      18.2,
    );
    expect(
      facts(
        'The optical receive reading was -18.19 dB.',
      )['optical_rx_dbm']['unitNeedsConfirmation'],
      true,
    );
    expect(
      facts('The reading is -18.19.')['optical_rx_dbm']['unitSource'],
      'field_definition',
    );
    expect(opticalNarrativeFacts('The reading is -18.19.'), isEmpty);
    expect(facts('The splice loss was 0.2 dB.')['optical_rx_dbm'], isNull);
  });

  test(
    'an apology about a different measurement does not retract receive power',
    () {
      final result = facts(
        'Optical receive reading was -18.2 dBm. Sorry the transmit reading was 2.1 dBm.',
      );
      expect(result['optical_rx_dbm']['value'], -18.2);
    },
  );
}
