import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/closure/closure_extraction.dart';
import 'package:field_assist/features/closure/closure_voice_turn.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/closure/question_voice.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'guided_voice_test.dart' as generated;

class AutomaticAnswerAudio extends generated.GeneratedAnswerAudio {
  @override
  Future<void> capture({
    required void Function(Uint8List) onBytes,
    required void Function(double) onLevel,
    required void Function(Object) onError,
  }) async {
    await super.capture(onBytes: onBytes, onLevel: onLevel, onError: onError);
    feed = (pcm) {
      onBytes(pcm);
      onLevel(.05);
      onBytes(Uint8List(48000));
      onLevel(0);
    };
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'closure branches, evidence archive and human-approved source trace survive encrypted reopen',
    (tester) async {
      final api = ApiClient();
      expect(
        [
          'localhost',
          '127.0.0.1',
        ].contains(Uri.parse(api.dio.options.baseUrl).host),
        isTrue,
      );
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
          'appVersion': 'closure-native-test',
          'osVersion': 'Synthetic simulator verification',
        },
      );
      final schema = FormDefinition.fromJson(provision['template'] as Json);
      schema.verifyHash();
      expect(schema.templateId, closureTemplateId);
      final repo = SecureReportRepository(
        const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
          ),
        ),
      );
      // Isolated synthetic namespace; does not bypass presence for real user data.
      final owner = 'closure-native-${const Uuid().v4()}';
      await repo.open(owner, authorizePresence: false);
      addTearDown(repo.close);
      expect(repo.cipherVersion, isNotEmpty);
      final examples =
          jsonDecode(
                await rootBundle.loadString('assets/closure/examples.json'),
              )
              as Json;
      var draft = await repo.create(
        schema,
        provision['entitlementId'] as String,
        workOrderId: '80000000-0000-4000-8006-000000000004',
        assignmentRevision: 1,
      );
      final answers = validate(
        schema,
        decodeAnswers(examples['S4'] as Json),
      ).values;
      draft = await repo.save(draft.id, answers);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6nCgAAAAASUVORK5CYII=',
      );
      List<Json> pictures() => [
        for (final s in ['test', 'blocker'])
          {
            'id': const Uuid().v4(),
            'stage': s,
            'caption': 'SYNTHETIC NATIVE VERIFICATION',
            'mimeType': 'image/png',
            'data': base64Encode(bytes),
            'sha256': sha256.convert(bytes).toString(),
            'capturedAt': DateTime.now().toUtc().toIso8601String(),
            'synthetic': true,
          },
      ];
      await repo.saveEvidence(draft.id, pictures());
      const transcript =
          'ONT fitted. RX -30.2 dBm. Optical test failed. Service not live.';
      await repo.saveClosureCapture(draft.id, {
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'transcript': transcript,
        'transcriptHistory': [transcript],
        'candidates': literalClosureFacts(transcript),
      });
      draft = await repo.save(draft.id, {
        ...draft.values,
        'fibre_connected': const BoolAnswer(false),
      });
      expect(draft.values['optical_rx_dbm'], isNull);
      expect(draft.values['optical_test'], isNull);
      expect(
        (await repo.evidence(draft.id)).any((p) => p['stage'] == 'test'),
        isFalse,
      );
      expect(
        await repo.metadata('closure-evidence-history:${draft.id}'),
        isNotEmpty,
      );
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      draft = await repo.get(draft.id);
      draft = await repo.save(draft.id, {
        ...draft.values,
        'fibre_connected': const BoolAnswer(true),
      });
      expect(
        draft.values['optical_rx_dbm'],
        isNull,
        reason: 'Old readings must not silently return when a branch reopens.',
      );
      final location = ReportLocation(
        latitude: 51.4545,
        longitude: -2.5879,
        accuracyMeters: 10,
        capturedAt: DateTime.now().toUtc(),
        isMocked: true,
      );
      await expectLater(
        repo.confirm(draft.id, timezone: 'Europe/London', location: location),
        throwsStateError,
      );
      draft = await repo.save(draft.id, answers, source: 'manual');
      await repo.saveEvidence(draft.id, pictures());
      final frozen = await repo.confirm(
        draft.id,
        timezone: 'Europe/London',
        location: location,
      );
      final payload = jsonDecode(frozen.frozen!) as Json,
          review = payload['closureReview'] as Json;
      expect(review['humanConfirmed'], isTrue);
      expect((review['questionStates'] as Json)['S4-Q17'], 'VERIFIED');
      expect(
        (review['candidates'] as List).every((c) => c['questionId'] is String),
        isTrue,
      );
      expect(
        (review['branchEvents'] as List).any(
          (e) => e['to'] == 'NOT_APPLICABLE',
        ),
        isTrue,
      );
      expect(payload['values']['claimed_outcome'], 'partial');
      expect(payload['values']['service_live'], isFalse);
      await expectLater(
        repo.saveClosureCapture(draft.id, {}),
        throwsStateError,
      );
      await expectLater(repo.saveEvidence(draft.id, []), throwsStateError);
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      final reopened = await repo.get(draft.id);
      expect(reopened.frozen, frozen.frozen);
      expect(
        reopened.payloadHash,
        sha256.convert(utf8.encode(reopened.frozen!)).toString(),
      );
      expect(reopened.state, ReportState.queued);
    },
  );
  testWidgets(
    'native speech then selected option advance automatically with preserved sources and no microphone recording',
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
          'appVersion': 'closure-voice-native-check',
          'osVersion': 'Synthetic simulator voice verification',
        },
      );
      final form = FormDefinition.fromJson(provision['template'] as Json);
      final manifest = (provision['manifest'] as Json)['assets'] as Json;
      final directory = await AssetInstaller(api).install(manifest, (_) {});
      final engine = FieldVoice();
      await engine.load(directory);
      addTearDown(engine.unload);
      final field = form.fields.firstWhere((f) => f.id == 'identity_verified');
      final access = form.fields.firstWhere((f) => f.id == 'access_permission');
      final questionVoice = QuestionVoice(engine);
      final prepared = await questionVoice.synthesize(
        closureSpokenQuestion(field),
      );
      expect(prepared.samples, isNotEmpty);
      expect(questionVoice.description, contains('prepared'));
      final answerPcm = generated.resample(
        await engine.synthesize('Yes, I did.'),
      );
      final audio = AutomaticAnswerAudio();
      final results = <ClosureVoiceAnswer>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ClosureVoiceAssistant(
            jobTitle: 'S1 · Standard FTTP provision',
            announceSavedAnswers: false,
            recognizer: engine,
            synthesizer: questionVoice,
            audio: audio,
            assertAccess: () async {},
            needsNarrative: false,
            nextQuestion: (_) => results.isEmpty
                ? field
                : results.length == 1
                ? access
                : null,
            proposeNarrative: (_, _) async => [],
            keepNarrative: (_, _, _) async {},
            keepAnswer: (_, answer) async {
              results.add(answer);
            },
            cancelInference: engine.cancel,
          ),
        ),
      );
      // The welcome and first question start automatically. No microphone is
      // opened by this replay adapter; only generated answer PCM is supplied.
      final wait = Stopwatch()..start();
      while (audio.feed == null && wait.elapsed < const Duration(seconds: 90)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(audio.openedAfterQuestion, isTrue);
      expect(results, isEmpty);
      audio.feed!(answerPcm);
      while ((results.isEmpty ||
              find.text(closureSpokenQuestion(access)).evaluate().isEmpty) &&
          wait.elapsed < const Duration(seconds: 120)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(results, hasLength(1));
      expect(results.single.answer?.toJson(), true);
      expect(results.single.transcript, isNotEmpty);
      expect(results.single.sourceType, 'speech');
      // The first answer used no taps. The next answer uses one optional
      // selection, with neither a Confirm nor Next tap afterwards.
      await tester.ensureVisible(find.text('No'));
      await tester.tap(find.text('No'));
      while ((results.length < 2 ||
              find.text('Open my draft').evaluate().isEmpty) &&
          wait.elapsed < const Duration(seconds: 150)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(results, hasLength(2));
      expect(results.last.answer?.toJson(), false);
      expect(results.last.sourceType, 'manual');
      expect(results.last.inputMethod, 'option');
      expect(find.text('Open my draft'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Native voice check complete')),
        ),
      );
      await tester.pumpAndSettle();
    },
  );
}
