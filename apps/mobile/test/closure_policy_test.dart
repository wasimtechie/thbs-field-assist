import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/closure_extraction.dart';
import 'package:field_assist/features/closure/closure_speech.dart';

void main() {
  final raw =
      jsonDecode(
            File(
              '../../fixtures/templates/closure-mvp.json',
            ).readAsStringSync(),
          )
          as Json;
  final schema = FormDefinition.fromJson(raw);
  test(
    'punctuated explicit yes/no answers stay grounded in the active question',
    () {
      final field = schema.fields.firstWhere(
        (f) => f.id == 'identity_verified',
      );
      expect(closureSpokenAnswer(field, 'Yes, I did.')?.toJson(), true);
      expect(closureSpokenAnswer(field, 'No, I did not.')?.toJson(), false);
      expect(closureSpokenAnswer(field, 'I think so'), isNull);
    },
  );
  test(
    'a long spoken visit preserves early field sources in bounded pages',
    () {
      var pages = <String>[];
      final turns = [
        for (var i = 0; i < 70; i++)
          'Question $i: ${List.filled(80, 'q').join()}\nEngineer: answer-$i',
      ];
      for (final turn in turns) {
        pages = retainClosureSources(pages, [turn]);
      }
      expect(pages.length, lessThanOrEqualTo(8));
      expect(pages.every((p) => p.length <= 4000), isTrue);
      for (final turn in turns) {
        expect(pages.any((p) => p.contains(turn)), isTrue);
      }
    },
  );
  test(
    'spoken outcomes distinguish a stage, referral and unknown completion',
    () {
      final field = schema.fields.firstWhere((f) => f.id == 'claimed_outcome');
      expect(closureSpokenQuestion(field), contains('network ready'));
      expect(
        closureSpokenAnswer(field, 'stage completed')?.toJson(),
        'stage_completed',
      );
      expect(closureSpokenAnswer(field, 'on hold')?.toJson(), 'hold');
      expect(closureSpokenAnswer(field, 'not completed'), isNull);
    },
  );
  test(
    'narrative model enrichment is bounded and excludes high-consequence facts',
    () {
      final targets = closureNarrativeTargets(
        schema,
        decodeAnswers({'scenario': 'S1', 'work_stage': 'final_provision'}),
        {'actual_work'},
      );
      expect(targets.length, lessThanOrEqualTo(4));
      expect(
        targets.every(
          (f) => closureModelMaySuggest(f.id) && f.id != 'actual_work',
        ),
        isTrue,
      );
    },
  );
  final pathways =
      jsonDecode(
            File('../../fixtures/closure-mvp/pathways.json').readAsStringSync(),
          )
          as List;
  final photos = <Json>[
    for (final s in ['before', 'installation', 'test', 'blocker']) {'stage': s},
  ];
  for (final p in pathways) {
    test('${p['id']} matches the shared policy', () {
      final values = p['values'] as Json;
      final result = checkClosure(raw, values, photos);
      expect(result.recommendation, p['expectedRecommendation']);
      if (p['expectedRecommendation'] != 'completed') {
        expect(result.serviceLive, isFalse);
      }
      for (final id in p['expectedHidden'] as List) {
        expect(
          schema.visible(
            schema.fields.firstWhere((f) => f.id == id),
            decodeAnswers(values),
          ),
          isFalse,
        );
      }
    });
  }
  test(
    'source facts retain exact spans and do not fabricate consent or optical passes',
    () {
      const text =
          'Installed ONT at agreed location using existing duct. CSP checked, optical receive -18.2 dBm; service test passed. Customer shown equipment.';
      final facts = literalClosureFacts(text);
      expect(
        facts.firstWhere((f) => f['fieldId'] == 'optical_rx_dbm')['value'],
        -18.2,
      );
      expect(
        facts.any(
          (f) => [
            'access_permission',
            'drilling_consent',
            'optical_test',
            'safety_hazard',
          ].contains(f['fieldId']),
        ),
        isFalse,
      );
      for (final f in facts) {
        expect(text.contains(f['sourceSpan'] as String), isTrue);
        expect(f['verificationStatus'], 'candidate');
      }
    },
  );
  test(
    'no light is a symptom and model confidence cannot invent critical facts',
    () {
      final facts = literalClosureFacts(
        'ONT is in. No light. Civils request raised.',
      );
      expect(facts.any((f) => f['fieldId'] == 'optical_test'), isFalse);
      expect(
        facts.firstWhere((f) => f['fieldId'] == 'issue_type')['value'],
        'no_light',
      );
      for (final id in [
        'optical_test',
        'optical_rx_dbm',
        'drilling_consent',
        'safety_hazard',
        'fibre_connected',
      ]) {
        expect(closureModelMaySuggest(id), isFalse);
      }
      expect(closureModelMaySuggest('next_owner'), isTrue);
    },
  );
  test('conflicting optical readings stay unanswered until clarified', () {
    final facts = literalClosureFacts('RX -30.2 dBm, RX -18.1 dBm.');
    final reading = facts.firstWhere((f) => f['fieldId'] == 'optical_rx_dbm');
    expect(reading['value'], isNull);
    expect(reading['ambiguityReason'], contains('Conflicting'));
  });
  test('synthetic examples contain the required applicable answers', () {
    final examples =
        jsonDecode(
              File(
                '../../fixtures/closure-mvp/examples.json',
              ).readAsStringSync(),
            )
            as Json;
    for (final e in examples.entries) {
      final answers = decodeAnswers(e.value as Json);
      final result = validate(schema, answers);
      expect(
        result.issues.map((i) => '${i.fieldId}: ${i.message}').toList(),
        isEmpty,
        reason: e.key,
      );
      expect(
        checkClosure(raw, encodeAnswers(result.values), photos).issues,
        isEmpty,
        reason: e.key,
      );
    }
  });
}
