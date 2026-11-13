import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/fttp/fttp_widgets.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'FTTP evidence survives encrypted reopen and freezes with the report',
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
          'email': 'fttp@fieldassist.demo',
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
          'appVersion': 'fttp-evidence-integration',
          'osVersion': 'Simulator storage verification',
        },
      );
      final schema = FormDefinition.fromJson(provision['template'] as Json);
      schema.verifyHash();
      final repo = SecureReportRepository(
        const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked_this_device,
          ),
        ),
      );
      // Isolated test namespace. This verifies storage, not OS user presence.
      final owner = 'fttp-native-check-${const Uuid().v4()}';
      await repo.open(owner, authorizePresence: false);
      addTearDown(repo.close);
      expect(repo.cipherVersion, isNotEmpty);
      final draft = await repo.create(
        schema,
        provision['entitlementId'] as String,
      );
      await repo.save(draft.id, fttpExample(false));
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6nCgAAAAASUVORK5CYII=',
      );
      final evidence = <Json>[
        for (final stage in ['before', 'installation', 'test'])
          {
            'id': const Uuid().v4(),
            'stage': stage,
            'caption': 'SYNTHETIC NATIVE TEST',
            'mimeType': 'image/png',
            'data': base64Encode(bytes),
            'sha256': sha256.convert(bytes).toString(),
            'capturedAt': DateTime.now().toUtc().toIso8601String(),
            'synthetic': true,
          },
      ];
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
      expect((await repo.get(draft.id)).state, ReportState.draft);
      await repo.saveEvidence(draft.id, evidence);
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      expect(await repo.evidence(draft.id), evidence);
      final frozen = await repo.confirm(
        draft.id,
        timezone: 'Europe/London',
        location: location,
      );
      expect((jsonDecode(frozen.frozen!) as Json)['evidence'], evidence);
      await expectLater(repo.saveEvidence(draft.id, []), throwsStateError);
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      final reopened = await repo.get(draft.id);
      expect(reopened.frozen, frozen.frozen);
      expect(reopened.payloadHash, frozen.payloadHash);
      expect(reopened.state, ReportState.queued);
    },
  );
}
