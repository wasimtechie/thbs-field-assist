import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/question_voice.dart';
import 'package:field_voice/field_voice.dart';

void main() {
  test(
    'every spoken closure question has an exact, verified offline recording',
    () {
      final form = FormDefinition.fromJson(
        jsonDecode(
              File(
                '../../fixtures/templates/closure-mvp.json',
              ).readAsStringSync(),
            )
            as Json,
      );
      final index =
          jsonDecode(
                File('assets/voice_questions/index.json').readAsStringSync(),
              )
              as Json;
      final prompts = index['prompts'] as Json;
      final fields = form.fields
          .where(
            (f) =>
                f.voiceEnabled &&
                f.source['capture'] != 'evidence' &&
                !['scenario', 'work_stage'].contains(f.id),
          )
          .toList();
      expect(
        prompts.length,
        fields.length + closureAssistantPrompts.length + 1,
      );
      expect(index['revision'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(index['model'], attentiveSpeechModel);
      expect(index['voice'], attentiveSpeechVoice);
      expect(index['settings']['speakerId'], attentiveSpeechSpeakerId);
      expect(index['settings']['speed'], attentiveSpeechSpeed);
      expect(index['settings']['backgroundAudio'], false);
      final expected = {
        ...closureAssistantPrompts,
        'voice_preview': speechVoicePreview,
        for (final f in fields) f.id: closureSpokenQuestion(f),
      };
      for (final prompt in expected.entries) {
        final text = prompt.value,
            key = sha256.convert(utf8.encode(text)).toString();
        final entry = prompts[key] as Json?;
        expect(
          entry,
          isNotNull,
          reason: 'No exact recording for ${prompt.key}',
        );
        expect(entry!['fieldId'], prompt.key);
        expect(entry['text'], text);
        final bytes = File(
          'assets/voice_questions/${entry['file']}',
        ).readAsBytesSync();
        expect(
          sha256.convert(bytes).toString(),
          entry['sha256'],
          reason: prompt.key,
        );
        final audio = decodeQuestionWav(bytes);
        expect(audio.samples, isNotEmpty);
        expect(audio.sampleRate, 24000);
      }
    },
  );
  test(
    'all selectable voices have verified offline previews and six-field prompts',
    () {
      final index =
          jsonDecode(
                File('assets/voice_questions/index.json').readAsStringSync(),
              )
              as Json;
      final form = FormDefinition.fromJson(
        jsonDecode(
              File(
                '../../fixtures/templates/closure-mvp.json',
              ).readAsStringSync(),
            )
            as Json,
      );
      final previewHashes = <String>{};
      for (final voice in offlineSpeechVoices) {
        final entry = index['voices'][voice.id] as Json;
        expect(entry['voice'], voice.id);
        expect(entry['settings']['speakerId'], voice.speakerId);
        expect(entry['settings']['backgroundAudio'], false);
        final expected = {
          ...closureAssistantPrompts,
          'voice_preview': speechVoicePreview,
          for (final field in form.fields.where(
            (f) => const {
              'actual_work',
              'claimed_outcome',
              'serving_asset',
              'optical_rx_dbm',
              'operational_test',
              'next_action',
            }.contains(f.id),
          ))
            field.id: closureSpokenQuestion(field),
        };
        for (final prompt in expected.entries) {
          final key = sha256.convert(utf8.encode(prompt.value)).toString();
          final clip = entry['prompts'][key] as Json;
          expect(clip['text'], prompt.value);
          final bytes = File(
            'assets/voice_questions/${clip['file']}',
          ).readAsBytesSync();
          expect(sha256.convert(bytes).toString(), clip['sha256']);
          expect(decodeQuestionWav(bytes).sampleRate, 24000);
          if (prompt.key == 'voice_preview') {
            previewHashes.add(clip['sha256'] as String);
          }
        }
      }
      expect(previewHashes, hasLength(offlineSpeechVoices.length));
    },
  );
}
