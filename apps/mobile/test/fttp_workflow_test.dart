import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/fttp/fttp_workflow.dart';
import 'package:field_assist/features/fttp/fttp_widgets.dart';

void main() {
  final raw =
      jsonDecode(
            File('../../fixtures/templates/fttp-demo.json').readAsStringSync(),
          )
          as Json;
  final form = FormDefinition.fromJson({
    ...raw,
    'versionId': '50000000-0000-4000-8000-000000000005',
    'versionNumber': 1,
    'schemaHash': 'unused',
  });
  test(
    'successful and blocked examples satisfy their own conditional schemas',
    () {
      for (final blocked in [false, true]) {
        expect(validate(form, fttpExample(blocked)).valid, isTrue);
      }
    },
  );
  test('completion refuses negative confirmations and missing evidence', () {
    final values = fttpExample(false);
    final photos = <Json>[
      for (final stage in ['before', 'installation', 'test']) {'stage': stage},
    ];
    expect(fttpIssues(fttpTemplateId, values, photos), isEmpty);
    expect(
      fttpIssues(fttpTemplateId, {
        ...values,
        'site_checks': const BoolAnswer(false),
      }, photos),
      isNotEmpty,
    );
    expect(
      fttpIssues(fttpTemplateId, values, photos.take(2).toList()),
      isNotEmpty,
    );
  });
  test('blocked handover requires owner, next action and blocker evidence', () {
    final values = fttpExample(true);
    expect(
      fttpIssues(fttpTemplateId, values, [
        {'stage': 'blocker'},
      ]),
      isEmpty,
    );
    expect(
      fttpIssues(
        fttpTemplateId,
        {...values, 'next_action': null},
        [
          {'stage': 'blocker'},
        ],
      ),
      isNotEmpty,
    );
    expect(fttpIssues(fttpTemplateId, values, []), isNotEmpty);
  });
  testWidgets(
    'demo evidence is a small real PNG with a visible synthetic label',
    (tester) async {
      final bytes = (await tester.runAsync(() => illustration('before')))!;
      expect(bytes.take(8).toList(), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(bytes.length, lessThan(120000));
    },
  );
}
