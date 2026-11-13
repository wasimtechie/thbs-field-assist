import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/structured_visit_extraction.dart';
import 'package:field_assist/features/voice/asset_reference.dart';
import 'support/voice_fakes.dart';
import 'closure_journey_test.dart' as fixture;

class ExtractionEngine extends TestEngine {
  ExtractionEngine(this.arguments) : super([]);
  final Json arguments;
  Completer<Json>? pending;
  @override
  Future<Json> extract(String text, List<Json> tools, String context) async {
    extractionCalls++;
    expect(tools.single['name'], 'record_visit_facts');
    return pending != null
        ? pending!.future
        : {
            'function_calls': [
              {'name': 'record_visit_facts', 'arguments': arguments},
            ],
          };
  }
}

void main() {
  final form = compactClosureForm(fixture.closureForm);
  Map<String, dynamic> values(List<Json> facts) => {
    for (final fact in facts) fact['fieldId'] as String: fact['value'],
  };
  for (final phrase in [
    'Reading was minus 18.2DBM.',
    'The reading was minus18.2DBM.',
    'The reading. was minus 18.2 dBm.',
    'The received power was −18.2 d.B.M.',
    'Optical receive reading was minus eighteen point two d B M.',
  ]) {
    test('extracts the explicit signed optical reading: $phrase', () {
      final facts = compactNarrativeFacts(form, phrase);
      expect(values(facts)['optical_rx_dbm'], -18.2);
      expect(
        phrase.contains(
          facts.firstWhere(
            (f) => f['fieldId'] == 'optical_rx_dbm',
          )['sourceSpan'],
        ),
        true,
      );
    });
  }
  test('target, TX, uncertain and conflicting readings stay unresolved', () {
    for (final phrase in [
      'The transmit reading was -18.2 dBm.',
      'The target reading was -18.2 dBm.',
      'The target optical receive -18.2 dBm.',
      'The transmit optical RX -18.2 dBm.',
      'I think the reading was minus 18.2 dBm.',
      'Reading was -18.2 dBm. Reading was -23.1 dBm.',
    ]) {
      expect(
        values(compactNarrativeFacts(form, phrase))['optical_rx_dbm'],
        isNull,
        reason: phrase,
      );
    }
  });
  test('ASR punctuation inside a completion claim preserves its evidence', () {
    const text = 'The service test passed. The job. is fully completed.';
    final facts = compactNarrativeFacts(form, text);
    expect(values(facts)['claimed_outcome'], 'completed');
    expect(values(facts)['operational_test'], 'passed');
    for (final fact in facts) {
      expect(text.contains(fact['sourceSpan']), true);
    }
  });
  test(
    'spoken asset letters and numbers normalize without phonetic guessing',
    () {
      for (final phrase in [
        'CBT-SYN-10',
        'C B T dash S Y N dash one zero',
        'CBT SYN ten',
      ]) {
        expect(spokenAssetReference(phrase), 'CBT-SYN-10');
      }
      for (final phrase in [
        'Paul. Paul.',
        'pole',
        'CBT unknown',
        'CBT checked',
      ]) {
        expect(spokenAssetReference(phrase), isNull);
        final field = fixture.closureForm.fields.firstWhere(
          (f) => f.id == 'serving_asset',
        );
        expect(closureSpokenAnswer(field, phrase), isNull);
      }
      expect(
        validateVisitSummary(
          fixture.closureForm,
          {'serving_asset': const TextAnswer('Paul. Paul.')},
          requireComplete: false,
        ).issues.any((i) => i.code == 'INVALID_ASSET_REFERENCE'),
        true,
      );
    },
  );
  test(
    'typed model proposals require exact evidence and allowed enum values',
    () async {
      const text =
          'Everything is now done. The service verification was successful.';
      final engine = ExtractionEngine({
        'outcome': 'completed',
        'outcome_evidence': 'Everything is now done.',
        'test_result': 'passed',
        'test_evidence': 'The service verification was successful.',
        'next_action': '',
      });
      final facts = await StructuredVisitExtractor(
        engine,
      ).extract(form, text, current: () => true);
      expect(values(facts)['claimed_outcome'], 'completed');
      expect(values(facts)['operational_test'], 'passed');
      expect(engine.extractionCalls, 1);
      for (final fact in facts) {
        expect(text.contains(fact['sourceSpan']), true);
      }
    },
  );
  test(
    'a model cannot manufacture success, identifiers or measurements',
    () async {
      final engine = ExtractionEngine({
        'outcome': 'completed',
        'outcome_evidence': 'I finished all the work.',
        'test_result': 'passed',
        'test_evidence': 'Connectivity checks were successful.',
        'next_action': '',
      });
      final facts = await StructuredVisitExtractor(engine).extract(
        form,
        'The job needs work. I started service checks.',
        current: () => true,
      );
      final v = values(facts);
      expect(v['claimed_outcome'], isNull);
      expect(v['operational_test'], isNull);
      expect(v['serving_asset'], isNull);
      expect(v['optical_rx_dbm'], isNull);
    },
  );
  test(
    'quote trimming cannot discard uncertainty or turn a test into success',
    () async {
      final engine = ExtractionEngine({
        'outcome': 'unknown',
        'outcome_evidence': '',
        'test_result': 'passed',
        'test_evidence': 'connectivity checks were successful',
        'next_action': '',
      });
      final facts = await StructuredVisitExtractor(engine).extract(
        form,
        'I think connectivity checks were successful.',
        current: () => true,
      );
      expect(values(facts)['operational_test'], isNull);
    },
  );
  test('completed checks alone do not establish a passing result', () async {
    final engine = ExtractionEngine({
      'outcome': 'unknown',
      'outcome_evidence': '',
      'test_result': 'passed',
      'test_evidence': 'Connectivity checks were completed.',
      'next_action': '',
    });
    final facts = await StructuredVisitExtractor(
      engine,
    ).extract(form, 'Connectivity checks were completed.', current: () => true);
    expect(values(facts)['operational_test'], isNull);
  });
  test('cancelled extraction cannot return late model facts', () async {
    final engine = ExtractionEngine({})..pending = Completer<Json>();
    var current = true;
    final operation = StructuredVisitExtractor(
      engine,
    ).extract(form, 'Everything is now done.', current: () => current);
    current = false;
    engine.pending!.complete({'function_calls': []});
    expect(await operation, isEmpty);
  });
}
