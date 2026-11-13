import 'dart:async';
import 'dart:convert';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/account_secure_storage.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/offline_access/entitlement.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/voice/pcm_meter.dart';
import 'package:field_assist/features/closure/question_voice.dart';
import 'package:field_assist/features/voice/prompt_audio_cache.dart';
import 'guided_voice_test.dart' as generated;

/// Real-time generated input through the production PCM meter. No microphone
/// opens. Output still uses native DeviceVoiceAudio/SoLoud playback.
class TurnGapAudio extends generated.GeneratedAnswerAudio {
  int serial = 0;
  void Function(Uint8List)? input;
  void Function(double)? meter;
  Stopwatch? gap;
  final nextSpeech = Completer<int>();
  int configureMs = 0;

  @override
  Future<void> configure(void Function() onInterruption) async {
    final watch = Stopwatch()..start();
    await super.configure(onInterruption);
    if (gap != null) configureMs += watch.elapsedMilliseconds;
  }

  @override
  Future<void> capture({
    required void Function(Uint8List) onBytes,
    required void Function(double) onLevel,
    required void Function(Object) onError,
  }) async {
    serial++;
    input = onBytes;
    meter = onLevel;
  }

  @override
  Future<void> stopCapture() async {
    serial++;
    input = null;
    meter = null;
  }

  @override
  Future<bool> play(SynthesizedAudio audio, void Function(double) onLevel) =>
      super.play(audio, (value) {
        if (gap != null && value > .001 && !nextSpeech.isCompleted) {
          nextSpeech.complete(gap!.elapsedMilliseconds);
        }
        onLevel(value);
      });

  Future<void> answer(Uint8List speech) async {
    final current = serial, emit = input!, level = meter!;
    var lastVoiceEnd = 0;
    // Locate the end of the final voiced 20 ms frame in this synthetic fixture.
    for (var at = 0; at + 640 <= speech.length; at += 640) {
      final probe = PcmLevelMeter((v) {
        if (v >= .004) lastVoiceEnd = at + 640;
      });
      probe.add(Uint8List.sublistView(speech, at, at + 640));
    }
    expect(lastVoiceEnd, greaterThan(0));
    final levels = PcmLevelMeter(level);
    final padded = Uint8List(speech.length + 32000)..setAll(0, speech);
    for (var at = 0; at < padded.length && current == serial; at += 640) {
      final end = (at + 640).clamp(0, padded.length);
      final chunk = Uint8List.sublistView(padded, at, end);
      emit(chunk);
      levels.add(chunk);
      if (at < lastVoiceEnd && end >= lastVoiceEnd) {
        gap = Stopwatch()..start();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

class TimedRecognizer implements SpeechRecognizer {
  TimedRecognizer(this.engine);
  final SpeechRecognizer engine;
  int elapsedMs = 0;
  @override
  Future<String> transcribe(Float32List pcm16k) async {
    final watch = Stopwatch()..start();
    final text = await engine.transcribe(pcm16k);
    elapsedMs += watch.elapsedMilliseconds;
    return text;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'measure answer end to next spoken question with real access checks and encrypted save',
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
      final device = const Uuid().v4();
      final provision = await api.send(
        'devices/provision',
        method: 'POST',
        body: {
          'deviceId': device,
          'platform': 'ios',
          'appVersion': 'synthetic-turn-gap-check',
          'osVersion': 'Simulator diagnostics',
        },
      );
      final directory = await AssetInstaller(
        api,
      ).install((provision['manifest'] as Json)['assets'] as Json, (_) {});
      final engine = FieldVoice();
      await engine.load(directory);
      addTearDown(engine.unload);
      final speech = generated.resample(
        await engine.synthesize('Minus eighteen point two.'),
      );
      final schema = FormDefinition.fromJson(provision['template'] as Json);
      final reading = schema.fields.firstWhere((f) => f.id == 'optical_rx_dbm');
      final test = schema.fields.firstWhere((f) => f.id == 'operational_test');
      final audio = TurnGapAudio(), recognizer = TimedRecognizer(engine);
      const secrets = AccountSecureStorage();
      final runId = 'synthetic-gap-${const Uuid().v4()}';
      final leaseKey = '$runId:lease', observedKey = '$runId:observed';
      await secrets.write(
        key: leaseKey,
        value: provision['entitlement'] as String,
      );
      await secrets.write(
        key: observedKey,
        value: provision['serverTime'] as String,
      );
      final repo = SecureReportRepository(secrets);
      await repo.open(runId, authorizePresence: false);
      addTearDown(() async {
        await repo.close();
        await secrets.delete(key: leaseKey);
        await secrets.delete(key: observedKey);
      });
      final accessMs = <int>[];
      Future<void> access() async {
        final watch = Stopwatch()..start();
        final token = await secrets.read(key: leaseKey);
        final previous = await secrets.read(key: observedKey);
        await OfflineLease.verify(
          token!,
          jsonDecode(const String.fromEnvironment('ENTITLEMENT_PUBLIC_JWK'))
              as Json,
          keyId: const String.fromEnvironment(
            'ENTITLEMENT_KEY_ID',
            defaultValue: 'field-assist-local-1',
          ),
          now: DateTime.now().toUtc(),
          lastObserved: DateTime.parse(previous!),
          userId: (login['user'] as Json)['id'] as String,
          deviceId: device,
        );
        await secrets.write(
          key: observedKey,
          value: DateTime.now().toUtc().toIso8601String(),
        );
        if (audio.gap != null && !audio.nextSpeech.isCompleted) {
          accessMs.add(watch.elapsedMilliseconds);
        }
      }

      Object? saved;
      var saveMs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ClosureVoiceAssistant(
            recognizer: recognizer,
            synthesizer: PromptAudioCache(QuestionVoice(engine)),
            audio: audio,
            assertAccess: access,
            needsNarrative: false,
            announceSavedAnswers: false,
            nextQuestion: (_) => saved == null ? reading : test,
            proposeNarrative: (_, _) async => [],
            keepNarrative: (_, _, _) async {},
            keepAnswer: (_, answer) async {
              // The compact screen checks the owner and checks again inside its
              // serialized durable save. Preserve that cost in this synthetic replay.
              await access();
              await access();
              final watch = Stopwatch()..start();
              await repo.setMetadata('summary', {
                'value': answer.answer?.toJson(),
                'sourceType': answer.sourceType,
              });
              saveMs = watch.elapsedMilliseconds;
              saved = answer.answer?.toJson();
            },
          ),
        ),
      );
      final wait = Stopwatch()..start();
      while (audio.input == null &&
          wait.elapsed < const Duration(seconds: 40)) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(audio.input, isNotNull);
      final feeding = audio.answer(speech);
      while (!audio.nextSpeech.isCompleted &&
          wait.elapsed < const Duration(seconds: 60)) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(audio.nextSpeech.isCompleted, isTrue);
      final gap = await audio.nextSpeech.future;
      await feeding;
      expect(saved, -18.2);
      expect((await repo.metadata('summary') as Json)['value'], -18.2);
      final evidence = {
        'scope':
            'iOS simulator debug; realtime generated PCM into the production meter and voice assistant, real Keychain/ES256 checks, SQLCipher save and native playback. First nonzero output-meter frame, not an acoustic microphone-to-speaker or physical-phone measurement.',
        'answerEndToNextSpeechMs': gap,
        'recognitionMs': recognizer.elapsedMs,
        'accessCheckMs': accessMs,
        'encryptedSaveMs': saveMs,
        'audioConfigureMs': audio.configureMs,
        'negativeReadingSaved': true,
      };
      binding.reportData = evidence;
      debugPrint('SOFTWARE_TURN_GAP_EVIDENCE ${jsonEncode(evidence)}');
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
