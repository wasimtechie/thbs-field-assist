import 'dart:convert';
import 'package:field_voice/field_voice.dart';
import '../../core/contracts.dart';

/// Application-owned adaptation to Needle's verified flat tool-call format.
/// One field per call avoids nested optional extraction objects, which failed
/// on the pinned model. The same single Needle model processes every field.
Future<Json> extractFormFields(
  FieldExtractor engine,
  FormDefinition schema,
  String transcript, {
  String question = '',
  Answers knownValues = const {},
  String? focusedFieldId,
}) async {
  final normalized = normalizeExplicitCorrection(transcript);
  final updates = <String, dynamic>{};
  final unresolved = <String>[];
  double? minimumConfidence;
  if (RegExp(
    r'\b(clear|remove)\b',
    caseSensitive: false,
  ).hasMatch(transcript)) {
    final result = await engine.extract(
      transcript,
      [
        {
          'name': 'clear_field',
          'description': 'Clear a report field only when explicitly requested.',
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
      ],
      'Identify only the explicitly named field to clear. Return no call when ambiguous.',
    );
    if (((result['confidence'] as num?) ?? 0) >= .7) {
      return result;
    }
    return {'confidence': null, 'function_calls': <Json>[]};
  }
  for (final field in schema.fields.where(
    (f) => f.voiceEnabled && (focusedFieldId == null || f.id == focusedFieldId),
  )) {
    final properties = <String, dynamic>{};
    switch (field.kind) {
      case FieldKind.quantity:
        properties.addAll({
          'amount': {'type': 'number', 'description': field.description},
        });
      case FieldKind.boolean:
        properties['value'] = {'type': 'boolean'};
      case FieldKind.integer:
        properties['value'] = {'type': 'integer'};
      case FieldKind.decimal:
        properties['value'] = {'type': 'number'};
      case FieldKind.singleSelect:
        properties['result'] = {
          'type': 'string',
          'enum': field.options.map((o) => o.id).toList(),
        };
      default:
        properties['value'] = {
          'type': 'string',
          'description': field.description,
        };
    }
    final tool = {
      'name': 'record_${field.id}',
      'description': 'Record the ${field.label.toLowerCase()}.',
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': properties.keys.toList(),
      },
    };
    var input = normalized;
    if (field.kind == FieldKind.singleSelect) {
      final mentioned = field.options
          .where(
            (o) => RegExp(
              '\\b${RegExp.escape(o.label.toLowerCase())}\\b',
            ).hasMatch(normalized.toLowerCase()),
          )
          .toList();
      if (mentioned.length == 1) {
        final option = mentioned.single;
        final sameMeaning = schema.fields
            .where(
              (f) =>
                  f.voiceEnabled &&
                  f.kind == FieldKind.singleSelect &&
                  f.options.any(
                    (o) => o.label.toLowerCase() == option.label.toLowerCase(),
                  ),
            )
            .toList();
        if (sameMeaning.length == 1) {
          input = 'The ${field.label.toLowerCase()} is ${option.id}.';
        }
      }
    }
    final result = await engine.extract(
      input,
      [tool],
      'Extract only explicitly stated engineer report values. Preserve corrections and negation.${question.isEmpty ? '' : ' Current question: $question.'}${knownValues.containsKey(field.id) ? ' Known value: ${jsonEncode(knownValues[field.id]?.toJson())}. Change it only for an explicit correction.' : ''}',
    );
    final confidence = (result['confidence'] as num?)?.toDouble() ?? 0;
    final calls = result['function_calls'] as List? ?? [];
    final ungrounded =
        ((result['validation'] as Json?)?['ungrounded'] as List?) ?? [];
    for (final raw in calls) {
      final call = raw as Json;
      if (call['name'] != tool['name']) continue;
      final args = call['arguments'] as Json;
      if (confidence < .7 || ungrounded.isNotEmpty) {
        unresolved.add(field.id);
        continue;
      }
      Object? value;
      if (field.kind == FieldKind.quantity) {
        final unit = explicitUnit(field, normalized, question);
        if (unit == null) {
          unresolved.add(field.id);
          continue;
        }
        value = {'amount': args['amount'], 'unit': unit};
      } else {
        value = args[field.kind == FieldKind.singleSelect ? 'result' : 'value'];
      }
      if (value != null) {
        updates[field.id] = value;
        minimumConfidence = minimumConfidence == null
            ? confidence
            : (minimumConfidence < confidence ? minimumConfidence : confidence);
      }
    }
  }
  return {
    'confidence': minimumConfidence,
    'function_calls': [
      {'name': 'record_fields', 'arguments': updates},
    ],
    'applicationUnresolved': unresolved,
    'adapter': 'per-field-verified-tool-format',
  };
}

String normalizeExplicitCorrection(String transcript) {
  // Keep correction parsing deliberately narrow: one explicit numeric correction
  // with a spoken unit. Unclear alternatives remain unchanged for clarification.
  const words =
      'zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred';
  final number = '(?:-?\\d+(?:\\.\\d+)?|(?:$words)(?:[ -](?:$words))*)';
  final pattern = RegExp(
    '($number)\\s+(metres?|meters?|m|Mbps|Gbps)\\s*[,;]?\\s*(?:actually|make that|correction)\\s+($number)\\b',
    caseSensitive: false,
  );
  return transcript.replaceAllMapped(pattern, (m) => '${m[3]} ${m[2]}');
}

const voiceUnitAliases = {
  'm': ['m', 'metre', 'metres', 'meter', 'meters'],
  'km': ['km', 'kilometre', 'kilometres', 'kilometer', 'kilometers'],
  'Mbps': ['Mbps', 'megabits per second'],
  'Gbps': ['Gbps', 'gigabits per second'],
};
String? explicitUnit(FieldDefinition field, String text, String question) {
  const aliases = voiceUnitAliases;
  final mentioned = field.units
      .where(
        (u) => (aliases[u] ?? [u]).any(
          (word) => RegExp(
            '\\b${RegExp.escape(word)}\\b',
            caseSensitive: false,
          ).hasMatch(text),
        ),
      )
      .toList();
  if (mentioned.length == 1) return mentioned.single;
  if (mentioned.isEmpty && question == field.question) {
    final established = field.units
        .where(
          (u) => (aliases[u] ?? [u]).any(
            (word) => RegExp(
              '\\b${RegExp.escape(word)}\\b',
              caseSensitive: false,
            ).hasMatch(question),
          ),
        )
        .toList();
    if (established.length == 1) return established.single;
  }
  return null;
}
