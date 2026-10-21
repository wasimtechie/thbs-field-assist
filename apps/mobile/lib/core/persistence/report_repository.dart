import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../contracts.dart';

class SecureReportRepository {
  SecureReportRepository(this.secrets);
  final FlutterSecureStorage secrets;
  Database? _database;
  String? _owner;
  String? cipherVersion;
  Database get database =>
      _database ?? (throw StateError('Unlock the account first.'));
  Future<void> checkStorage({int minimumBytes = 2097152}) async {
    final bytes = await const MethodChannel(
      'field_assist/security',
    ).invokeMethod<int>('availableStorage');
    if (bytes == null || bytes < minimumBytes) {
      throw StateError(
        'Not enough free device storage. Free some space and retry. Existing reports are retained; nothing new has been marked saved.',
      );
    }
  }

  Future<void> open(String owner, {required bool authorizePresence}) async {
    await checkStorage(minimumBytes: 10485760);
    if (authorizePresence) {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported() ||
          !await auth.authenticate(
            localizedReason: 'Unlock your encrypted Field Assist reports',
            biometricOnly: false,
          )) {
        throw StateError(
          'Device authentication is required. Enable a device passcode or biometrics, then retry.',
        );
      }
    }
    await close();
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'accounts', owner));
    await dir.create(recursive: true);
    if (Platform.isIOS) {
      await const MethodChannel(
        'field_assist/security',
      ).invokeMethod<void>('excludeFromBackup', {'path': dir.path});
    }
    final file = p.join(dir.path, 'reports.db');
    final keyName = 'database-key:$owner';
    var key = await secrets.read(key: keyName);
    if (key == null) {
      if (await File(file).exists()) {
        throw StateError(
          'Your encrypted reports exist, but their secure key is unavailable. Restore the original device credentials; no data has been replaced.',
        );
      }
      key = base64Url.encode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      );
      await secrets.write(key: keyName, value: key);
    }
    final opened = await openDatabase(
      file,
      password: key,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys=ON');
      },
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE collaboration_outbox (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, kind TEXT NOT NULL, route TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, error TEXT, blocked INTEGER NOT NULL DEFAULT 0)',
        );
        await db.execute(
          'CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE reports (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, schema_json TEXT NOT NULL, values_json TEXT NOT NULL, provenance_json TEXT NOT NULL, state TEXT NOT NULL, revision INTEGER NOT NULL, entitlement_id TEXT NOT NULL, updated_at TEXT NOT NULL, frozen TEXT, payload_hash TEXT, attempt_id TEXT, receipt_json TEXT, last_error TEXT, retry_count INTEGER NOT NULL DEFAULT 0, next_retry_at TEXT, work_order_id TEXT, work_order_assignment_revision INTEGER)',
        );
        await db.execute(
          'CREATE INDEX report_state ON reports(owner_id,state,updated_at)',
        );
        await db.execute(
          "CREATE UNIQUE INDEX active_work_order ON reports(owner_id,work_order_id) WHERE work_order_id IS NOT NULL AND state != 'accepted'",
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE reports ADD COLUMN work_order_id TEXT');
          await db.execute(
            "CREATE UNIQUE INDEX active_work_order ON reports(owner_id,work_order_id) WHERE work_order_id IS NOT NULL AND state != 'accepted'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE reports ADD COLUMN work_order_assignment_revision INTEGER',
          );
          await db.execute(
            'CREATE TABLE collaboration_outbox (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, kind TEXT NOT NULL, route TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, error TEXT, blocked INTEGER NOT NULL DEFAULT 0)',
          );
        }
      },
    );
    final result = await opened.rawQuery('PRAGMA cipher_version');
    cipherVersion = result.isNotEmpty
        ? result.first.values.firstOrNull?.toString()
        : null;
    if (cipherVersion == null || cipherVersion!.isEmpty) {
      await opened.close();
      throw StateError(
        'SQLCipher is unavailable. Plaintext storage is not allowed.',
      );
    }
    _database = opened;
    _owner = owner;
    await database.update(
      'reports',
      {
        'state': 'queued',
        'last_error':
            'Connection interrupted. Retrying the same frozen payload.',
      },
      where: 'owner_id = ? AND state = ?',
      whereArgs: [owner, 'syncing'],
    );
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _owner = null;
    if (db != null) await db.close();
  }

  Future<void> setMetadata(String key, Object value) async {
    await database.insert('metadata', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Object?> metadata(String key) async {
    final rows = await database.query(
      'metadata',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<void> activateVoicePackage(String directory, Json manifest) async {
    await database.transaction((tx) async {
      for (final entry in {
        'voice-directory': directory,
        'asset-manifest': manifest,
      }.entries) {
        await tx.insert('metadata', {
          'key': entry.key,
          'value': jsonEncode(entry.value),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await tx.delete(
        'metadata',
        where: 'key = ?',
        whereArgs: ['pending-voice-package'],
      );
    });
  }

  Future<LocalReport> create(
    FormDefinition schema,
    String entitlementId, {
    String? workOrderId,
    int? assignmentRevision,
  }) async {
    await checkStorage();
    schema.verifyHash();
    final id = const Uuid().v4();
    await database.insert('reports', {
      'id': id,
      'work_order_id': workOrderId,
      'work_order_assignment_revision': assignmentRevision,
      'owner_id': _owner!,
      'schema_json': jsonEncode(schema.source),
      'values_json': '{}',
      'provenance_json': '{}',
      'state': 'draft',
      'revision': 1,
      'entitlement_id': entitlementId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'retry_count': 0,
    });
    return get(id);
  }

  Future<LocalReport> get(String id) async {
    final rows = await database.query(
      'reports',
      where: 'id = ? AND owner_id = ?',
      whereArgs: [id, _owner],
    );
    if (rows.isEmpty) throw StateError('Report unavailable for this account.');
    return LocalReport.fromRow(rows.first);
  }

  Future<List<LocalReport>> list() async => (await database.query(
    'reports',
    where: 'owner_id = ?',
    whereArgs: [_owner],
    orderBy: 'updated_at DESC, id DESC',
  )).map(LocalReport.fromRow).toList();
  Future<LocalReport> save(
    String id,
    Answers values, {
    String source = 'manual',
  }) async {
    await checkStorage();
    await database.transaction((tx) async {
      final rows = await tx.query(
        'reports',
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, _owner],
      );
      if (rows.isEmpty) throw StateError('Report unavailable.');
      final current = LocalReport.fromRow(rows.first);
      if (current.state != ReportState.draft) {
        throw StateError('Queued and accepted reports cannot be edited.');
      }
      final history = <String, dynamic>{...current.provenance};
      for (final entry in values.entries) {
        if (jsonEncode(entry.value?.toJson()) ==
            jsonEncode(current.values[entry.key]?.toJson())) {
          continue;
        }
        final prior = (history[entry.key] as List?) ?? [];
        history[entry.key] = [
          ...prior,
          {
            'source': source,
            'prior': current.values[entry.key]?.toJson(),
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        ].reversed.take(10).toList().reversed.toList();
      }
      await tx.update(
        'reports',
        {
          'values_json': jsonEncode(encodeAnswers(values)),
          'provenance_json': jsonEncode(history),
          'revision': current.revision + 1,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND owner_id = ? AND state = ?',
        whereArgs: [id, _owner, 'draft'],
      );
    });
    return get(id);
  }

  Future<LocalReport> confirm(
    String id, {
    required String timezone,
    required ReportLocation location,
  }) async {
    await checkStorage();
    await database.transaction((tx) async {
      final rows = await tx.query(
        'reports',
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, _owner],
      );
      if (rows.isEmpty) throw StateError('Report unavailable.');
      final report = LocalReport.fromRow(rows.first);
      if (report.state != ReportState.draft) {
        throw StateError('This report is already confirmed.');
      }
      final result = validate(report.schema, report.values);
      if (!result.valid) {
        throw StateError(
          'Review the required or invalid fields before confirming.',
        );
      }
      final attempt = const Uuid().v4();
      location.requireFresh(DateTime.now().toUtc());
      final frozen = jsonEncode({
        'clientReportId': report.id,
        'submissionAttemptId': attempt,
        'revision': report.revision,
        'templateId': report.schema.templateId,
        'versionId': report.schema.versionId,
        'schemaHash': report.schema.hash,
        'entitlementId': report.entitlementId,
        'values': encodeAnswers(result.values),
        'confirmedAt': DateTime.now().toUtc().toIso8601String(),
        'originatingTimezone': timezone,
        'location': location.toJson(),
        if (report.workOrderId != null) 'workOrderId': report.workOrderId,
        if (report.workOrderAssignmentRevision != null)
          'workOrderAssignmentRevision': report.workOrderAssignmentRevision,
      });
      await tx.update(
        'reports',
        {
          'state': 'queued',
          'frozen': frozen,
          'payload_hash': sha256.convert(utf8.encode(frozen)).toString(),
          'attempt_id': attempt,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND owner_id = ? AND state = ?',
        whereArgs: [id, _owner, 'draft'],
      );
    });
    return get(id);
  }

  Future<void> move(
    String id,
    String event, {
    Json? receipt,
    String? error,
    int? retries,
    DateTime? nextRetry,
  }) async {
    await database.transaction((tx) async {
      final rows = await tx.query(
        'reports',
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, _owner],
      );
      if (rows.isEmpty) throw StateError('Report unavailable.');
      final r = LocalReport.fromRow(rows.first);
      final state = transition(r.state, event);
      if (state == ReportState.accepted && receipt == null) {
        throw StateError('A server receipt is required.');
      }
      await tx.update(
        'reports',
        {
          'state': stateName(state),
          'last_error': error,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          if (receipt != null) 'receipt_json': jsonEncode(receipt),
          'retry_count': ?retries,
          'next_retry_at': nextRetry?.toUtc().toIso8601String(),
          if (state == ReportState.draft) 'frozen': null,
          if (state == ReportState.draft) 'payload_hash': null,
          if (state == ReportState.draft) 'attempt_id': null,
        },
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, _owner],
      );
    });
  }
}
