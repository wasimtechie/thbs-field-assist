import 'package:field_voice/field_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/structured_visit_extraction.dart';
import 'closure_journey_test.dart' as fixture;

class RecordingExtractor implements FieldExtractor {
  RecordingExtractor(this.respond);
  final Json Function(String text, List<Json> tools) respond;
  final inputs = <String>[];

  @override
  Future<Json> extract(String text, List<Json> tools, String context) async {
    inputs.add(text);
    return respond(text, tools);
  }
}

Json reply(List<Json> tools, String result, {double confidence = .9}) => {
  'confidence': confidence,
  'function_calls': [
    {
      'name': tools.single['name'],
      'arguments': {'result': result},
    },
  ],
};

void main() {
  final form = compactClosureForm(fixture.closureForm);
  Future<Map<String, dynamic>> extract(
    RecordingExtractor engine,
    String text,
  ) async => {
    for (final fact in await StructuredVisitExtractor(
      NeedleVisitExtractor(engine),
    ).extract(form, text, current: () => true))
      fact['fieldId'] as String: fact['value'],
  };

  test(
    'small model sees one exact source clause and one enum field per call',
    () async {
      final engine = RecordingExtractor((text, tools) {
        final schema = tools.single['parameters'] as Json;
        expect((schema['properties'] as Json).keys, ['result']);
        expect(schema['required'], ['result']);
        return reply(
          tools,
          tools.single['name'] == 'record_claimed_outcome'
              ? 'completed'
              : 'passed',
        );
      });
      const text =
          'Everything is now done. The service verification was successful.';
      final values = await extract(engine, text);
      expect(values['claimed_outcome'], 'completed');
      expect(values['operational_test'], 'passed');
      expect(engine.inputs, [
        'Everything is now done',
        'The service verification was successful',
      ]);
      expect(values['serving_asset'], isNull);
      expect(values['optical_rx_dbm'], isNull);
    },
  );

  test('low confidence and unsupported failure remain missing', () async {
    for (final confidence in [.2, .9]) {
      final engine = RecordingExtractor(
        (_, tools) => reply(tools, 'failed', confidence: confidence),
      );
      final values = await extract(
        engine,
        'The service verification was successful.',
      );
      expect(values['operational_test'], isNull);
    }
  });

  test(
    'ambiguous and uncertain clauses are not sent for classification',
    () async {
      for (final text in [
        'Maybe the service verification was successful.',
        'The service verification was successful. The service verification failed.',
        'Everything might be done.',
      ]) {
        final engine = RecordingExtractor((_, tools) => reply(tools, 'passed'));
        final values = await extract(engine, text);
        expect(engine.inputs, isEmpty);
        expect(values['operational_test'], isNull);
        expect(values['claimed_outcome'], isNull);
      }
    },
  );

  test('ungrounded or malformed model output cannot update a field', () async {
    for (final response in <Json>[
      {'confidence': double.nan, 'function_calls': []},
      {
        'confidence': .99,
        'validation': {
          'ungrounded': ['result'],
        },
        'function_calls': [
          {
            'name': 'record_operational_test',
            'arguments': {'result': 'passed'},
          },
        ],
      },
      {
        'confidence': .99,
        'function_calls': [
          {
            'name': 'other',
            'arguments': {'result': 'passed'},
          },
        ],
      },
      {
        'confidence': .99,
        'function_calls': [
          {
            'name': 'record_operational_test',
            'arguments': {'result': 'passed', 'optical_rx_dbm': -18.2},
          },
        ],
      },
    ]) {
      final engine = RecordingExtractor((_, _) => response);
      final values = await extract(
        engine,
        'The service verification was successful.',
      );
      expect(values['operational_test'], isNull);
      expect(values['optical_rx_dbm'], isNull);
    }
  });

  test('known completion and test phrases need no model inference', () async {
    final engine = RecordingExtractor(
      (_, _) => throw StateError('unnecessary inference'),
    );
    final values = await extract(
      engine,
      'I finished all the work. Connectivity checks were successful. Optical receive -18.2 dBm.',
    );
    expect(engine.inputs, isEmpty);
    expect(values['claimed_outcome'], 'completed');
    expect(values['operational_test'], 'passed');
    expect(values['optical_rx_dbm'], -18.2);
    for (final text in [
      'I have not finished all the work.',
      'I think connectivity checks were successful.',
      'Connectivity checks were not successful.',
    ]) {
      final facts = compactNarrativeFacts(form, text);
      expect(
        facts.where((f) => f['fieldId'] != 'actual_work' && f['value'] != null),
        isEmpty,
      );
    }
  });
}
