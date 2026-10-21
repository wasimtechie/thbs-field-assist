import 'dart:convert';
import '../../core/contracts.dart';

class PatchResult {
  const PatchResult(this.values, this.changed, this.unresolved);
  final Answers values;
  final List<String> changed, unresolved;
}

List<Json> compileTools(FormDefinition schema) => [
  {
    'name': 'record_fields',
    'description':
        'Record only explicitly stated engineer report values. Unmentioned fields MUST be omitted. Preserve negation and use the last explicit correction. Never infer completed or passed.',
    'parameters': {
      'type': 'object',
      'properties': {
        for (final f in schema.fields.where((f) => f.voiceEnabled))
          f.id: _parameter(f),
      },
      'required': <String>[],
    },
  },
  {
    'name': 'clear_field',
    'description':
        'Clear one field only when the engineer explicitly asks to clear or remove its value.',
    'parameters': {
      'type': 'object',
      'properties': {
        'fieldId': {
          'type': 'string',
          'enum': schema.fields
              .where((f) => f.voiceEnabled)
              .map((f) => f.id)
              .toList(),
        },
      },
      'required': ['fieldId'],
    },
  },
];
Json _parameter(FieldDefinition f) => {
  'description': '${f.description} ${f.question}',
  ...switch (f.kind) {
    FieldKind.boolean => {'type': 'boolean'},
    FieldKind.integer => {'type': 'integer'},
    FieldKind.decimal => {'type': 'number'},
    FieldKind.quantity => {
      'type': 'object',
      'properties': {
        'amount': {'type': 'number'},
        'unit': {'type': 'string', 'enum': f.units},
      },
      'required': ['amount', 'unit'],
    },
    FieldKind.singleSelect => {
      'type': 'string',
      'enum': f.options.map((o) => o.id).toList(),
    },
    _ => {'type': 'string'},
  },
  if (f.constraints['min'] != null && f.kind != FieldKind.quantity)
    'minimum': f.constraints['min'],
  if (f.constraints['max'] != null && f.kind != FieldKind.quantity)
    'maximum': f.constraints['max'],
};
PatchResult mergeExtraction(
  FormDefinition schema,
  Answers previous,
  Json output,
  String transcript, {
  Set<String> manualFields = const {},
}) {
  final values = <String, Answer?>{...previous},
      changed = <String>[],
      unresolved = ((output['applicationUnresolved'] as List?) ?? const [])
          .cast<String>()
          .toList();
  final confidence = (output['confidence'] as num?)?.toDouble();
  if (confidence == null || confidence < .7) {
    return PatchResult(previous, [], unresolved);
  }
  final ungrounded =
      ((output['validation'] as Json?)?['ungrounded'] as List?)
          ?.cast<String>() ??
      [];
  final calls = output['function_calls'] as List? ?? [];
  final text = transcript.toLowerCase();
  final explicitCorrection = RegExp(
    r'\b(actually|change|correct|correction|instead|make that)\b',
  ).hasMatch(text);
  for (final raw in calls) {
    if (raw is! Json) throw const FormatException('Malformed model call');
    final args = raw['arguments'];
    if (args is! Json) throw const FormatException('Malformed model arguments');
    final entries = raw['name'] == 'record_fields'
        ? args.entries
        : raw['name'] == 'clear_field' && args['fieldId'] is String
        ? <MapEntry<String, dynamic>>[MapEntry(args['fieldId'] as String, null)]
        : <MapEntry<String, dynamic>>[];
    for (final entry in entries) {
      final field = schema.fields
          .where((f) => f.id == entry.key && f.voiceEnabled)
          .firstOrNull;
      if (field == null) {
        throw const FormatException(
          'Model proposed an unknown or non-voice field',
        );
      }
      final id = field.id;
      if (ungrounded.any((u) => u.endsWith('.$id'))) {
        unresolved.add(id);
        continue;
      }
      if (entry.value == null &&
          !RegExp(r'\b(clear|remove|delete)\b').hasMatch(text)) {
        unresolved.add(id);
        continue;
      }
      if (RegExp(r'\b\w+\s+or\s+\w+\b').hasMatch(text) &&
          [
            FieldKind.quantity,
            FieldKind.integer,
            FieldKind.decimal,
          ].contains(field.kind)) {
        unresolved.add(id);
        continue;
      }
      if (text.contains('not tested') && entry.value == 'passed' ||
          RegExp(r'\b(did not|didn.t|not) replace').hasMatch(text) &&
              field.kind == FieldKind.quantity) {
        unresolved.add(id);
        continue;
      }
      Answer? answer;
      try {
        answer = Answer.decode(entry.value);
      } catch (_) {
        unresolved.add(id);
        continue;
      }
      final candidate = {...values, id: answer};
      final validation = validate(schema, candidate, requireComplete: false);
      if (validation.issues.any((i) => i.fieldId == id)) {
        unresolved.add(id);
        continue;
      }
      final different =
          jsonEncode(previous[id]?.toJson()) != jsonEncode(answer?.toJson());
      if (different &&
          !missing(previous[id]) &&
          manualFields.contains(id) &&
          !explicitCorrection) {
        unresolved.add(id);
        continue;
      }
      if (different) {
        values[id] = answer;
        changed.add(id);
      }
    }
  }
  return PatchResult(
    Map.unmodifiable(values),
    List.unmodifiable(changed.toSet()),
    List.unmodifiable(unresolved.toSet()),
  );
}

FieldDefinition? nextQuestion(
  FormDefinition schema,
  Answers values,
  List<String> unresolved,
  Map<String, int> attempts, {
  Set<String> skipped = const {},
}) {
  for (final id in unresolved) {
    final field = schema.fields
        .where((f) => f.id == id && f.voiceEnabled && schema.visible(f, values))
        .firstOrNull;
    if (field != null && !skipped.contains(id) && (attempts[id] ?? 0) < 2) {
      return field;
    }
  }
  final issues = validate(schema, values).issues;
  for (final field in schema.visibleFields(values)) {
    if (field.voiceEnabled &&
        issues.any((i) => i.fieldId == field.id) &&
        !skipped.contains(field.id) &&
        (attempts[field.id] ?? 0) < 2) {
      return field;
    }
  }
  for (final field in schema.visibleFields(values)) {
    if (field.voiceEnabled &&
        missing(values[field.id]) &&
        !skipped.contains(field.id) &&
        (attempts[field.id] ?? 0) < 2) {
      return field;
    }
  }
  return null;
}
