import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';

void main() {
  final full = FormDefinition.fromJson(
    jsonDecode(
          File('../../fixtures/templates/closure-mvp.json').readAsStringSync(),
        )
        as Json,
  );
  final form = compactClosureForm(full);
  FieldDefinition field(String id) => form.fields.firstWhere((f) => f.id == id);
  test(
    'spoken options accept explicit sentences, displayed labels and ordinal choices',
    () {
      const outcomes = {
        'The work is fully completed.': 'completed',
        'I have fully completed the work.': 'completed',
        'I have completed it.': 'completed',
        "I'm done.": 'completed',
        'We have fully completed the job.': 'completed',
        'Yes, the job is completed.': 'completed',
        'Work completed': 'completed',
        'The job was partially completed.': 'partial',
        'Partially completed': 'partial',
        'The visit is blocked.': 'blocked',
        'The job is on hold.': 'hold',
        'Referral required': 'referred',
        'This build stage has been completed.': 'stage_completed',
        'Stage completed': 'stage_completed',
        'The network is ready.': 'network_ready',
        'Select the second option.': 'partial',
        'Option two': 'partial',
        'Please choose option 1': 'completed',
      };
      for (final e in outcomes.entries) {
        expect(
          closureSpokenAnswer(field('claimed_outcome'), e.key)?.toJson(),
          e.value,
          reason: e.key,
        );
      }
      const tests = {
        'The service test passed.': 'passed',
        'The test has passed.': 'passed',
        'The service test has been passed.': 'passed',
        'It was a pass.': 'passed',
        'Yes, passed.': 'passed',
        'The test was successful.': 'passed',
        'The operational test failed.': 'failed',
        'The test was not tested.': 'not_tested',
        'The third option': 'not_tested',
      };
      for (final e in tests.entries) {
        expect(
          closureSpokenAnswer(field('operational_test'), e.key)?.toJson(),
          e.value,
          reason: e.key,
        );
      }
      for (final f in form.fields.where(
        (f) => f.kind == FieldKind.singleSelect,
      )) {
        for (final choice in f.options) {
          expect(
            closureSpokenAnswer(f, choice.label)?.toJson(),
            choice.id,
            reason: choice.label,
          );
        }
      }
    },
  );
  test(
    'negation, uncertain speech and alternatives never become a successful choice',
    () {
      for (final text in [
        'Maybe fully completed',
        'Not fully completed',
        'Not completed',
        'Completed or partially completed',
        'Completed, actually blocked',
        'I think the job is completed',
        'The job will be completed',
        'Not the first option',
        'Option eight',
      ]) {
        expect(
          closureSpokenAnswer(field('claimed_outcome'), text),
          isNull,
          reason: text,
        );
      }
      for (final text in [
        'The service test has not passed',
        'Passed or failed',
        'It probably passed',
        'It passed but then failed',
        'No, passed',
        'It will pass',
        'Not failed',
      ]) {
        expect(
          closureSpokenAnswer(field('operational_test'), text),
          isNull,
          reason: text,
        );
      }
    },
  );
}
