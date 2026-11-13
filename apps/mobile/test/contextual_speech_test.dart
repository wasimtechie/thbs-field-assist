import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/asset_reference.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/closure/closure_voice_turn.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'support/voice_fakes.dart';
import 'closure_voice_assistant_test.dart' as harness;

final form = FormDefinition.fromJson(
  jsonDecode(
        File('../../fixtures/templates/closure-mvp.json').readAsStringSync(),
      )
      as Json,
);
FieldDefinition field(String id) => form.fields.firstWhere((f) => f.id == id);

void main() {
  test('past is a test-result homophone, not a general positive guess', () {
    for (final words in [
      'past',
      'The service test has past.',
      'It was past.',
    ]) {
      expect(
        closureSpokenAnswer(field('operational_test'), words)?.toJson(),
        'passed',
        reason: words,
      );
    }
    for (final words in [
      'not past',
      'maybe past',
      'past or failed',
      'it was in the past',
      'I walked past the cabinet',
    ]) {
      expect(
        closureSpokenAnswer(field('operational_test'), words),
        isNull,
        reason: words,
      );
    }
    final facts = compactNarrativeFacts(form, 'The service test past.');
    expect(
      facts.firstWhere((f) => f['fieldId'] == 'operational_test')['value'],
      'passed',
    );
    expect(
      facts.firstWhere((f) => f['fieldId'] == 'operational_test')['sourceSpan'],
      contains('past'),
    );
    expect(
      compactNarrativeFacts(form, 'The service test did not past.')
          .where((f) => f['fieldId'] == 'operational_test')
          .every((f) => f['value'] != 'passed'),
      true,
    );
  });

  test('asset homophones require an explicit identifier and remain scoped', () {
    const examples = {
      'paul one two three': 'POLE-123',
      'paule dash SYN one zero': 'POLE-SYN-10',
      'chambe zero four': 'CHAMBER-04',
      'chemba twelve': 'CHAMBER-12',
      'the chamber reference is CH-SYN-04': 'CH-SYN-04',
      'CBT-SYN-0010': 'CBT-SYN-0010',
    };
    for (final entry in examples.entries) {
      expect(spokenAssetReference(entry.key), entry.value, reason: entry.key);
    }
    for (final words in [
      'Paul. Paul.',
      'chemba',
      'My name is Paul',
      'Paul says number five',
      'Pole damaged at nine',
    ]) {
      expect(spokenAssetReference(words), isNull, reason: words);
    }
    expect(
      compactNarrativeFacts(
        form,
        'Paul one two three',
      ).where((f) => f['fieldId'] == 'serving_asset'),
      isEmpty,
    );
    expect(
      compactNarrativeFacts(
        form,
        'The serving asset is paule one two three.',
      ).firstWhere((f) => f['fieldId'] == 'serving_asset')['value'],
      'POLE-123',
    );
  });

  test('openings rotate and resumptions do not pretend it is a new visit', () {
    expect(
      List.generate(3, (i) => closureOpeningGreeting(i)).toSet(),
      hasLength(3),
    );
    expect(closureOpeningGreeting(3), closureOpeningGreeting(0));
    expect(closureOpeningGreeting(1, resumed: true), contains('still need'));
  });

  testWidgets(
    'a type-only homophone is clarified by voice, then digits complete its reference',
    (tester) async {
      final engine = TestEngine([])..answer = 'chemba';
      final audio = TestAudio([]);
      ClosureVoiceAnswer? accepted;
      await harness.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          announceSavedAnswers: false,
          nextQuestion: (_) => accepted == null ? field('serving_asset') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, response) async {
            if (response.answer != null) accepted = response;
          },
        ),
      );
      await harness.utter(tester, audio);
      expect(accepted, isNull);
      expect(
        engine.events.any(
          (e) => e.contains('I heard chamber. What is its number'),
        ),
        true,
      );
      engine.answer = 'zero four';
      await harness.utter(tester, audio);
      expect(accepted?.answer?.toJson(), 'CHAMBER-04');
      expect(accepted?.transcript, 'chemba\nzero four');
    },
  );

  testWidgets(
    'repeated mismatches keep voice clarification available without forcing a manual form',
    (tester) async {
      final engine = TestEngine([])..answer = 'maybe it did';
      final audio = TestAudio([]);
      ClosureVoiceAnswer? accepted;
      await harness.mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) =>
              accepted == null ? field('operational_test') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, response) async {
            if (response.answer != null) accepted = response;
          },
        ),
      );
      for (var i = 0; i < 3; i++) {
        await harness.utter(tester, audio);
      }
      expect(accepted, isNull);
      expect(find.text('Conversation paused'), findsNothing);
      engine.answer = 'past';
      await harness.utter(tester, audio);
      expect(accepted?.answer?.toJson(), 'passed');
      expect(accepted?.transcript, 'past');
    },
  );
}
