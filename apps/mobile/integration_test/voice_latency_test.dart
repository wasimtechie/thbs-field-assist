import 'dart:convert';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/question_voice.dart';
import 'package:field_assist/features/voice/prompt_audio_cache.dart';
import 'package:field_assist/features/voice/speech_input.dart';
import 'guided_voice_test.dart' show resample;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'measure native recognition and prompt preparation using synthetic speech only',
    (tester) async {
      final api = ApiClient();
      final login = await api.send(
        'auth/login',
        method: 'POST',
        body: {
          'email': 'closure@fieldassist.demo',
          'password': '123456',
          'audience': 'mobile',
        },
      );
      api.token = login['token'] as String;
      final provision = await api.send(
        'devices/provision',
        method: 'POST',
        body: {
          'deviceId': const Uuid().v4(),
          'platform': 'ios',
          'appVersion': 'synthetic-latency-check',
          'osVersion': 'Simulator diagnostics',
        },
      );
      final directory = await AssetInstaller(
        api,
      ).install((provision['manifest'] as Json)['assets'] as Json, (_) {});
      final engine = FieldVoice();
      await engine.load(directory);
      addTearDown(engine.unload);
      final schema = FormDefinition.fromJson(provision['template'] as Json);
      final numeric = schema.fields.firstWhere((f) => f.id == 'optical_rx_dbm');
      final watch = Stopwatch()..start();
      final synthetic = await engine.synthesize('Minus eighteen point two.');
      final synthesisMs = watch.elapsedMilliseconds;
      final data = ByteData.sublistView(resample(synthetic));
      final spoken = Float32List(data.lengthInBytes ~/ 2);
      for (var i = 0; i < spoken.length; i++) {
        spoken[i] = data.getInt16(i * 2, Endian.little) / 32768;
      }
      final padded = Float32List.fromList([
        ...Float32List(16000 * 6),
        ...spoken,
        ...Float32List(16000 * 2),
      ]);
      final trimmed = trimSpeechSilence(padded);
      final runs = <Json>[];
      // Two orders reduce the risk of attributing first-call warm-up to trimming.
      for (final entry in [
        ('padded', padded),
        ('trimmed', trimmed),
        ('trimmed', trimmed),
        ('padded', padded),
      ]) {
        watch.reset();
        final text = await engine.transcribe(entry.$2);
        final ms = watch.elapsedMilliseconds;
        final value = closureSpokenAnswer(numeric, text)?.toJson();
        expect(
          value,
          -18.2,
          reason: 'Synthetic replay must preserve the negative measurement.',
        );
        runs.add({
          'input': entry.$1,
          'audioMs': entry.$2.length * 1000 ~/ 16000,
          'recognitionMs': ms,
          'negativeReadingPreserved': true,
        });
      }
      final voice = PromptAudioCache(QuestionVoice(engine));
      watch.reset();
      await voice.synthesize(
        closureAssistantPrompts['assistant_answer_saved']!,
      );
      final coldPromptMs = watch.elapsedMilliseconds;
      watch.reset();
      await voice.synthesize(
        closureAssistantPrompts['assistant_answer_saved']!,
      );
      final warmPromptMs = watch.elapsedMilliseconds;
      final evidence = {
        'scope':
            'iOS simulator debug; generated speech only. No microphone, field accuracy or physical-phone latency claim.',
        'syntheticAnswerSynthesisMs': synthesisMs,
        'recognition': runs,
        'coldPreparedPromptMs': coldPromptMs,
        'cachedPreparedPromptMs': warmPromptMs,
      };
      binding.reportData = evidence;
      debugPrint('VOICE_LATENCY_EVIDENCE ${jsonEncode(evidence)}');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
