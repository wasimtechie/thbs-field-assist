import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/label_scan/cable_label.dart';
import 'package:field_assist/features/label_scan/cable_scan_screen.dart';

final cableForm = FormDefinition.fromJson(
  jsonDecode(
        File(
          '../../fixtures/templates/fibre-cable-label.json',
        ).readAsStringSync(),
      )
      as Json,
);
const labelText = '''CABLE ID: CBL-2026-0042
DRUM NO: DR-0017
MANUFACTURED BY: DEMO CABLE WORKS
BATCH NO: B2409-08
CABLE TYPE: 24F SM G.652D
FIBRE COUNT: 24
LENGTH: 1000 m
MANUFACTURE DATE: 2026-09-18''';
FieldDefinition target(String name) =>
    cableForm.fields.firstWhere((f) => f.scanTarget == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'labelled details map to the configured fields, never installation length',
    () {
      final existing = <String, Answer?>{
        'cable_installed': const QuantityAnswer(12, 'm'),
      };
      final patch = validLabelSuggestions(
        cableForm,
        existing,
        CableLabelReadout.parse(labelText),
      );
      expect(patch.length, 8);
      expect(patch[target('cable_id').id]?.toJson(), 'CBL-2026-0042');
      expect(patch[target('drum_id').id]?.toJson(), 'DR-0017');
      expect(patch[target('manufacturer').id]?.toJson(), 'DEMO CABLE WORKS');
      expect(patch[target('fibre_count').id]?.toJson(), 24);
      expect(patch[target('declared_length').id]?.toJson(), {
        'amount': 1000.0,
        'unit': 'm',
      });
      expect(patch[target('manufactured_date').id]?.toJson(), '2026-09-18');
      expect(patch.containsKey('cable_installed'), false);
      expect(patch.containsKey('installation_outcome'), false);
      expect(existing['cable_installed']?.toJson(), {
        'amount': 12,
        'unit': 'm',
      });
    },
  );
  test('separate label/value lines and identifier spelling are retained', () {
    final readout = CableLabelReadout.parse(
      'CABLE ID:\n00-OI-10\nManufacturer:\nExample Works',
    );
    expect(readout.values['cable_id'], '00-OI-10');
    expect(readout.values['manufacturer'], 'Example Works');
  });
  test('conflicting values remain unresolved instead of picking one', () {
    final readout = CableLabelReadout.parse('CABLE ID: A001\nCABLE ID: A002');
    expect(readout.ambiguous, contains('cable_id'));
    expect(readout.values.containsKey('cable_id'), false);
  });
  test('repeated identical printed values are not a conflict', () {
    expect(
      CableLabelReadout.parse(
        'CABLE ID: A001\nCABLE ID: A001',
      ).values['cable_id'],
      'A001',
    );
  });
  test('one label is not consumed as another label value', () {
    final readout = CableLabelReadout.parse('Manufacturer:\nCABLE ID: A001');
    expect(readout.values.containsKey('manufacturer'), false);
    expect(readout.values['cable_id'], 'A001');
  });
  for (final value in ['1000', '1,000 m', '1,5 km', '12 ft', '-5 m']) {
    test('printed length refuses ambiguous/unsupported value $value', () {
      expect(decodeLabelEntry(target('declared_length'), value), null);
    });
  }
  test(
    'explicit km is preserved and converts only to a configured allowed unit',
    () {
      expect(decodeLabelEntry(target('declared_length'), '1.25 km')?.toJson(), {
        'amount': 1.25,
        'unit': 'km',
      });
      final metres = FieldDefinition.fromJson({
        ...target('declared_length').source,
        'units': {
          'allowed': ['m'],
          'canonical': 'm',
        },
      });
      expect(decodeLabelEntry(metres, '1.25 km')?.toJson(), {
        'amount': 1250.0,
        'unit': 'm',
      });
    },
  );
  for (final date in [
    '02/03/2026',
    '2026-02-30',
    '2026-13-01',
    'September 2026',
  ]) {
    test('ambiguous or invalid manufacture date $date is not auto-applied', () {
      expect(decodeLabelEntry(target('manufactured_date'), date), null);
    });
  }
  test('field constraints reject implausible count and excess precision', () {
    final patch = validLabelSuggestions(
      cableForm,
      {},
      CableLabelReadout.parse('FIBRE COUNT: 9999\nLENGTH: 1.123456 m'),
    );
    expect(patch, isEmpty);
  });
  test('legacy form without scan mappings has no camera candidates', () {
    final old = FormDefinition.fromJson(
      jsonDecode(File('../../fixtures/templates/fibre.json').readAsStringSync())
          as Json,
    );
    expect(scannableFields(old, {}), isEmpty);
    expect(
      validLabelSuggestions(old, {}, CableLabelReadout.parse(labelText)),
      isEmpty,
    );
  });
  test('schema rejects duplicate and incompatible scan mapping', () {
    final raw = jsonDecode(jsonEncode(cableForm.source)) as Json;
    (raw['fields'] as List)[1]['scan'] = {
      'kind': 'cable_label',
      'target': 'cable_id',
    };
    expect(() => FormDefinition.fromJson(raw), throwsFormatException);
    (raw['fields'] as List)[1]['scan'] = {
      'kind': 'cable_label',
      'target': 'fibre_count',
    };
    expect(() => FormDefinition.fromJson(raw), throwsFormatException);
  });
  test(
    'native OCR failure still cancels cleanup and returns the actual failure',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeLabelReader.channel, (call) async {
            calls.add(call.method);
            if (call.method == 'recognize') {
              throw PlatformException(
                code: 'OCR_FAILED',
                message: 'Retake the photo.',
              );
            }
            return null;
          });
      await expectLater(
        const NativeLabelReader().read('/private/cache/test.jpg'),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, ['recognize', 'cancel']);
    },
  );
  testWidgets('review requires an explicit replacement for existing values', (
    tester,
  ) async {
    Answers? applied;
    await tester.pumpWidget(
      MaterialApp(
        theme: fieldTheme(),
        home: Scaffold(
          body: CableLabelReview(
            form: cableForm,
            existing: {
              target('manufacturer').id: const TextAnswer(
                'Existing Manufacturer',
              ),
            },
            readout: CableLabelReadout.parse(labelText),
            onApply: (patch) => applied = patch,
            onRetake: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apply to report'));
    await tester.pump();
    expect(applied!.containsKey(target('manufacturer').id), false);
    expect(applied![target('cable_id').id]?.toJson(), 'CBL-2026-0042');
    expect(applied!.containsKey('cable_installed'), false);
  });
  testWidgets('blank scan cannot claim a saved result', (tester) async {
    var applied = false, retaken = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: fieldTheme(),
        home: Scaffold(
          body: CableLabelReview(
            form: cableForm,
            existing: {},
            readout: CableLabelReadout.parse('unlabelled illegible text'),
            onApply: (_) => applied = true,
            onRetake: () => retaken = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Apply to report'));
    await tester.pump();
    expect(applied, false);
    await tester.tap(find.text('Retake'));
    await tester.pump();
    expect(retaken, true);
    expect(find.textContaining('saved on this device'), findsNothing);
  });
}
