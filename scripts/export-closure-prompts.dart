import 'dart:convert';
import 'dart:io';
import '../apps/mobile/lib/core/contracts.dart';
import '../apps/mobile/lib/features/closure/closure_speech.dart';
import 'package:field_voice/field_voice.dart';

void main() {
  final raw =
      jsonDecode(File('fixtures/templates/closure-mvp.json').readAsStringSync())
          as Json;
  final form = FormDefinition.fromJson(raw);
  final data = {
    'speechProfile': {
      'model': attentiveSpeechModel,
      'voice': attentiveSpeechVoice,
      'speakerId': attentiveSpeechSpeakerId,
      'speed': attentiveSpeechSpeed,
    },
    'speechProfiles': [
      for (final voice in offlineSpeechVoices)
        {
          'model': attentiveSpeechModel,
          'voice': voice.id,
          'speakerId': voice.speakerId,
          'speed': attentiveSpeechSpeed,
        },
    ],
    'policyId': 'fttp-closure-mvp',
    'policyVersion': (raw['closurePolicy'] as Json)['version'],
    'prompts': [
      for (final p in closureAssistantPrompts.entries)
        {'fieldId': p.key, 'text': p.value, 'allVoices': true},
      {
        'fieldId': 'voice_preview',
        'text': speechVoicePreview,
        'allVoices': true,
      },
      for (final f in form.fields.where(
        (f) =>
            f.voiceEnabled &&
            f.source['capture'] != 'evidence' &&
            !['scenario', 'work_stage'].contains(f.id),
      ))
        {
          'fieldId': f.id,
          'text': closureSpokenQuestion(f),
          'allVoices': const {
            'actual_work',
            'claimed_outcome',
            'serving_asset',
            'optical_rx_dbm',
            'operational_test',
            'next_action',
          }.contains(f.id),
        },
    ],
  };
  File(
    '.local/voice-lab/question-prompts.json',
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(data)}\n');
  print(
    '${(data['prompts'] as List).length} fixed questions exported from the app’s spoken-question function.',
  );
}
