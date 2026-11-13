// Versioned, deterministic evaluation. No policy expression executes code.
const closureTemplateId = '40000000-0000-4000-8000-000000000006';
bool closureMatches(
  Map<String, dynamic> expression,
  Map<String, dynamic> values,
) {
  if (expression['all'] case final List children) {
    return children.every(
      (e) => closureMatches(Map<String, dynamic>.from(e as Map), values),
    );
  }
  if (expression['any'] case final List children) {
    return children.any(
      (e) => closureMatches(Map<String, dynamic>.from(e as Map), values),
    );
  }
  final value = values[expression['field']];
  final absent = value == null || value == '';
  return switch (expression['op']) {
    'present' => !absent,
    'missing' => absent,
    'eq' => !absent && value == expression['value'],
    'neq' => !absent && value != expression['value'],
    'in' => !absent && (expression['value'] as List).contains(value),
    _ => false,
  };
}

List<String> closureDependencies(Map<String, dynamic> e) => e['field'] is String
    ? [e['field'] as String]
    : ((e['all'] ?? e['any']) as List)
          .expand(
            (x) => closureDependencies(Map<String, dynamic>.from(x as Map)),
          )
          .toList();
bool closureRequired(
  String id,
  bool required,
  Map<String, dynamic> values,
  Map<String, dynamic>? policy,
) =>
    required &&
    (policy == null ||
        values['claimed_outcome'] != 'hold' ||
        (policy['holdRequired'] as List).contains(id));

class ClosureCheck {
  const ClosureCheck(this.issues, this.recommendation, this.serviceLive);
  final List<String> issues;
  final String recommendation;
  final bool serviceLive;
}

ClosureCheck checkClosure(
  Map<String, dynamic> schema,
  Map<String, dynamic> values,
  List<Map<String, dynamic>> photos,
) {
  final policy = schema['closurePolicy'] as Map<String, dynamic>?;
  if (policy == null) return const ClosureCheck([], 'incomplete', false);
  final fields = (schema['fields'] as List).cast<Map<String, dynamic>>();
  final byId = {for (final f in fields) f['id'] as String: f};
  bool visible(String id, Set<String> seen) {
    if (seen.contains(id)) return false;
    final expression = byId[id]?['activation'] as Map<String, dynamic>?;
    if (expression == null) return true;
    bool test(Map<String, dynamic> e) {
      if (e['all'] is List) {
        return (e['all'] as List).every((x) => test(x as Map<String, dynamic>));
      }
      if (e['any'] is List) {
        return (e['any'] as List).any((x) => test(x as Map<String, dynamic>));
      }
      final parent = e['field'] as String;
      return (!byId.containsKey(parent) || visible(parent, {...seen, id})) &&
          closureMatches(e, values);
    }

    return test(expression);
  }

  final active = fields.where((f) => visible(f['id'] as String, {})).toList();
  values = {
    for (final f in active)
      if (values.containsKey(f['id'])) f['id'] as String: values[f['id']],
  };
  final issues = <String>[];
  if (values['claimed_outcome'] != 'hold' && photos.isEmpty) {
    issues.add('Attach work-order evidence or record an explicit hold.');
  }
  for (final f in active) {
    if (f['activation'] != null &&
        !closureMatches(f['activation'] as Map<String, dynamic>, values)) {
      continue;
    }
    final required = closureRequired(
      f['id'] as String,
      f['required'] as bool,
      values,
      policy,
    );
    if (required && (values[f['id']] == null || values[f['id']] == '')) {
      issues.add('${f['label']} is required.');
    }
    if (required &&
        f['capture'] == 'evidence' &&
        (values[f['id']] != true ||
            !photos.any((p) => p['stage'] == f['evidenceStage']))) {
      issues.add('Attach ${(f['label'] as String).toLowerCase()}.');
    }
  }
  for (final r in policy['rules'] as List) {
    if (closureMatches(r['when'] as Map<String, dynamic>, values) &&
        !closureMatches(r['assert'] as Map<String, dynamic>, values)) {
      issues.add(r['message'] as String);
    }
  }
  var recommendation = 'incomplete';
  for (final d in policy['dispositions'] as List) {
    if (closureMatches(d['when'] as Map<String, dynamic>, values)) {
      recommendation = d['outcome'] as String;
      break;
    }
  }
  if (values['claimed_outcome'] == 'completed' &&
      recommendation != 'completed') {
    issues.add(
      'This visit is not eligible for completed provision. Resolve the branch or select an honest hold, partial or referral outcome.',
    );
  }
  if (values['claimed_outcome'] == 'stage_completed' &&
      !['stage_completed', 'network_ready'].contains(recommendation)) {
    issues.add('This build stage has not met its acceptance checks.');
  }
  if (values['claimed_outcome'] == 'network_ready' &&
      recommendation != 'network_ready') {
    issues.add('Network readiness has not been established.');
  }
  return ClosureCheck(
    issues.toSet().toList(),
    recommendation,
    values['work_stage'] == 'final_provision' &&
        values['claimed_outcome'] == 'completed' &&
        recommendation == 'completed' &&
        values['service_live'] == true &&
        issues.isEmpty,
  );
}
