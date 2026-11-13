import 'package:field_voice/field_voice.dart';
import '../../core/contracts.dart';
import '../voice/asset_reference.dart';
import '../voice/speech_repair.dart';
import 'compact_narrative.dart';

/// The model proposes qualitative facts using one flat, typed function call.
/// Exact numeric/identifier parsing and source-grounding remain authoritative.
/// This is local extraction, not a model-authored replacement for the report.
class StructuredVisitExtractor {
  const StructuredVisitExtractor(this.engine);
  final FieldExtractor engine;

  Future<List<Json>> extract(
    FormDefinition form,
    String raw, {
    required bool Function() current,
  }) async {
    final interpretation = interpretSpokenRepairs(raw);
    final text = interpretation.text;
    final facts = {
      for (final fact in compactNarrativeFacts(form, raw))
        fact['fieldId'] as String: fact,
    };
    final lower = text.toLowerCase();
    final missingOutcome =
        !facts.containsKey('claimed_outcome') &&
        RegExp(
          r'\b(?:work|job|installation|visit|everything)\b',
        ).hasMatch(lower) &&
        RegExp(
          r'\b(?:done|finished|complete|completed|partial|partially|blocked|hold|outstanding|remaining)\b',
        ).hasMatch(lower);
    final missingTest =
        !facts.containsKey('operational_test') &&
        RegExp(
          r'\b(?:test|tested|verified|verification|checks)\b',
        ).hasMatch(lower);
    final missingAction =
        !facts.containsKey('next_action') &&
        RegExp(
          r"\b(?:need|needs|return|arrange|waiting|awaiting|tomorrow|follow[- ]?up|nothing left)\b",
        ).hasMatch(lower);
    if (!current()) return [];
    if (!(missingOutcome || missingTest || missingAction)) {
      return facts.values.toList();
    }
    try {
      final response = await engine.extract(
        text,
        [
          {
            'name': 'record_visit_facts',
            'description':
                'Extract explicit visit outcome, service test and follow-up. Unknown facts stay unknown. Copy evidence verbatim.',
            'parameters': {
              'type': 'object',
              'properties': {
                'outcome': {
                  'type': 'string',
                  'enum': [
                    'completed',
                    'partial',
                    'blocked',
                    'hold',
                    'referred',
                    'unknown',
                  ],
                },
                'outcome_evidence': {
                  'type': 'string',
                  'description':
                      'Exact quote supporting the outcome, or empty.',
                },
                'test_result': {
                  'type': 'string',
                  'enum': ['passed', 'failed', 'not_tested', 'unknown'],
                },
                'test_evidence': {
                  'type': 'string',
                  'description':
                      'Exact quote supporting the service test, or empty.',
                },
                'next_action': {
                  'type': 'string',
                  'description': 'Exact spoken follow-up action, or empty.',
                },
              },
              'required': [
                'outcome',
                'outcome_evidence',
                'test_result',
                'test_evidence',
                'next_action',
              ],
            },
          },
        ],
        'Extract stated facts only. Never infer measurements, identifiers, test success, consent or safety. Installation alone is not completion. Use unknown when absent or uncertain.',
      );
      if (!current()) return [];
      final calls = response['function_calls'];
      if (calls is! List || calls.length != 1) return facts.values.toList();
      final call = calls.single;
      if (call is! Map ||
          call['name'] != 'record_visit_facts' ||
          call['arguments'] is! Map) {
        return facts.values.toList();
      }
      final args = call['arguments'] as Map;
      if (args.keys.any(
        (key) => ![
          'outcome',
          'outcome_evidence',
          'test_result',
          'test_evidence',
          'next_action',
        ].contains(key),
      )) {
        return facts.values.toList();
      }
      void accept(String id, Object? value, Object? evidence, bool eligible) {
        if (!eligible ||
            value == null ||
            value == 'unknown' ||
            evidence is! String ||
            evidence.trim().isEmpty ||
            !text.contains(evidence) ||
            evidence.length > 2000) {
          return;
        }
        final at = text.indexOf(evidence);
        final before = text.substring(0, at).split(RegExp(r'[.;!?\n]')).last;
        final after = text
            .substring(at + evidence.length)
            .split(RegExp(r'[.;!?\n]'))
            .first;
        final sourceContext = '$before$evidence$after';
        if (RegExp(
          r"\b(?:maybe|might|probably|think|not sure|unconfirmed|not confirmed)\b",
          caseSensitive: false,
        ).hasMatch(sourceContext)) {
          return;
        }
        if (id == 'claimed_outcome') {
          if (![
            'completed',
            'partial',
            'blocked',
            'hold',
            'referred',
          ].contains(value)) {
            return;
          }
          if (value == 'completed' &&
              RegExp(
                r"\b(?:not|never|didn't|haven't|couldn't|remaining|outstanding)\b",
                caseSensitive: false,
              ).hasMatch(text)) {
            return;
          }
          final nonCompletedEvidence = {
            'partial':
                r'\b(?:partial|partially|incomplete|unfinished|remaining|outstanding|some work|not finished|not complete)\b',
            'blocked':
                r"\b(?:blocked|unable|could not|couldn't|prevented|no access)\b",
            'hold': r'\b(?:hold|paused|pause|waiting)\b',
            'referred':
                r'\b(?:referred|referral|handed|handover|another team)\b',
          };
          if (nonCompletedEvidence[value] != null &&
              !RegExp(
                nonCompletedEvidence[value]!,
                caseSensitive: false,
              ).hasMatch(sourceContext)) {
            return;
          }
          if (!RegExp(
            r'\b(?:work|job|installation|visit|everything)\b',
            caseSensitive: false,
          ).hasMatch(evidence)) {
            return;
          }
          if (value == 'completed' &&
              !RegExp(
                r'\b(?:complete|completed|done|finished)\b',
                caseSensitive: false,
              ).hasMatch(sourceContext)) {
            return;
          }
        }
        if (id == 'operational_test') {
          if (!['passed', 'failed', 'not_tested'].contains(value)) return;
          if (!RegExp(
            r'\b(?:test|tested|verified|verification|checks)\b',
            caseSensitive: false,
          ).hasMatch(evidence)) {
            return;
          }
          if (value == 'passed' &&
              RegExp(
                r"\b(?:not|never|didn't|haven't|failed)\b",
                caseSensitive: false,
              ).hasMatch(evidence)) {
            return;
          }
          if (value == 'passed' &&
              !RegExp(
                r'\b(?:passed|successful|successfully|working|good|okay|ok)\b',
                caseSensitive: false,
              ).hasMatch(evidence)) {
            return;
          }
          if (value == 'failed' &&
              !RegExp(
                r'\b(?:failed|failure|unsuccessful|not working)\b',
                caseSensitive: false,
              ).hasMatch(evidence)) {
            return;
          }
          if (value == 'not_tested' &&
              !RegExp(
                r"\b(?:not tested|never tested|(?:did not|didn't|could not|couldn't|haven't|have not) (?:test|run|perform|carry)|(?:tests?|checks?) (?:was |were |have been |has been )?not (?:run|performed|completed|carried out))\b",
                caseSensitive: false,
              ).hasMatch(evidence)) {
            return;
          }
        }
        if (id == 'next_action' &&
            !RegExp(
              r"\b(?:need|needs|return|arrange|waiting|awaiting|tomorrow|follow[- ]?up|nothing left)\b",
              caseSensitive: false,
            ).hasMatch(evidence)) {
          return;
        }
        final answer = decodeAnswers({id: value})[id];
        if (answer == null ||
            validate(form, {
              id: answer,
            }, requireComplete: false).issues.any((i) => i.fieldId == id)) {
          return;
        }
        facts[id] = interpretation.ground({
          'fieldId': id,
          'value': value,
          'sourceType': 'speech',
          'sourceSpan': evidence,
          'verificationStatus': 'candidate',
          'confidence': null,
        });
      }

      accept(
        'claimed_outcome',
        args['outcome'],
        args['outcome_evidence'],
        missingOutcome,
      );
      accept(
        'operational_test',
        args['test_result'],
        args['test_evidence'],
        missingTest,
      );
      accept(
        'next_action',
        args['next_action'],
        args['next_action'],
        missingAction,
      );
    } catch (_) {
      // Local extraction failure leaves the grounded direct facts intact. Ask
      // the unresolved question rather than filling a guess or using a server.
    }
    return current() ? facts.values.toList() : [];
  }
}

ValidationResult validateVisitSummary(
  FormDefinition form,
  Answers values, {
  bool requireComplete = true,
}) {
  final base = validate(form, values, requireComplete: requireComplete);
  final asset = values['serving_asset'];
  return ValidationResult(base.values, [
    ...base.issues,
    if (!missing(asset) &&
        (asset is! TextAnswer || spokenAssetReference(asset.value) == null))
      const ValidationIssue(
        'serving_asset',
        'INVALID_ASSET_REFERENCE',
        'Enter the asset identifier, including its letters and numbers, or leave it unanswered.',
      ),
  ], base.excluded);
}
