import 'dart:convert';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:field_assist/core/persistence/account_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';

/// Generated speech fixture, never the laptop microphone. Native Kokoro plays
/// the bot questions; Whistle hears resampled Kokoro test speech as the answer.
class GeneratedAnswerAudio implements VoiceAudio {
  final output = DeviceVoiceAudio();
  void Function(Uint8List)? feed;
  bool questionFinished = false, openedAfterQuestion = false;
  @override
  Future<void> configure(void Function() interrupted) =>
      output.configure(interrupted);
  @override
  Future<bool> hasPermission() async => true; // No microphone is used by this test adapter.
  @override
  Future<void> capture({
    required void Function(Uint8List) onBytes,
    required void Function(double) onLevel,
    required void Function(Object) onError,
  }) async {
    openedAfterQuestion = questionFinished;
    feed = onBytes;
  }

  @override
  Future<void> stopCapture() async {}
  @override
  Future<bool> play(
    SynthesizedAudio audio,
    void Function(double) onLevel,
  ) async {
    questionFinished = false;
    final done = await output.play(audio, onLevel);
    questionFinished = done;
    return done;
  }

  @override
  Future<void> stopPlayback() => output.stopPlayback();
  @override
  Future<void> close() => output.close();
}

Uint8List resample(SynthesizedAudio audio) {
  final length = (audio.samples.length * 16000 / audio.sampleRate).floor();
  final bytes = ByteData(length * 2);
  for (var i = 0; i < length; i++) {
    final position = i * audio.sampleRate / 16000,
        low = position.floor(),
        high = (low + 1).clamp(0, audio.samples.length - 1);
    final fraction = position - low;
    final sample =
        audio.samples[low] * (1 - fraction) + audio.samples[high] * fraction;
    bytes.setInt16(i * 2, (sample.clamp(-1, 1) * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native complete and partial spoken reports commit every relevant field and reopen',
    (tester) async {
      final api = ApiClient();
      final login = await api.send(
        'auth/login',
        method: 'POST',
        body: {
          'email': const String.fromEnvironment('TEST_ENGINEER_EMAIL'),
          'password': const String.fromEnvironment('TEST_ENGINEER_PASSWORD'),
          'audience': 'mobile',
        },
      );
      final owner = (login['user'] as Json)['id'] as String;
      final repository = SecureReportRepository(const AccountSecureStorage());
      addTearDown(repository.close);
      // Presence is bypassed only in this storage/model integration fixture. Main
      // application account unlock retains real OS user presence requirements.
      await repository.open(owner, authorizePresence: false);
      final form = FormDefinition.fromJson(
        await repository.metadata('installed-form') as Json,
      );
      form.verifyHash();
      final manifest = await repository.metadata('asset-manifest') as Json;
      final directory = await AssetInstaller.installedDirectory(manifest);
      expect(
        await AssetInstaller(api).verifyInstalled(manifest, directory),
        isTrue,
      );
      final engine = FieldVoice();
      await engine.load(directory);
      final clock = Stopwatch()..start();
      final runs = <Json>[];
      for (final completed in [false, true]) {
        final replay = GeneratedAnswerAudio();
        final report = await repository.create(
          form,
          'generated-voice-fixture-not-for-upload',
        );
        Answers values = {};
        final voice = VoiceCoordinator(
          engine: engine,
          schema: form,
          readValues: () => values,
          audio: replay,
          onPatch: (patch, source) async {
            final saved = await repository.save(
              report.id,
              patch.values,
              source: source,
            );
            values = saved.values;
          },
        );
        try {
          await voice.begin();
          final answers = <String, String>{
            'installation_outcome': completed
                ? 'Fully completed.'
                : 'Partially completed.',
            'work_performed':
                'Installed twelve metres of cable and checked the route.',
            'cable_installed': 'Twelve metres.',
            if (completed) 'optical_reading': 'Minus twenty two point four.',
            'connectivity_test': 'Not tested.',
            if (!completed) 'exception_reason': 'The customer was unavailable.',
          };
          final asked = <String>[];
          for (final entry in answers.entries) {
            expect(voice.activeField?.id, entry.key);
            expect(replay.openedAfterQuestion, isTrue);
            expect(voice.state, VoiceState.listening);
            asked.add(entry.key);
            final answer = await engine.synthesize(entry.value);
            replay.feed!(resample(answer));
            await voice.finish();
            expect(
              voice.changed,
              contains(entry.key),
              reason: 'Generated replay must commit the active field',
            );
            expect(voice.savedMessage, contains('saved on this device'));
          }
          expect(voice.activeField, isNull);
          if (completed) {
            expect(voice.touchFields.map((f) => f.id), ['ont_serial']);
          }
          await voice.finishAndPause();
          await repository.close();
          await repository.open(owner, authorizePresence: false);
          final recovered = await repository.get(report.id);
          expect(
            recovered.values['installation_outcome']!.toJson(),
            completed ? 'completed' : 'partial',
          );
          expect(recovered.values['cable_installed']!.toJson(), {
            'amount': 12,
            'unit': 'm',
          });
          if (completed) {
            expect(recovered.values['optical_reading']!.toJson(), -22.4);
          }
          expect(recovered.values['connectivity_test']!.toJson(), 'not_tested');
          expect(encodeAnswers(recovered.values), encodeAnswers(values));
          expect(recovered.state, ReportState.draft);
          for (final id in asked) {
            expect((recovered.provenance[id] as List).last['source'], 'voice');
          }
          runs.add({
            'branch': completed ? 'completed' : 'partial',
            'fieldsAskedAndCommitted': asked,
            'reopened': true,
            'typedQuantityVerified': true,
            'negativeReadingVerified': completed,
            'manualIdentifierNotInvented': !recovered.values.containsKey(
              'ont_serial',
            ),
          });
        } finally {
          await voice.shutdown();
        }
      }
      final evidence = {
        'scope':
            'Simulator native Kokoro playback + generated-answer Whistle replay + SQLCipher. No live microphone, physical-device or accuracy benchmark claim.',
        'runs': runs,
        'state': 'draft - review required',
        'reopened': true,
        'elapsedMs': clock.elapsedMilliseconds,
      };
      binding.reportData = evidence;
      debugPrint('GUIDED_VOICE_EVIDENCE ${jsonEncode(evidence)}');
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
