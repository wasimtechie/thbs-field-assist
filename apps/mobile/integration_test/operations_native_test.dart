import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/persistence/report_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'v1 encrypted migration retains drafts, assignments and frozen job link',
    (tester) async {
      const encoded = String.fromEnvironment('CABLE_LABEL_TEST_SCHEMA_BASE64');
      final raw = jsonDecode(utf8.decode(base64Decode(encoded))) as Json;
      raw['schemaHash'] = FormDefinition.fromJson(raw).calculatedHash;
      raw['versionId'] = const Uuid().v4();
      raw['versionNumber'] = 4;
      final form = FormDefinition.fromJson(raw)..verifyHash();
      final owner = 'synthetic-job-migration-${const Uuid().v4()}',
          legacyId = const Uuid().v4(),
          jobId = const Uuid().v4();
      const secrets = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      );
      final key = const Uuid().v4() + const Uuid().v4();
      await secrets.write(key: 'database-key:$owner', value: key);
      final root = await getApplicationSupportDirectory(),
          dir = Directory(p.join(root.path, 'accounts', owner));
      await dir.create(recursive: true);
      final file = p.join(dir.path, 'reports.db');
      final old = await openDatabase(
        file,
        password: key,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE reports (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, schema_json TEXT NOT NULL, values_json TEXT NOT NULL, provenance_json TEXT NOT NULL, state TEXT NOT NULL, revision INTEGER NOT NULL, entitlement_id TEXT NOT NULL, updated_at TEXT NOT NULL, frozen TEXT, payload_hash TEXT, attempt_id TEXT, receipt_json TEXT, last_error TEXT, retry_count INTEGER NOT NULL DEFAULT 0, next_retry_at TEXT)',
          );
        },
      );
      await old.insert('reports', {
        'id': legacyId,
        'owner_id': owner,
        'schema_json': jsonEncode(form.source),
        'values_json': jsonEncode({
          'work_performed': 'Existing synthetic draft must survive.',
        }),
        'provenance_json': '{}',
        'state': 'draft',
        'revision': 1,
        'entitlement_id': const Uuid().v4(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      await old.close();
      final repo = SecureReportRepository(secrets);
      addTearDown(repo.close);
      // Test-only presence bypass. No production unlock, GPS or OS network claim.
      await repo.open(owner, authorizePresence: false);
      expect(
        (await repo.get(legacyId)).values['work_performed']?.toJson(),
        'Existing synthetic draft must survive.',
      );
      expect((await repo.get(legacyId)).workOrderId, isNull);
      final snapshot = {
        'workOrders': [
          {'id': jobId, 'instructions': 'Synthetic offline brief.'},
        ],
        'feedback': [
          {'decision': 'follow_up', 'note': 'Synthetic revisit instruction.'},
        ],
        'syncedAt': DateTime.now().toUtc().toIso8601String(),
      };
      await repo.setMetadata('operations-snapshot', snapshot);
      final report = await repo.create(
        form,
        const Uuid().v4(),
        workOrderId: jobId,
      );
      await expectLater(
        repo.create(form, const Uuid().v4(), workOrderId: jobId),
        throwsA(isA<DatabaseException>()),
      );
      await repo.save(
        report.id,
        decodeAnswers({
          'installation_outcome': 'partial',
          'work_performed': 'Synthetic migration verification only.',
          'cable_installed': {'amount': 12, 'unit': 'm'},
          'connectivity_test': 'not_tested',
          'exception_reason': 'Synthetic follow-up required.',
        }),
      );
      final frozen = await repo.confirm(
        report.id,
        timezone: 'UTC',
        location: ReportLocation(
          latitude: 12.9716,
          longitude: 77.5946,
          accuracyMeters: 10,
          capturedAt: DateTime.now().toUtc(),
          isMocked: true,
        ),
      );
      expect((jsonDecode(frozen.frozen!) as Json)['workOrderId'], jobId);
      await repo.move(report.id, 'upload');
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      final recovered = await repo.get(report.id);
      expect(recovered.state, ReportState.queued);
      expect(recovered.frozen, frozen.frozen);
      expect(recovered.payloadHash, frozen.payloadHash);
      expect(recovered.workOrderId, jobId);
      expect(await repo.metadata('operations-snapshot'), snapshot);
      final header = await File(
        file,
      ).openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
      expect(header, isNot(utf8.encode('SQLite format 3\u0000')));
      binding.reportData = {
        'scope':
            'Real native SQLCipher migration, encrypted cache and frozen-payload recovery on simulator; no physical location/network or OS-presence claim',
        'legacyDraftRetained': true,
        'encryptedSnapshotRecovered': true,
        'duplicateActiveJobBlocked': true,
        'workOrderLinkFrozen': true,
        'interruptedUploadRecovered': true,
        'frozenHashUnchanged': true,
        'encryptedHeader': true,
      };
      debugPrint(
        'OPERATIONS_NATIVE_EVIDENCE ${jsonEncode(binding.reportData)}',
      );
      await repo.close();
      await dir.delete(recursive: true);
      await secrets.delete(key: 'database-key:$owner');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
