import '../../core/contracts.dart';

const provisionNarrativeFieldIds = {
  'access_permission',
  'location_agreed',
  'drop_route',
  'external_connection',
  'internal_fibre',
  'ont_fitted',
  'ont_status_checked',
  'service_live',
  'customer_handover',
  'site_handover_safe',
};

// Match domain words in their field context, without rewriting the engineer's
// transcript or changing identifiers. OND is a known ONT decode in this visit.
RegExp _provisionPattern(String pattern, {bool verbForms = false}) {
  var expanded = pattern.replaceAll(
    'ONT',
    r'(?:ONT|OND|O[\s.]*N[\s.]*(?:T|D))',
  );
  if (verbForms) {
    for (final entry in const {
      'approved': r'approv(?:e|ed|es)',
      'installed': r'install(?:ed|s)?',
      'fitted': r'fit(?:ted|s)?',
      'connected': r'connect(?:ed|s)?',
      'checked': r'check(?:ed|s)?',
      'verified': r'verif(?:ied|y|ies)',
      'completed': r'complet(?:ed|e|es)',
      'showed': r'show(?:ed|s)?',
    }.entries) {
      expanded = expanded.replaceAll(entry.key, entry.value);
    }
  }
  // ASR sometimes inserts a comma/full stop between a subject and its verb.
  return RegExp(expanded.replaceAll(r'\s+', r'[\s.,:]+'), caseSensitive: false);
}

/// Literal, on-device S1 facts. A completed installation never implies consent,
/// live service, a handover or a safety check. Each value needs spoken evidence.
List<Json> provisionNarrativeFacts(FormDefinition form, String text) {
  final enabled = form.fields.map((f) => f.id).toSet();
  final results = <String, Json>{};
  void record(String id, Object? value, String span) {
    if (!enabled.contains(id)) return;
    final previous = results[id];
    if (previous != null && previous['value'] != value) value = null;
    results[id] = {
      'fieldId': id,
      'value': value,
      'sourceSpan': previous == null ? span : text,
      'sourceType': 'speech',
      'verificationStatus': 'candidate',
      'confidence': null,
      if (value == null)
        'ambiguityReason':
            'Uncertain or conflicting statement; ask the engineer.',
    };
  }

  // Do not split decimal readings. Separate contrasting clauses so a negative
  // answer for one check cannot negate a different, explicitly stated fact.
  final clauses = text.split(
    RegExp(
      r'(?<!\d)\.(?!\d|\s*(?:n[\s.]*[td]\b|[td]\b|approv(?:e|ed|es)|agree(?:d|s)?|install(?:ed|s)?|fit(?:ted|s)?|is|was|were|has|have|and\s+tidy|tidy)\b)\s*|[;!?\n]+|\bbut\b',
      caseSensitive: false,
    ),
  );
  for (final raw in clauses) {
    final clause = raw.trim();
    if (clause.isEmpty) continue;
    final uncertain = RegExp(
      r"\b(?:maybe|might|probably|possibly|think|not sure|unconfirmed|not confirmed)\b",
      caseSensitive: false,
    ).hasMatch(clause);
    void flag(String id, String positive, String negative) {
      if (!enabled.contains(id)) return;
      final negatives = _provisionPattern(negative).allMatches(clause).toList();
      final positives = _provisionPattern(positive, verbForms: true)
          .allMatches(clause)
          .where(
            (p) => !negatives.any((n) => p.start < n.end && p.end > n.start),
          )
          .toList();
      for (final n in negatives) {
        record(id, uncertain ? null : false, n.group(0)!);
      }
      for (final p in positives) {
        final before = clause
            .substring(0, p.start)
            .split(RegExp(r'\b(?:and|then|but)\b|[,;]', caseSensitive: false))
            .last;
        // Unhandled negation stays unknown; it must not turn into a yes.
        final negated = RegExp(
          r"\b(?:not|never|didn't|don't|haven't|hasn't|wasn't|without)\b",
          caseSensitive: false,
        ).hasMatch(before);
        final planned = RegExp(
          r"\b(?:will|would|shall|should|must|need(?:s)? to|plan(?:ning)? to|going to|intend to|please|want(?:s)? to)\b|\b(?:i|we|they|he|she)['’]ll\b",
          caseSensitive: false,
        ).hasMatch(before);
        final question = RegExp(
          r'^\s*(?:can|could|would|will|did|does|do|should|has|have|is|are)\b',
          caseSensitive: false,
        ).hasMatch(clause);
        record(
          id,
          uncertain || negated || planned || question ? null : true,
          negated || uncertain || planned || question ? clause : p.group(0)!,
        );
      }
    }

    flag(
      'access_permission',
      r'\b(?:customer\s+(?:has\s+|had\s+)?(?:granted|gave|confirmed|allowed)\s+(?:me\s+|us\s+)?access|access\s+(?:was\s+|has been\s+)?(?:granted|obtained|confirmed|permitted)|(?:obtained|received)\s+(?:(?:customer\s+)?access\s+permission|customer\s+permission))\b',
      r'\b(?:customer\s+(?:has\s+|had\s+)?(?:refused|denied)\s+access|(?:no|without)\s+(?:customer\s+)?(?:access\s+)?permission|access\s+(?:was\s+)?(?:refused|denied|not granted|not obtained)|permission\s+(?:was\s+)?(?:refused|denied|not obtained))\b',
    );
    flag(
      'location_agreed',
      r'\b(?:customer\s+(?:has\s+|had\s+)?(?:approved|agreed\s+(?:to\s+|on\s+)?)\s*(?:the\s+)?(?:cable\s+and\s+)?ONT\s+location|(?:ONT|cable and ONT)\s+location\s+(?:was\s+|has been\s+)?(?:approved|agreed)\s+(?:by|with)\s+the\s+customer)\b',
      r"\b(?:customer\s+(?:(?:has\s+)?not|did not|didn't|refused to)\s+approv(?:e|ed)\s+(?:the\s+)?ONT\s+location|ONT\s+location\s+(?:was\s+)?(?:not approved|not agreed|rejected))\b",
    );
    flag(
      'external_connection',
      r'\b(?:(?:installed|fitted|completed)\s+(?:the\s+)?external\s+fib(?:re|er)\s+and\s+(?:the\s+)?connection\s+point|external\s+fib(?:re|er)\s+and\s+(?:the\s+)?connection\s+point\s+(?:was\s+|were\s+|is\s+|are\s+|has been\s+|have been\s+)?(?:installed|fitted|completed))\b',
      r"\b(?:(?:did not|didn't|could not|couldn't)\s+(?:install|fit|complete)\s+(?:the\s+)?external\s+fib(?:re|er)|external\s+fib(?:re|er)(?:\s+and\s+(?:the\s+)?connection\s+point)?\s+(?:was\s+|is\s+)?(?:not installed|not fitted|incomplete|not completed))\b",
    );
    flag(
      'internal_fibre',
      r'\b(?:(?:fitted|installed|connected)\s+(?:the\s+)?internal\s+fib(?:re|er)\s+to\s+(?:the\s+)?ONT|internal\s+fib(?:re|er)\s+(?:was\s+|is\s+|has been\s+)?(?:fitted|installed|connected)\s+to\s+(?:the\s+)?ONT)\b',
      r"\b(?:(?:did not|didn't|could not|couldn't)\s+(?:fit|install|connect)\s+(?:the\s+)?internal\s+fib(?:re|er)|internal\s+fib(?:re|er)\s+(?:was\s+|is\s+)?(?:not fitted|not installed|not connected))\b",
    );
    flag(
      'ont_fitted',
      r'\b(?:(?:installed|fitted)\s+(?:(?:an?|the)\s+)?ONT|ONT\s+(?:was\s+|is\s+|has been\s+)?(?:installed|fitted))\b',
      r"\b(?:(?:did not|didn't|could not|couldn't)\s+(?:install|fit)\s+(?:(?:an?|the)\s+)?ONT|ONT\s+(?:was\s+|is\s+)?(?:not installed|not fitted))\b",
    );
    flag(
      'ont_status_checked',
      r'\b(?:(?:checked|verified)\s+(?:the\s+)?ONT\s+(?:power\s+and\s+status|status\s+and\s+power)|ONT\s+(?:power\s+and\s+status|status\s+and\s+power)\s+(?:was\s+|were\s+|has been\s+)?(?:checked|verified))\b',
      r"\b(?:(?:did not|didn't|have not|haven't)\s+(?:check|verify)\s+(?:the\s+)?ONT\s+(?:power|status)|ONT\s+(?:power\s+and\s+status|status\s+and\s+power)\s+(?:was\s+|were\s+)?not\s+(?:checked|verified))\b",
    );
    flag(
      'service_live',
      r'\b(?:service\s+(?:is\s+|was\s+|is now\s+|was now\s+)?(?:live|active)|customer\s+(?:is\s+|was\s+|is now\s+)?online)\b',
      r'\b(?:service\s+(?:is\s+|was\s+)?(?:not live|not active|inactive)|customer\s+(?:is\s+|was\s+)?(?:not online|offline))\b',
    );
    flag(
      'customer_handover',
      r'\b(?:(?:showed|shown)\s+(?:the\s+)?customer\s+(?:the\s+)?equipment|customer\s+(?:was\s+|has been\s+)?shown\s+(?:the\s+)?equipment|customer\s+handover\s+(?:was\s+|is\s+)?completed)\b',
      r"\b(?:(?:did not|didn't|have not|haven't)\s+show\s+(?:the\s+)?customer\s+(?:the\s+)?equipment|customer\s+(?:was\s+|has\s+)?not\s+(?:been\s+)?shown\s+(?:the\s+)?equipment|customer\s+handover\s+(?:was\s+|is\s+)?(?:not completed|incomplete))\b",
    );
    flag(
      'site_handover_safe',
      r'\b(?:(?:left|leaving)\s+(?:the\s+)?site\s+safe\s+and\s+tidy|site\s+(?:is\s+|was\s+|has been left\s+|was left\s+)?safe\s+and\s+tidy)\b',
      r'\b(?:site\s+(?:is\s+|was\s+|was left\s+)?(?:not safe|unsafe|not tidy)|(?:did not|could not)\s+leave\s+(?:the\s+)?site\s+safe\s+and\s+tidy)\b',
    );

    final routePatterns = {
      'existing': r'\bexisting\s+(?:duct|fib(?:re|er)\s+route|route)\b',
      'underground': r'\bunderground\s+(?:duct|fib(?:re|er)\s+route|route)\b',
      'overhead': r'\boverhead\s+(?:cable|fib(?:re|er)\s+route|route)\b',
    };
    for (final route in routePatterns.entries) {
      final match = RegExp(
        route.value,
        caseSensitive: false,
      ).firstMatch(clause);
      if (match == null) continue;
      final before = clause.substring(0, match.start);
      final qualified =
          uncertain ||
          RegExp(
            r"\b(?:not|never|didn't|couldn't|instead of|rather than)\b",
            caseSensitive: false,
          ).hasMatch(before);
      record('drop_route', qualified ? null : route.key, clause);
    }
  }
  return results.values.toList();
}
