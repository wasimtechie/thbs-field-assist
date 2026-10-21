import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';

class OfflineTimeApi extends ApiClient {
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async => throw const ServiceFailure(
    'TRANSPORT',
    'Synthetic offline time proof',
    retryable: true,
  );
}

class LostTimeApi extends ApiClient {
  bool lose = true;
  final routes = <String>[];
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    routes.add(route);
    final result = await super.send(
      route,
      method: method,
      body: body,
      headers: headers,
    );
    if (lose && route.endsWith('/time-events')) {
      lose = false;
      throw const ServiceFailure(
        'TRANSPORT',
        'Synthetic lost time response after commit',
        retryable: true,
      );
    }
    return result;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native SQLCipher time queue reopens and lost arrival response creates one visit',
    (tester) async {
      final owner = 'native-time-${const Uuid().v4()}',
          jobId = const String.fromEnvironment('TEST_COLLAB_JOB_ID');
      expect(jobId, isNotEmpty);
      const secrets = FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.unlocked_this_device,
        ),
      );
      final repo = SecureReportRepository(secrets);
      addTearDown(repo.close);
      await repo.open(owner, authorizePresence: false);
      final offline = CollaborationService(OfflineTimeApi(), repo);
      await offline.enqueue(owner, 'response', 'work-orders/$jobId/response', {
        'requestId': const Uuid().v4(),
        'assignmentRevision': 1,
        'decision': 'accepted',
        'note': 'Synthetic time proof',
      });
      final visitId = const Uuid().v4(),
          base = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
      for (final pair in [
        ('check_in', 0),
        ('break_start', 2),
        ('break_end', 4),
        ('check_out', 9),
      ]) {
        final sequence =
                [
                  'check_in',
                  'break_start',
                  'break_end',
                  'check_out',
                ].indexOf(pair.$1) +
                1,
            at = base.add(Duration(minutes: pair.$2)).toIso8601String();
        await offline.enqueue(owner, 'time', 'work-orders/$jobId/time-events', {
          'requestId': const Uuid().v4(),
          'visitId': visitId,
          'assignmentRevision': 1,
          'sequence': sequence,
          'action': pair.$1,
          'occurredAt': at,
          'note': 'Synthetic native proof',
          'location': ?(['check_in', 'check_out'].contains(pair.$1)
              ? {
                  'latitude': 12.9716,
                  'longitude': 77.5946,
                  'accuracyMeters': 10,
                  'capturedAt': at,
                  'isMocked': true,
                }
              : null),
        });
      }
      expect(await offline.flush(isCurrent: () => true), false);
      expect((await offline.pending()).length, 5);
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      expect((await offline.pending()).length, 5);
      final api = LostTimeApi()
            ..token = const String.fromEnvironment('TEST_COLLAB_TOKEN'),
          service = CollaborationService(api, repo);
      expect(await service.flush(isCurrent: () => true), false);
      expect(api.routes.first, 'work-orders/$jobId/response');
      expect((await service.pending()).length, 4);
      await repo.close();
      await repo.open(owner, authorizePresence: false);
      expect(await service.flush(isCurrent: () => true), true);
      expect(await service.pending(), isEmpty);
      final result = await api.send('time-tracking?jobId=$jobId'),
          visits = (result['items'] as List).cast<Json>();
      expect(visits.length, 1);
      final visit = visits.single;
      expect((visit['events'] as List).length, 4);
      expect(visit['state'], 'closed');
      expect(visit['siteSeconds'], 540);
      expect(visit['workSeconds'], 420);
      expect(visit['breakSeconds'], 120);
      expect(
        (await repo.metadata('time-visits') as List).single['state'],
        'closed',
      );
      await api.send(
        'me/profile',
        method: 'PATCH',
        body: {'avatarId': 'vibrent_5'},
      );
      expect((await api.send('me'))['avatarId'], 'vibrent_5');
      await repo.close();
      final root = await getApplicationSupportDirectory(),
          file = File(p.join(root.path, 'accounts', owner, 'reports.db')),
          bytes = await file.open();
      final header = await bytes.read(16);
      await bytes.close();
      expect(
        utf8.decode(header, allowMalformed: true).startsWith('SQLite format 3'),
        false,
      );
      binding.reportData = {
        'workspace': {
          'scope':
              'Real iPhone simulator SQLCipher queue + local HTTP. Mocked synthetic action locations; no OS airplane-mode, GPS or closed-app push claim.',
          'timeQueueReopened': true,
          'acceptanceBeforeCheckIn': true,
          'lostArrivalReplyDeduplicated': true,
          'oneVisitFourImmutableActions': true,
          'workSeconds': 420,
          'breakSeconds': 120,
          'siteSeconds': 540,
          'profileAvatarSaved': true,
          'encryptedHeader': true,
        },
      };
    },
  );
}
