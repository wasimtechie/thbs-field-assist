import '../../core/contracts.dart';
import 'closure_extraction.dart';
import 'optical_reading.dart';
import 'provision_narrative.dart';
import '../voice/asset_reference.dart';
import '../voice/speech_repair.dart';

/// Grounded, local mapping for the short visit summary. Every accepted value keeps
/// its exact spoken source. Measurements and results are never inferred from
/// installation progress, and contradictory clauses remain unanswered.
List<Json> compactNarrativeFacts(FormDefinition form, String raw) {
  final interpretation = interpretSpokenRepairs(raw);
  final text = interpretation.text;
  final found = <String, Json>{};
  final ambiguous = <String>{};
  void unresolved(String id) {
    found[id] = {
      'fieldId': id,
      'value': null,
      'sourceSpan': text,
      'sourceType': 'speech',
      'verificationStatus': 'candidate',
      'confidence': null,
      'ambiguityReason':
          'Uncertain or conflicting statement; ask the engineer.',
    };
    ambiguous.add(id);
  }

  void add(String id, Object value, String source) {
    if (ambiguous.contains(id)) return;
    final previous = found[id];
    if (previous != null && previous['value'] != value) {
      found[id] = {
        ...previous,
        'value': null,
        'sourceSpan': text,
        'ambiguityReason': 'Conflicting statements; ask the engineer.',
      };
      ambiguous.add(id);
      return;
    }
    found[id] = {
      'fieldId': id,
      'value': value,
      'sourceSpan': source,
      'sourceType': 'speech',
      'verificationStatus': 'candidate',
      'confidence': null,
    };
  }

  for (final fact in literalClosureFacts(text, sourceType: 'speech')) {
    // The measurement parser below also checks transmit/target context. Do
    // not retain a legacy literal reading that bypasses those checks.
    if (fact['fieldId'] != 'optical_rx_dbm' &&
        !provisionNarrativeFieldIds.contains(fact['fieldId']) &&
        form.fields.any((f) => f.id == fact['fieldId'])) {
      found[fact['fieldId'] as String] = fact;
      if (fact['value'] == null) ambiguous.add(fact['fieldId'] as String);
    }
  }
  for (final fact in provisionNarrativeFacts(form, text)) {
    final id = fact['fieldId'] as String;
    found[id] = fact;
    if (fact['value'] == null) ambiguous.add(id);
  }
  if (form.fields.any((f) => f.id == 'optical_rx_dbm')) {
    for (final fact in opticalNarrativeFacts(
      text,
      allowUnitless:
          form.fields
              .where(
                (f) => [
                  FieldKind.decimal,
                  FieldKind.integer,
                  FieldKind.quantity,
                ].contains(f.kind),
              )
              .length ==
          1,
    )) {
      final value = fact['value'];
      if (value == null) {
        unresolved('optical_rx_dbm');
      } else {
        add('optical_rx_dbm', value, fact['sourceSpan'] as String);
        if (found['optical_rx_dbm']?['value'] == value) {
          found['optical_rx_dbm'] = {...found['optical_rx_dbm']!, ...fact};
        }
      }
    }
  }
  // Split sentences without breaking decimal measurements or asset references.
  final clauses = text.split(
    RegExp(
      r'(?<!\d)\.(?!\s*(?:is|was|has|have|are|were)\b)\s*|[;!?]\s*|\n+|\.(?=\s+[A-Z])',
    ),
  );
  for (final raw in clauses) {
    final clause = raw.trim();
    if (clause.isEmpty) continue;
    // Keep the original span for review, while tolerating an ASR full stop
    // between a subject and its auxiliary (for example, "The job. is done").
    final lower = clause.toLowerCase().replaceAll(RegExp(r'[.,]\s*'), ' ');
    final uncertain = RegExp(
      r"\b(?:maybe|might|not sure|not confirmed|unconfirmed|think|possibly)\b",
    ).hasMatch(lower);
    if (RegExp(r'\b(?:work|job|installation|visit)\b').hasMatch(lower) &&
        RegExp(
          r"\b(?:not|never|haven't|didn't|couldn't)\b.*\b(?:completed|complete|finished)\b",
        ).hasMatch(lower)) {
      unresolved('claimed_outcome');
    }
    if (RegExp(
          r'\b(?:service|connectivity|activation|operational)\s+(?:tests?|checks?)\b',
        ).hasMatch(lower) &&
        (uncertain ||
            RegExp(
              r"\b(?:not\s+(?:passed|past|successful)|(?:did not|didn't|has not|hasn't)\s+(?:pass(?:ed)?|past))\b",
            ).hasMatch(lower))) {
      unresolved('operational_test');
    }
    if (uncertain &&
        RegExp(
          r'\b(?:work|job|installation|visit)\b.*\b(?:completed|complete|finished|blocked)\b',
        ).hasMatch(lower)) {
      unresolved('claimed_outcome');
    }
    if (uncertain && RegExp(r'\b(?:optical|receive|rx)\b').hasMatch(lower)) {
      unresolved('optical_rx_dbm');
    }
    if (uncertain) continue;
    // In an explicit asset clause, tolerate the known ASR spellings while
    // retaining its original source. A bare asset type never supplies an ID.
    final assetClause = spokenAssetReference(clause, allowHomophones: false);
    if (assetClause != null &&
        !RegExp(r'\b(?:wrong|not|unknown|unconfirmed)\b').hasMatch(lower)) {
      add('serving_asset', assetClause, clause);
    }
    // Preserve identifiers as spoken; do not fill the asset from job context.
    final assets = RegExp(
      r'\b(?:CBT|DP|POL|POLE|CH|CHAMBER|CSP|CAB)[-_][A-Z0-9]+(?:[-_][A-Z0-9]+)*\b',
      caseSensitive: false,
    ).allMatches(clause);
    for (final asset in assets) {
      if (!RegExp(r'\b(?:wrong|not|unknown|unconfirmed)\b').hasMatch(lower)) {
        final reference = spokenAssetReference(asset.group(0)!);
        if (reference != null) add('serving_asset', reference, asset.group(0)!);
      }
    }
    final outcomes = <String, String>{
      'partial':
          r'\b(?:work|job|installation|visit)\s+(?:is |was |has been )?(?:partially|partly) (?:completed|complete|done)\b',
      'blocked':
          r'\b(?:work|job|installation|visit|duct|route)\s+(?:is |was |remains )?blocked\b',
      'hold': r'\b(?:work|job|installation|visit)\s+(?:is |was )?on hold\b',
      'referred':
          r'\b(?:referral|follow-on)\s+(?:is |was )?(?:required|raised)\b',
      'completed':
          r'\b(?:(?:work|job|installation|visit)\s+(?:is |was |has been )?(?:fully )?(?:completed|complete|finished)|(?:completed|finished) (?:all (?:of )?)?(?:the |this )?(?:work|job|installation|visit))\b',
    };
    for (final entry in outcomes.entries) {
      if (RegExp(entry.value).hasMatch(lower) &&
          !RegExp(
            r"\b(?:not|never|haven't|didn't|couldn't|unable)\b",
          ).hasMatch(lower)) {
        add('claimed_outcome', entry.key, clause);
      }
    }
    for (final result in RegExp(
      r'\b(?:service|connectivity|activation|operational)\s+(?:tests?|checks?)\s+(?:has |have |is |was |were )?(passed|past|successful|failed)\b',
      caseSensitive: false,
    ).allMatches(clause)) {
      if (!RegExp(r"\b(?:not|never|didn't|haven't)\b").hasMatch(lower)) {
        add(
          'operational_test',
          result.group(1)!.toLowerCase() == 'failed' ? 'failed' : 'passed',
          result.group(0)!,
        );
      }
    }
    if (RegExp(
      r'\b(?:no (?:further work|follow[- ]?up|further action)|nothing (?:else )?(?:required|outstanding)|(?:follow[- ]?up|next action)\s*(?:is |:)|civils (?:is )?required|revisit (?:is )?required|refer (?:to|the)|return (?:to|visit))\b',
    ).hasMatch(lower)) {
      final start = RegExp(
        r'\b(?:no (?:further work|follow[- ]?up|further action)|nothing (?:else )?(?:required|outstanding)|follow[- ]?up|next action|civils|revisit|refer|return)\b',
        caseSensitive: false,
      ).firstMatch(clause)!.start;
      final action = clause.substring(start);
      add('next_action', action, action);
    }
  }
  return found.values
      .where((fact) => form.fields.any((field) => field.id == fact['fieldId']))
      .map(interpretation.ground)
      .toList();
}
