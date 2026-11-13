import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'closure_journey_test.dart' as fixture;

void main() {
  final form = compactClosureForm(fixture.closureForm);
  Map<String, dynamic> map(String text) => {
    for (final f in compactNarrativeFacts(form, text))
      f['fieldId'] as String: f['value'],
  };
  test('the supplied S1 rehearsal leaves only next action missing', () {
    final v = map(
      'I installed the ONT in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two dBm. The service test passed. The job is fully completed. I showed the customer the equipment.',
    );
    expect(v['claimed_outcome'], 'completed');
    expect(v['operational_test'], 'passed');
    expect(v['optical_rx_dbm'], -18.2);
    expect(compactClosureLabels.keys.where((id) => v[id] == null), [
      'next_action',
    ]);
  });
  test('seven sentences populate all five fields with exact source spans', () {
    const text =
        'Installed the ONT in the living room. Used the existing duct. Connected at CBT-SYN-10. Optical receive -18.2 dBm. Service test passed. The job is fully completed. No further work required.';
    final facts = compactNarrativeFacts(form, text), v = map(text);
    expect(v.keys, containsAll(compactClosureLabels.keys));
    expect(v['actual_work'], text);
    expect(v['claimed_outcome'], 'completed');
    expect(v['serving_asset'], isNull);
    expect(v['optical_rx_dbm'], -18.2);
    expect(v['operational_test'], 'passed');
    expect(v['next_action'], 'No further work required');
    for (final f in facts) {
      expect(text.contains(f['sourceSpan'] as String), isTrue);
    }
  });
  test(
    'unpunctuated native ASR keeps spoken minus and separates the follow-up',
    () {
      const text =
          'installed the ONT in the living room used the existing duct connected the fiber at the serving terminal optical receive minus 18.2 dbm service test passed the job is fully completed no further work required';
      final v = map(text);
      expect(v['optical_rx_dbm'], -18.2);
      expect(v['operational_test'], 'passed');
      expect(v['claimed_outcome'], 'completed');
      expect(v['next_action'], 'no further work required');
      expect(v['serving_asset'], isNull);
    },
  );
  test('conflicts require a follow-up rather than choosing a result', () {
    final v = map(
      'Optical receive -18.2 dBm. Optical receive -30.1 dBm. Service test passed. Service test failed. Work completed. Work partially completed.',
    );
    expect(v['optical_rx_dbm'], isNull);
    expect(v['operational_test'], isNull);
    expect(v['claimed_outcome'], isNull);
  });
  test('progress never implies test success, reading or outcome', () {
    final v = map(
      'Installed ONT. Customer shown equipment. I think the service test passed. Optical reading not measured.',
    );
    expect(v['optical_rx_dbm'], isNull);
    expect(v['operational_test'], isNull);
    expect(v['claimed_outcome'], isNull);
  });
  test('negated and uncertain outcomes never become completed', () {
    for (final text in [
      'The job is not completed.',
      'I have not completed the installation.',
      'Maybe the work is completed.',
    ]) {
      expect(map(text)['claimed_outcome'], isNull);
    }
  });
  test('spoken-sign reading still rejects uncertainty', () {
    expect(
      map('I think optical receive minus 18.2 dbm')['optical_rx_dbm'],
      isNull,
    );
  });
  test('end-of-summary responses do not swallow work detail', () {
    for (final t in [
      "That's everything.",
      'No, nothing else.',
      "That's all, thank you.",
      'No.',
    ]) {
      expect(summaryFinished(t), isTrue, reason: t);
    }
    for (final t in [
      'Completed',
      'No service at the property',
      'No further work required',
      'The job is complete',
    ]) {
      expect(summaryFinished(t), isFalse, reason: t);
    }
  });
}
