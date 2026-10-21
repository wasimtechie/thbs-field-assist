import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/sync/sync_service.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';
import 'appearance_journey_test.dart' as fixture;

class Gate {
  bool current = true;
  int identity = 0, uploads = 0;
  String phase = '';
}

class GateApi extends ApiClient {
  GateApi(this.gate);
  final Gate gate;
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    if (route == 'me') {
      gate.identity++;
      if (gate.phase == 'identity') {
        gate.current = false;
      }
      return {};
    }
    if (route == 'submissions') {
      gate.uploads++;
      if (gate.phase == 'response') {
        gate.current = false;
      }
      return {
        'receipt': {'id': 'synthetic-receipt'},
      };
    }
    throw StateError('Unexpected request');
  }
}

class GateReports extends SecureReportRepository {
  GateReports(this.gate) : super(const FlutterSecureStorage());
  final Gate gate;
  int reads = 0;
  final events = <String>[];
  @override
  Future<List<LocalReport>> list() async {
    reads++;
    return [
      LocalReport(
        id: 'queued',
        ownerId: 'owner-a',
        schema: fixture.schema,
        values: {},
        state: ReportState.queued,
        revision: 1,
        entitlementId: 'lease',
        updatedAt: DateTime.now(),
        frozen: '{}',
        payloadHash: '0' * 64,
      ),
    ];
  }

  @override
  Future<void> move(
    String id,
    String event, {
    Json? receipt,
    String? error,
    int? retries,
    DateTime? nextRetry,
  }) async {
    events.add(event);
    if (event == 'upload' && gate.phase == 'upload') {
      gate.current = false;
    }
  }
}

class PendingGate extends CollaborationService {
  PendingGate() : super(ApiClient(), fixture.MemoryReports());
  final enqueued = Completer<void>(), done = Completer<String>();
  @override
  Future<String> enqueue(
    String owner,
    String kind,
    String route,
    Json payload, {
    String? id,
  }) async {
    enqueued.complete();
    return done.future;
  }

  @override
  Future<List<Json>> pending() async => [];
}

class SwitchingController extends fixture.DesignController {
  final delayed = PendingGate();
  @override
  CollaborationService get collaboration => delayed;
  void switchUser() {
    state = AppState(
      stage: AccessStage.ready,
      user: EngineerIdentity(
        id: 'next-owner',
        name: 'Next user',
        email: 'next@example.invalid',
        organizationId: 'test-org',
        typeId: fixture.schema.typeId,
        typeName: 'Fibre',
        assignmentRevision: 1,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'switching after identity check prevents reading another account database',
    () async {
      final g = Gate()..phase = 'identity',
          repo = GateReports(g),
          api = GateApi(g);
      expect(
        await SyncService(api, repo).run(isCurrent: () => g.current),
        false,
      );
      expect(repo.reads, 0);
      expect(g.uploads, 0);
    },
  );
  test(
    'switching after marking upload prevents a request with the next user token',
    () async {
      final g = Gate()..phase = 'upload',
          repo = GateReports(g),
          api = GateApi(g);
      expect(
        await SyncService(api, repo).run(isCurrent: () => g.current),
        false,
      );
      expect(g.uploads, 0);
      expect(repo.events, ['upload']);
    },
  );
  test(
    'a late upload reply cannot write its receipt into the next account',
    () async {
      final g = Gate()..phase = 'response',
          repo = GateReports(g),
          api = GateApi(g);
      expect(
        await SyncService(api, repo).run(isCurrent: () => g.current),
        false,
      );
      expect(g.uploads, 1);
      expect(repo.events, ['upload']);
    },
  );
  test(
    'the same unlocked owner still completes a normal frozen upload',
    () async {
      final g = Gate(), repo = GateReports(g), api = GateApi(g);
      expect(
        await SyncService(api, repo).run(isCurrent: () => g.current),
        true,
      );
      expect(repo.events, ['upload', 'receipt']);
    },
  );
  test(
    'a late local message commit cannot restore the previous user screen',
    () async {
      final c = ProviderContainer(
        overrides: [appProvider.overrideWith(SwitchingController.new)],
      );
      addTearDown(c.dispose);
      c.read(appProvider);
      final controller = c.read(appProvider.notifier) as SwitchingController,
          action = controller.sendMessage(
            'chat',
            'Synthetic old-account message',
          );
      await controller.delayed.enqueued.future;
      controller.switchUser();
      final result = expectLater(action, throwsStateError);
      controller.delayed.done.complete('saved-original-account');
      await result;
      expect(c.read(appProvider).user?.id, 'next-owner');
      expect(c.read(appProvider).collaboration.pending, isEmpty);
    },
  );
}
