import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';

class OfflineApi extends ApiClient {
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async => throw const ServiceFailure(
    'TRANSPORT_ERROR',
    'Synthetic offline transport',
    retryable: true,
  );
}

class LostMessageResponseApi extends ApiClient {
  bool lose = true;
  final order = <String>[];
  String? savedMessageId;
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    order.add(route);
    final r = await super.send(
      route,
      method: method,
      body: body,
      headers: headers,
    );
    if (lose && route.endsWith('/messages') && method == 'POST') {
      lose = false;
      savedMessageId = r['id'] as String;
      throw const ServiceFailure(
        'TRANSPORT_ERROR',
        'Synthetic lost response after server commit',
        retryable: true,
      );
    }
    return r;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native encrypted messages recover and retries preserve one server message',
    (tester) async {
      final owner = 'native-collaboration-${const Uuid().v4()}',
          other = 'native-other-${const Uuid().v4()}',
          jobId = const String.fromEnvironment('TEST_COLLAB_JOB_ID'),
          conversationId = const String.fromEnvironment(
            'TEST_COLLAB_CONVERSATION_ID',
          );
      expect(jobId, isNotEmpty);
      expect(conversationId, isNotEmpty);
      final form = FormDefinition.fromJson(
            jsonDecode(const String.fromEnvironment('TEST_COLLAB_FORM'))
                as Json,
          ),
          key = const Uuid().v4() + const Uuid().v4();
      const secrets = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      );
      await secrets.write(key: 'database-key:$owner', value: key);
      final root = await getApplicationSupportDirectory(),
          folder = Directory(p.join(root.path, 'accounts', owner));
      await folder.create(recursive: true);
      final file = p.join(folder.path, 'reports.db');
      // Construct the previous v2 schema to exercise preservation of existing drafts.
      final old = await openDatabase(
        file,
        password: key,
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE metadata (key TEXT PRIMARY KEY,value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE reports (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, schema_json TEXT NOT NULL, values_json TEXT NOT NULL, provenance_json TEXT NOT NULL, state TEXT NOT NULL, revision INTEGER NOT NULL, entitlement_id TEXT NOT NULL, updated_at TEXT NOT NULL, frozen TEXT, payload_hash TEXT, attempt_id TEXT, receipt_json TEXT, last_error TEXT, retry_count INTEGER NOT NULL DEFAULT 0, next_retry_at TEXT, work_order_id TEXT)',
          );
          await db.execute(
            "CREATE UNIQUE INDEX active_work_order ON reports(owner_id,work_order_id) WHERE work_order_id IS NOT NULL AND state != 'accepted'",
          );
        },
      );
      final legacyId = const Uuid().v4();
      await old.insert('reports', {
        'id': legacyId,
        'owner_id': owner,
        'schema_json': jsonEncode(form.source),
        'values_json': jsonEncode({
          'work_performed': 'Existing synthetic draft retained.',
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
      await repo.open(owner, authorizePresence: false);
      expect(
        (await repo.get(legacyId)).values['work_performed']?.toJson(),
        'Existing synthetic draft retained.',
      );
      final responseId = const Uuid().v4(),
          messageId = const Uuid().v4(),
          offline = CollaborationService(OfflineApi(), repo);
      await offline.enqueue(owner, 'response', 'work-orders/$jobId/response', {
        'requestId': responseId,
        'assignmentRevision': 1,
        'decision': 'accepted',
        'note': 'Synthetic native proof',
      }, id: responseId);
      await offline
          .enqueue(owner, 'message', 'conversations/$conversationId/messages', {
            'clientMessageId': messageId,
            'text': 'Synthetic native proof: please confirm site access.',
          }, id: messageId);
      expect(await offline.flush(isCurrent: () => true), false);
      expect((await offline.pending()).length, 2);
      final report = await repo.create(
        form,
        const String.fromEnvironment('TEST_COLLAB_ENTITLEMENT'),
        workOrderId: jobId,
        assignmentRevision: 1,
      );
      await repo.save(
        report.id,
        decodeAnswers({
          'installation_outcome': 'partial',
          'work_performed': 'Synthetic simulator persistence proof only.',
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
      expect(await offline.canUpload(frozen), false);
      expect(
        (jsonDecode(frozen.frozen!) as Json)['workOrderAssignmentRevision'],
        1,
      );
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      final recovered = await repo.get(report.id);
      expect(recovered.frozen, frozen.frozen);
      expect(recovered.payloadHash, frozen.payloadHash);
      expect((await offline.pending()).length, 2);
      final live = LostMessageResponseApi()
            ..token = const String.fromEnvironment('TEST_COLLAB_TOKEN'),
          service = CollaborationService(live, repo);
      expect(await service.flush(isCurrent: () => true), false);
      expect(live.order.first, 'work-orders/$jobId/response');
      expect((await service.pending()).single['id'], messageId);
      expect(await service.canUpload(recovered), true);
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      expect((await service.pending()).single['id'], messageId);
      expect(await service.flush(isCurrent: () => true), true);
      expect(await service.pending(), isEmpty);
      final server = await live.send('conversations/$conversationId/messages');
      final same = (server['items'] as List)
          .where((m) => m['clientMessageId'] == messageId)
          .toList();
      expect(same.length, 1);
      expect(same.single['id'], live.savedMessageId);
      expect(
        (await service.cachedThread(conversationId))!['items'],
        isNotEmpty,
      );
      final receipt = await live.send(
        'submissions',
        method: 'POST',
        body: recovered.frozen,
        headers: {'X-Payload-SHA256': recovered.payloadHash!},
      );
      expect(receipt['receipt'], isNotNull);
      final lead = ApiClient(),
          reply = await lead.send(
            'conversations/$conversationId/messages',
            method: 'POST',
            body: {
              'clientMessageId': const Uuid().v4(),
              'text': 'Synthetic native lead reply: use the east gate.',
            },
            headers: {
              'Cookie': const String.fromEnvironment('TEST_COLLAB_LEAD_COOKIE'),
              'Origin': const String.fromEnvironment('TEST_COLLAB_ORIGIN'),
            },
          );
      final refreshed = await service.messages(
        conversationId,
        isCurrent: () => true,
      );
      expect(
        (refreshed['items'] as List).any((m) => m['id'] == reply['id']),
        true,
      );
      await repo.close();
      await repo.open(other, authorizePresence: false);
      expect(await service.pending(), isEmpty);
      expect(await service.cachedThread(conversationId), isNull);
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      expect((await repo.get(report.id)).frozen, frozen.frozen);
      expect(
        (await service.cachedThread(conversationId))!['items'],
        isNotEmpty,
      );
      final bytes = await File(
        file,
      ).openRead(0, 16).fold<List<int>>([], (a, b) => a..addAll(b));
      expect(bytes, isNot(utf8.encode('SQLite format 3\u0000')));
      expect(
        sha256.convert(utf8.encode(frozen.frozen!)).toString(),
        recovered.payloadHash,
      );
      binding.reportData = {
        'scope':
            'Real iPhone simulator SQLCipher v2→v3 migration and local HTTP. Simulated unreachable transport and lost response; no OS airplane-mode, hardware GPS or background-push claim.',
        'legacyDraftPreserved': true,
        'queuedMessagesRecovered': true,
        'assignmentBeforeReport': true,
        'lostMessageResponseDeduplicated': true,
        'leadReplyReceived': true,
        'reportFrozenBytesPreserved': true,
        'accountIsolation': true,
        'encryptedHeader': true,
      };
      // No keys, session tokens or private test configuration are printed.
      // ignore: avoid_print
      print('COLLABORATION_NATIVE_EVIDENCE ${jsonEncode(binding.reportData)}');
    },
  );
}
