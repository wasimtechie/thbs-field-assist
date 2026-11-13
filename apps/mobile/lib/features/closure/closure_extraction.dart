import '../../core/contracts.dart';

/// Append exact source text in bounded pages, rather than losing early spoken
/// answers by keeping only the last eight individual turns.
List<String> retainClosureSources(
  List<String> existing,
  List<String> incoming,
) {
  final pages = [...existing];
  for (final source in incoming.where((s) => s.isNotEmpty)) {
    if (pages.any((p) => p.contains(source))) continue;
    for (var at = 0; at < source.length; at += 4000) {
      final part = source.substring(at, (at + 4000).clamp(0, source.length));
      if (pages.isNotEmpty && pages.last.length + part.length + 1 <= 4000) {
        pages[pages.length - 1] = '${pages.last}\n$part';
      } else {
        pages.add(part);
      }
    }
  }
  return pages.reversed.take(8).toList().reversed.toList();
}

/// Keep narrative enrichment bounded. A voice turn targets one missing field;
/// a general narrative proposes at most four additional low-consequence facts.
List<FieldDefinition> closureNarrativeTargets(
  FormDefinition schema,
  Answers values,
  Set<String> alreadyReported,
) => schema
    .visibleFields(values)
    .where(
      (f) =>
          f.voiceEnabled &&
          missing(values[f.id]) &&
          !alreadyReported.contains(f.id) &&
          closureModelMaySuggest(f.id),
    )
    .take(4)
    .toList();

/// Conservative literal facts for the demo and a transparent fallback when the
/// on-device model is unavailable. Every result remains an unverified candidate.
List<Json> literalClosureFacts(
  String transcript, {
  String sourceType = 'text',
}) {
  final results = <String, Json>{};
  void fact(String id, Object value, String span) {
    results[id] = {
      'fieldId': id,
      'value': value,
      'sourceSpan': span,
      'sourceType': sourceType,
      'confidence': null,
      'verificationStatus': 'candidate',
      'ambiguityReason':
          'Literal phrase match; engineer verification required.',
    };
  }

  void match(String id, String pattern, Object Function(RegExpMatch) value) {
    final matches = RegExp(
      pattern,
      caseSensitive: false,
    ).allMatches(transcript).toList();
    if (matches.isEmpty) return;
    final qualified = matches.any((m) {
      final before = transcript.substring(0, m.start);
      final clause = before
          .split(RegExp(r'[.;!?\n]|\b(?:and|but)\b', caseSensitive: false))
          .last;
      return RegExp(
        r"\b(?:not|no|never|didn't|haven't|hasn't|wasn't|unable to|maybe|might|think|not sure|unconfirmed)\b",
        caseSensitive: false,
      ).hasMatch(clause);
    });
    if (qualified) {
      results[id] = {
        'fieldId': id,
        'value': null,
        'sourceSpan': transcript,
        'sourceType': sourceType,
        'confidence': null,
        'verificationStatus': 'candidate',
        'ambiguityReason':
            'Negated or uncertain statement. Ask for an explicit answer; do not infer a value.',
      };
      return;
    }
    final distinct = matches.map(value).toSet();
    if (distinct.length > 1 ||
        results[id] != null && results[id]!['value'] != distinct.first) {
      results[id] = {
        'fieldId': id,
        'value': null,
        'sourceSpan': transcript,
        'sourceType': sourceType,
        'confidence': null,
        'verificationStatus': 'candidate',
        'ambiguityReason':
            'Conflicting facts are present. Ask which result applies; do not guess.',
      };
    } else {
      fact(id, distinct.first, matches.first.group(0)!);
    }
  }

  if (transcript.trim().isNotEmpty) {
    fact('actual_work', transcript.trim(), transcript.trim());
  }
  match(
    'optical_rx_dbm',
    r'(?:optical\s+(?:receive|RX|reading|level)|\bRX|receive)\s*[:=]?\s*(-?\d+(?:\.\d+)?)\s*dBm',
    (m) => num.parse(m.group(1)!),
  );
  match(
    'blockage_distance',
    r'(?:stopped|blocked|obstructed)\s*(?:at\s*)?(\d+(?:\.\d+)?)\s*m\b',
    (m) => num.parse(m.group(1)!),
  );
  match(
    'ont_serial',
    r'\bONT[-_](?:[A-Z0-9]+[-_])*[A-Z0-9]+\b',
    (m) => m.group(0)!,
  );
  match(
    'route_obstructed',
    r'\b(?:duct|route)\s+(?:is\s+|was\s+)?blocked\b',
    (_) => true,
  );
  match('drop_route', r'\bunderground\b', (_) => 'underground');
  match('drop_route', r'\boverhead\b', (_) => 'overhead');
  match(
    'ont_fitted',
    r'\b(?:installed|fitted)\s+(?:an?\s+)?ONT\b',
    (_) => true,
  );
  match(
    'cbt_present',
    r'\b(?:CBT|terminal)\s+(?:is\s+|was\s+)?(?:missing|absent|not found)\b',
    (_) => false,
  );
  match(
    'fibre_connected',
    r'\b(?:external\s+)?fibre\s+(?:is\s+|was\s+)?(?:not connected|incomplete)\b',
    (_) => false,
  );
  match(
    'optical_test',
    r'\boptical\s+test\s+(?:has\s+)?passed\b',
    (_) => 'passed',
  );
  match('optical_test', r'\boptical\s+test\s+failed\b', (_) => 'failed');
  match(
    'operational_test',
    r'\b(?:service|connectivity|activation)\s+test\s+passed\b',
    (_) => 'passed',
  );
  match(
    'service_live',
    r'\b(?:service\s+(?:is\s+)?(?:not\s+active|not\s+live)|customer\s+offline)\b',
    (_) => false,
  );
  match(
    'service_live',
    r'\b(?:service\s+(?:is\s+)?live|customer\s+online)\b',
    (_) => true,
  );
  match(
    'customer_handover',
    r'\bcustomer\s+(?:was\s+)?shown\s+(?:the\s+)?equipment\b',
    (_) => true,
  );
  match(
    'site_handover_safe',
    r'\b(?:site\s+(?:is\s+)?safe|left\s+(?:the\s+)?site\s+safe)\b',
    (_) => true,
  );
  match('civils_required', r'\bcivils\s+(?:is\s+)?required\b', (_) => true);
  match('issue_type', r'\bno\s+(?:optical\s+)?light\b', (_) => 'no_light');
  match(
    'identity_verified',
    r'\b(?:work order and premises|premises and work order)\s+identity\s+verified\b',
    (_) => true,
  );
  match(
    'access_permission',
    r'\baccess\s+(?:was\s+)?(?:obtained|granted|confirmed)\b',
    (_) => true,
  );
  match(
    'drilling_consent',
    r'\b(?:drilling|new entry)\s+consent\s+(?:was\s+)?(?:granted|obtained)\b',
    (_) => true,
  );
  match(
    'drilling_consent',
    r'\b(?:drilling|new entry)\s+consent\s+(?:was\s+)?(?:refused|not granted)\b',
    (_) => false,
  );
  match('safety_hazard', r'\bno\s+(?:safety\s+)?hazards?\b', (_) => false);
  match(
    'safety_hazard',
    r'\b(?:unmitigated hazard|hazard identified|safety incident)\b',
    (_) => true,
  );
  match('hazard_mitigated', r'\bhazard\s+(?:was\s+)?mitigated\b', (_) => true);
  match('hazard_mitigated', r'\bunmitigated hazard\b', (_) => false);
  match(
    'wayleave_granted',
    r'\bwayleave\s+(?:was\s+)?(?:granted|approved)\b',
    (_) => true,
  );
  match(
    'wayleave_granted',
    r'\bwayleave\s+(?:was\s+)?(?:denied|not granted)\b',
    (_) => false,
  );
  // No thresholds, safety clearance, identity or permission are inferred.

  return results.values.toList();
}

// High-consequence facts need explicit literal evidence or engineer input.
// Model confidence alone cannot create measurements, consent or acceptance.
bool closureModelMaySuggest(String id) => !const {
  'scenario',
  'work_stage',
  'identity_verified',
  'access_permission',
  'drilling_consent',
  'location_agreed',
  'optical_rx_dbm',
  'blockage_distance',
  'route_distance',
  'optical_test',
  'operational_test',
  'service_live',
  'safety_hazard',
  'hazard_mitigated',
  'site_handover_safe',
  'alternative_authorised',
  'wayleave_granted',
  'design_accepted',
  'downstream_handoff',
  'reinstatement_accepted',
  'all_network_stages_accepted',
  'premises_ready',
  'cbt_safe_access',
  'safe_attempt',
  'fibre_connected',
  'external_connection',
  'internal_fibre',
  'ont_fitted',
  'ont_status_checked',
  'civils_to_design',
  'splice_tests_accepted',
  'as_built_accepted',
  'terminal_available_mapped',
  'evidence_sufficient',
  'installation_evidence',
  'asset_evidence',
  'test_evidence',
  'diagnostic_evidence',
  'build_evidence',
  'blocker_evidence',
}.contains(id);
