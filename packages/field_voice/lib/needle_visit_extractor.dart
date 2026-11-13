part of 'field_voice.dart';

/// The same small Needle3 model, with its supported one-field tool format.
/// It proposes labels only. The app independently verifies verbatim evidence,
/// negation, uncertainty and field constraints before accepting any label.
class NeedleVisitExtractor implements FieldExtractor {
  NeedleVisitExtractor(this.engine);
  final FieldExtractor engine;

  @override
  Future<Map<String, dynamic>> extract(
    String transcript,
    List<Map<String, dynamic>> tools,
    String context,
  ) async {
    if (tools.length != 1 || tools.single['name'] != 'record_visit_facts') {
      throw const VoiceFailure(
        'UNSUPPORTED_SCHEMA',
        'Unsupported visit schema.',
      );
    }
    final arguments = <String, dynamic>{
      'outcome': 'unknown',
      'outcome_evidence': '',
      'test_result': 'unknown',
      'test_evidence': '',
      'next_action': '',
    };
    final clauses = transcript.split(RegExp(r'(?<!\d)[.;!?]\s*|[;!?]\s*|\n+'));
    for (final target in [
      (
        key: 'outcome',
        evidence: 'outcome_evidence',
        tool: 'record_claimed_outcome',
        label: 'visit outcome',
        values: ['completed', 'partial', 'blocked', 'hold', 'referred'],
        subject: r'\b(?:work|job|installation|visit|everything)\b',
        claim:
            r'\b(?:complete|completed|done|finished|partial|partially|blocked|hold|paused|referred|remaining|outstanding)\b',
      ),
      (
        key: 'test_result',
        evidence: 'test_evidence',
        tool: 'record_operational_test',
        label: 'service test result',
        values: ['passed', 'failed', 'not_tested'],
        subject: r'\b(?:test|tested|checks|verified|verification)\b',
        claim:
            r'\b(?:passed|successful|successfully|working|failed|failure|not|never|good|okay|ok)\b',
      ),
    ]) {
      final candidates = clauses
          .where(
            (c) =>
                c.trim().isNotEmpty &&
                c.length <= 1000 &&
                RegExp(target.subject, caseSensitive: false).hasMatch(c) &&
                RegExp(target.claim, caseSensitive: false).hasMatch(c),
          )
          .toList();
      // Never select one of multiple potentially conflicting source clauses.
      if (candidates.length != 1) continue;
      final source = candidates.single.trim();
      if (RegExp(
        r'\b(?:maybe|might|probably|think|not sure|unconfirmed|not confirmed)\b',
        caseSensitive: false,
      ).hasMatch(source)) {
        continue;
      }
      try {
        final response = await engine
            .extract(
              source,
              [
                {
                  'name': target.tool,
                  'description': 'Record the ${target.label}.',
                  'parameters': {
                    'type': 'object',
                    'properties': {
                      'result': {'type': 'string', 'enum': target.values},
                    },
                    'required': ['result'],
                  },
                },
              ],
              'Extract only the explicitly stated ${target.label}. Preserve negation. Do not infer missing facts.',
            )
            .timeout(const Duration(seconds: 3));
        final confidence = response['confidence'];
        if (confidence is! num || !confidence.isFinite || confidence < .7) {
          continue;
        }
        final validation = response['validation'];
        if (validation is Map &&
            (validation['ungrounded'] as List? ?? []).isNotEmpty) {
          continue;
        }
        final calls = response['function_calls'];
        if (calls is! List || calls.length != 1 || calls.single is! Map) {
          continue;
        }
        final call = calls.single as Map;
        final args = call['arguments'];
        if (call['name'] != target.tool ||
            args is! Map ||
            args.length != 1 ||
            !target.values.contains(args['result'])) {
          continue;
        }
        arguments[target.key] = args['result'];
        arguments[target.evidence] = source;
      } catch (_) {
        // Keep the independent field unknown; source-grounded direct facts and
        // other fields remain usable when native inference fails or times out.
      }
    }
    final actions = clauses
        .where(
          (c) => RegExp(
            r'\b(?:need|needs|return|arrange|waiting|awaiting|tomorrow|follow[- ]?up|nothing left)\b',
            caseSensitive: false,
          ).hasMatch(c),
        )
        .toList();
    if (actions.length == 1) arguments['next_action'] = actions.single.trim();
    return {
      'function_calls': [
        {'name': 'record_visit_facts', 'arguments': arguments},
      ],
      'confidence': null,
      'adapter': 'needle3-per-field-source-validated',
    };
  }
}
