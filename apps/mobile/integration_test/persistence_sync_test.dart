import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/sync/sync_service.dart';
import 'package:field_assist/features/sync/outbox_pump.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native encrypted recovery and real lost-response retry',
    (tester) async {
      const email = String.fromEnvironment('TEST_ENGINEER_EMAIL');
      const password = String.fromEnvironment('TEST_ENGINEER_PASSWORD');
      expect(email, isNotEmpty);
      expect(password, isNotEmpty);
      final api = ApiClient();
      final login = await api.send(
        'auth/login',
        method: 'POST',
        body: {'email': email, 'password': password, 'audience': 'mobile'},
      );
      api.token = login['token'] as String;
      final owner = (login['user'] as Json)['id'] as String;
      final provision = await api.send(
        'devices/provision',
        method: 'POST',
        body: {
          'deviceId': const Uuid().v4(),
          'platform': Platform.isIOS ? 'ios' : 'android',
          'appVersion': 'persistence-integration',
          'osVersion': Platform.operatingSystemVersion,
          'model':
              'Automated repository integration; not physical-device evidence',
        },
      );
      final schema = FormDefinition.fromJson(provision['template'] as Json);
      schema.verifyHash();
      const secrets = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      );
      final repository = SecureReportRepository(secrets);
      addTearDown(repository.close);
      // This test targets native storage and delivery. It deliberately does not
      // certify OS user presence, UI entry, process-kill recovery, or airplane mode.
      // Interactive presence remains enabled in every production app open call.
      await repository.open(owner, authorizePresence: false);
      final cipher = repository.cipherVersion;
      expect(cipher, isNotEmpty);
      final draft = await repository.create(
        schema,
        provision['entitlementId'] as String,
      );
      final values = decodeAnswers({
        'installation_outcome': 'partial',
        'work_performed':
            'Synthetic simulator integration: installed twelve metres; follow-up required.',
        'cable_installed': {'amount': 12, 'unit': 'm'},
        'connectivity_test': 'not_tested',
        'exception_reason':
            'Synthetic integration: connection awaiting a follow-up visit.',
      });
      await repository.save(draft.id, values);
      await repository.close();
      await repository.open(owner, authorizePresence: false);
      expect(
        encodeAnswers((await repository.get(draft.id)).values),
        encodeAnswers(values),
      );
      final frozen = await repository.confirm(
        draft.id,
        timezone: 'Asia/Kolkata',
        location: ReportLocation(
          latitude: 12.9716,
          longitude: 77.5946,
          accuracyMeters: 10,
          capturedAt: DateTime.now().toUtc(),
          isMocked: true,
        ),
      );
      expect(frozen.state, ReportState.queued);
      await repository.move(draft.id, 'upload');
      final accepted = await api.send(
        'submissions',
        method: 'POST',
        body: frozen.frozen,
        headers: {'X-Payload-SHA256': frozen.payloadHash!},
      );
      final firstReceipt = accepted['receipt'] as Json;
      // Intentionally omit persisting this response to emulate a lost receipt.
      await repository.close();
      await repository.open(owner, authorizePresence: false);
      final recovered = await repository.get(draft.id);
      expect(recovered.state, ReportState.queued);
      expect(recovered.frozen, frozen.frozen);
      expect(recovered.payloadHash, frozen.payloadHash);
      expect(recovered.location!.toJson(), frozen.location!.toJson());
      var backendReachable = false, queuedWork = true;
      var retryClock = DateTime.now();
      final offlineAttempt = Completer<void>(),
          automaticReceipt = Completer<void>();
      final service = SyncService(api, repository);
      final pump = OutboxPump(
        interval: const Duration(
          milliseconds: 100,
        ), // Fast clock only in this test.
        now: () => retryClock,
        hasWork: () => queuedWork,
        send: () async {
          if (!backendReachable) {
            if (!offlineAttempt.isCompleted) offlineAttempt.complete();
            return false; // Simulated outage; no OS/network claim.
          }
          await service.run();
          queuedWork =
              (await repository.get(draft.id)).state == ReportState.queued;
          if (!queuedWork && !automaticReceipt.isCompleted) {
            automaticReceipt.complete();
          }
          return service.lastError == null;
        },
      );
      addTearDown(pump.stop);
      pump.start();
      await offlineAttempt.future;
      expect((await repository.get(draft.id)).state, ReportState.queued);
      backendReachable = true;
      retryClock = retryClock.add(const Duration(seconds: 5));
      await automaticReceipt.future.timeout(const Duration(seconds: 30));
      pump.stop();
      final delivered = await repository.get(draft.id);
      expect(
        delivered.state,
        ReportState.accepted,
        reason: delivered.lastError,
      );
      expect(delivered.receipt!['id'], firstReceipt['id']);
      await repository.close();
      await repository.open(owner, authorizePresence: false);
      expect(
        (await repository.get(draft.id)).receipt!['id'],
        firstReceipt['id'],
      );
      final root = await getApplicationSupportDirectory();
      final header = await File(
        p.join(root.path, 'accounts', owner, 'reports.db'),
      ).openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
      expect(header, isNot(utf8.encode('SQLite format 3\u0000')));
      await repository.close();
      await repository.open(const Uuid().v4(), authorizePresence: false);
      await expectLater(repository.get(draft.id), throwsStateError);
      binding.reportData = {
        'scope':
            'Native storage and real HTTP on simulator; presence/UI/airplane-mode excluded',
        'sqlCipher': cipher,
        'clientReportId': draft.id,
        'receiptId': firstReceipt['id'],
        'payloadHash': frozen.payloadHash,
        'draftReopen': true,
        'interruptedUploadRecovered': true,
        'frozenBytesPreserved': true,
        'stableReceipt': true,
        'foregroundOutboxRetry':
            'timer-driven recovery with simulated reachability change and real HTTP retry',
        'encryptedHeader': true,
        'ownerNamespaceIsolation': true,
      };
      debugPrint(
        'SIMULATOR_PERSISTENCE_EVIDENCE ${jsonEncode(binding.reportData)}',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
