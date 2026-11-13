import '../../features/fttp/fttp_workflow.dart';
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
      values = {...values};
      if (current.schema.source['closurePolicy'] != null) {
        final priorEvents = await tx.query(
          'metadata',
          where: 'key = ?',
          whereArgs: ['closure-branches:$id'],
        );
        final events = priorEvents.isEmpty
            ? <dynamic>[]
            : jsonDecode(priorEvents.first['value'] as String) as List;
        final archivedStages = <String>{};
        for (final field in current.schema.fields) {
          final wasVisible = current.schema.visible(field, current.values);
          final nowVisible = current.schema.visible(field, values);
          if (wasVisible != nowVisible) {
            events.add({
              'at': DateTime.now().toUtc().toIso8601String(),
              'fieldId': field.id,
              'from': wasVisible
                  ? (missing(current.values[field.id])
                        ? 'ACTIVE_UNANSWERED'
                        : 'ANSWERED_UNVERIFIED')
                  : 'NOT_SHOWN',
              'to': nowVisible ? 'ACTIVE_UNANSWERED' : 'NOT_APPLICABLE',
            });
          }
          if (!nowVisible && !missing(values[field.id])) {
            if (field.source['capture'] == 'evidence') {
              archivedStages.add(field.source['evidenceStage'] as String);
            }
            values[field.id] = null;
          }
        }
        if (archivedStages.isNotEmpty) {
          final photoRows = await tx.query(
            'metadata',
            where: 'key = ?',
            whereArgs: ['evidence:$id'],
          );
          final allPhotos = photoRows.isEmpty
              ? <dynamic>[]
              : jsonDecode(photoRows.first['value'] as String) as List;
          final historyRows = await tx.query(
            'metadata',
            where: 'key = ?',
            whereArgs: ['closure-evidence-history:$id'],
          );
          final priorPhotos = historyRows.isEmpty
              ? <dynamic>[]
              : jsonDecode(historyRows.first['value'] as String) as List;
          await tx.insert('metadata', {
            'key': 'closure-evidence-history:$id',
            'value': jsonEncode(
              [
                ...priorPhotos,
                ...allPhotos.where((p) => archivedStages.contains(p['stage'])),
              ].reversed.take(8).toList().reversed.toList(),
            ),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await tx.insert('metadata', {
            'key': 'evidence:$id',
            'value': jsonEncode(
              allPhotos
                  .where((p) => !archivedStages.contains(p['stage']))
                  .toList(),
            ),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await tx.insert('metadata', {
          'key': 'closure-branches:$id',
          'value': jsonEncode(
            events.reversed.take(200).toList().reversed.toList(),
          ),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<void> saveClosureCapture(String id, Json capture) async {
    await checkStorage();
    if (utf8.encode(jsonEncode(capture)).length > 100000) {
      throw StateError(
        'Keep the narrative and candidate history under 100 KB.',
      );
    }
    await database.transaction((tx) async {
      final rows = await tx.query(
        'reports',
        where: 'id = ? AND owner_id = ? AND state = ?',
        whereArgs: [id, _owner, 'draft'],
      );
      if (rows.isEmpty ||
          LocalReport.fromRow(rows.first).schema.source['closurePolicy'] ==
              null) {
        throw StateError(
          'Only an editable closure draft can change its source record.',
        );
      }
      await tx.insert('metadata', {
        'key': 'closure-capture:$id',
        'value': jsonEncode(capture),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Json>> evidence(String id) async {
    await get(id);
    return ((await metadata('evidence:$id')) as List? ?? []).cast<Json>();
  }

  Future<void> saveEvidence(String id, List<Json> items) async {
    await checkStorage();
    if (items.length > 4) {
      throw StateError('Keep at most four evidence images.');
    }
    for (final item in items) {
      final bytes = base64Decode(item['data'] as String);
      if (bytes.length > 120000 ||
          sha256.convert(bytes).toString() != item['sha256']) {
        throw StateError('Evidence must be hash-verified and at most 120 KB.');
      }
    }
    await database.transaction((tx) async {
      final rows = await tx.query(
        'reports',
        where: 'id = ? AND owner_id = ?',
        whereArgs: [id, _owner],
      );
      if (rows.isEmpty || rows.first['state'] != 'draft') {
        throw StateError('Only an editable draft can change its evidence.');
      }
      await tx.insert('metadata', {
        'key': 'evidence:$id',
        'value': jsonEncode(items),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.rawUpdate(
        'UPDATE reports SET revision = revision + 1, updated_at = ? WHERE id = ? AND owner_id = ?',
        [DateTime.now().toUtc().toIso8601String(), id, _owner],
      );
    });
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
      if (report.schema.source['closurePolicy'] != null &&
          report.workOrderId == null) {
        throw StateError(
          'Link the closure draft to its assigned work order before confirmation.',
        );
      }
      final result = validate(report.schema, report.values);
      if (!result.valid) {
        throw StateError(
          'Review the required or invalid fields before confirming.',
        );
      }
      final evidenceRows = await tx.query(
        'metadata',
        where: 'key = ?',
        whereArgs: ['evidence:$id'],
      );
      final evidence = evidenceRows.isEmpty
          ? <Json>[]
          : (jsonDecode(evidenceRows.first['value'] as String) as List)
                .cast<Json>();
      final checks = fttpIssues(
        report.schema.templateId,
        report.values,
        evidence,
      );
      if (checks.isNotEmpty) throw StateError(checks.join(' '));
      final closure = checkClosure(
        report.schema.source,
        encodeAnswers(result.values),
        evidence,
      );
      if (closure.issues.isNotEmpty) throw StateError(closure.issues.join(' '));
      Json? closureReview;
      if (report.schema.source['closurePolicy'] case final Json policy) {
        final records = await tx.query(
          'metadata',
          where: 'key = ?',
          whereArgs: ['closure-capture:$id'],
        );
        final capture = records.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(records.first['value'] as String) as Json;
        final branchRows = await tx.query(
          'metadata',
          where: 'key = ?',
          whereArgs: ['closure-branches:$id'],
        );
        final branches = branchRows.isEmpty
            ? <dynamic>[]
            : jsonDecode(branchRows.first['value'] as String) as List;
        final now = DateTime.now().toUtc();
        final started =
            DateTime.tryParse(capture['startedAt'] as String? ?? '') ?? now;
        final rawValues = encodeAnswers(result.values);
        final activeBanks = <String>{rawValues['scenario'] as String};
        if (rawValues['scenario'] == 'S1' &&
            rawValues['route_obstructed'] == true) {
          activeBanks.add('S2');
        }
        if (rawValues['scenario'] == 'S2' &&
                rawValues['route_obstructed'] == false ||
            rawValues['scenario'] == 'S3' &&
                rawValues['alternative_authorised'] == true ||
            rawValues['scenario'] == 'S4' &&
                rawValues['service_live'] == true) {
          activeBanks.add('S1');
        }
        String questionFor(String fieldId) {
          final banks = (policy['banks'] as List).cast<Json>();
          for (final id in activeBanks) {
            final questions =
                banks.firstWhere((b) => b['id'] == id)['questions'] as List;
            for (final q in questions) {
              if (q['fieldId'] == fieldId) return q['questionId'] as String;
            }
          }
          return 'CONTROL_$fieldId';
        }

        closureReview = {
          'policyId': policy['id'],
          'policyVersion': policy['version'],
          'humanConfirmed': true,
          'transcript': capture['transcript'] ?? '',
          'transcriptHistory': capture['transcriptHistory'] ?? [],
          'candidates': [
            for (final c in (capture['candidates'] as List? ?? []))
              {
                ...c as Map,
                'questionId': questionFor(c['fieldId'] as String),
                'evidenceId': null,
                'verificationStatus': rawValues[c['fieldId']] == c['value']
                    ? 'accepted'
                    : 'rejected',
              },
          ],
          'questionStates': {
            for (final b in policy['banks'] as List)
              for (final q in b['questions'] as List)
                q['questionId']: !activeBanks.contains(b['id'])
                    ? 'NOT_SHOWN'
                    : report.schema.visible(
                        report.schema.fields.firstWhere(
                          (f) => f.id == q['fieldId'],
                        ),
                        result.values,
                      )
                    ? (rawValues[q['fieldId']] == null
                          ? 'ACTIVE_UNANSWERED'
                          : 'VERIFIED')
                    : branches.any(
                        (e) =>
                            e['fieldId'] == q['fieldId'] &&
                            e['to'] == 'NOT_APPLICABLE',
                      )
                    ? 'NOT_APPLICABLE'
                    : 'NOT_SHOWN',
          },
          'branchEvents': branches,
          'metrics': {
            'startedAt': started.toIso8601String(),
            'reviewedAt': now.toIso8601String(),
            'elapsedMs': now
                .difference(started)
                .inMilliseconds
                .clamp(0, 8640000000),
            'extractionMs': capture['extractionMs'] ?? 0,
            'promptsShown': capture['promptsShown'] ?? 0,
            'corrections': capture['corrections'] ?? 0,
          },
        };
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
        if (evidence.isNotEmpty) 'evidence': evidence,
        'closureReview': ?closureReview,
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
