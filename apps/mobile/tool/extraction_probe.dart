import 'dart:convert';
import 'dart:io';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/patch_rules.dart';
import 'package:field_assist/features/voice/field_extraction.dart';

Future<void> main(List<String> args) async {
  final engine = FieldVoice();
  await engine.load(args.first);
  final form = FormDefinition.fromJson(
    jsonDecode(File('../../fixtures/templates/repair.json').readAsStringSync())
        as Json,
  );
  final probes = <({String name, List<Json> tools, String text})>[
    (
      name: 'simple control',
      tools: [
        {
          'name': 'record_access',
          'description': 'Record site access status.',
          'parameters': {
            'type': 'object',
            'properties': {
              'status': {
                'type': 'string',
                'enum': ['available', 'restricted', 'unavailable'],
              },
            },
            'required': ['status'],
          },
        },
      ],
      text: 'Site access is available.',
    ),
    (
      name: 'field-specific tool',
      tools: [
        {
          'name': 'record_cable_replaced',
          'description':
              'Record how many metres of cable the engineer replaced.',
          'parameters': {
            'type': 'object',
            'properties': {
              'amount': {
                'type': 'number',
                'description': 'Metres of cable actually replaced',
              },
            },
            'required': ['amount'],
          },
        },
      ],
      text: 'Replaced twenty metres actually twelve.',
    ),
    (
      name: 'two explicit tools',
      tools: [
        {
          'name': 'record_cable_replaced',
          'description': 'Record the metres of cable replaced.',
          'parameters': {
            'type': 'object',
            'properties': {
              'amount': {'type': 'number'},
            },
            'required': ['amount'],
          },
        },
        {
          'name': 'record_line_test',
          'description': 'Record the line test result.',
          'parameters': {
            'type': 'object',
            'properties': {
              'result': {
                'type': 'string',
                'enum': ['passed', 'failed', 'not_tested'],
              },
            },
            'required': ['result'],
          },
        },
      ],
      text:
          'Replaced twenty metres actually twelve. I have not tested the line.',
    ),
    (
      name: 'full form',
      tools: compileTools(form),
      text:
          'Replaced twenty metres actually twelve. I have not tested the line.',
    ),
    (
      name: 'normalized measurement',
      tools: [
        {
          'name': 'record_cable_replaced',
          'description': 'Record the length of cable replaced in metres.',
          'parameters': {
            'type': 'object',
            'properties': {
              'amount': {'type': 'number'},
            },
            'required': ['amount'],
          },
        },
      ],
      text: 'Replaced twelve metres.',
    ),
    (
      name: 'enum-focused extraction',
      tools: [
        {
          'name': 'record_line_test',
          'description':
              'Extract the line test result from the engineer report.',
          'parameters': {
            'type': 'object',
            'properties': {
              'line_test': {
                'type': 'string',
                'description':
                    'not_tested means the line has not been tested. passed means explicitly tested and passed. failed means explicitly tested and failed.',
                'enum': ['passed', 'failed', 'not_tested'],
              },
            },
            'required': ['line_test'],
          },
        },
      ],
      text: 'I have not tested the line.',
    ),
    (
      name: 'full form simple speech',
      tools: compileTools(form),
      text:
          'Fault location is cabinet. Cable replaced is twelve metres. Line test result is not tested. Service restored is no. Follow-up required is yes.',
    ),
    (
      name: 'single field via record',
      tools: [
        {
          'name': 'record_fields',
          'description': 'Extract explicitly mentioned report fields.',
          'parameters': {
            'type': 'object',
            'properties': {
              'cable_replaced': {
                'type': 'object',
                'properties': {
                  'amount': {'type': 'number'},
                  'unit': {
                    'type': 'string',
                    'enum': ['m'],
                  },
                },
                'required': ['amount', 'unit'],
              },
            },
            'required': <String>[],
          },
        },
      ],
      text: 'Replaced twelve metres.',
    ),
    (
      name: 'explicit status phrase',
      tools: [
        {
          'name': 'record_line_test',
          'description': 'Record the line test result.',
          'parameters': {
            'type': 'object',
            'properties': {
              'result': {
                'type': 'string',
                'enum': ['passed', 'failed', 'not_tested'],
              },
            },
            'required': ['result'],
          },
        },
      ],
      text: 'The line test result is not_tested.',
    ),
  ];
  final results = <Json>[];
  for (final p in probes) {
    final timer = Stopwatch()..start();
    final output = await engine.extract(
      p.text,
      p.tools,
      'Extract explicitly stated engineer report values. Preserve corrections and negation.',
    );
    results.add({
      'probe': p.name,
      'milliseconds': timer.elapsedMilliseconds,
      'output': output,
    });
  }
  results.add({
    'probe': 'schema driven per-field adapter',
    'output': await extractFormFields(
      engine,
      form,
      'Replaced twenty metres actually twelve. I have not tested the line.',
    ),
  });
  File('../../docs/evidence/extraction-probe.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(results)}\n',
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(results));
  exit(0);
}
