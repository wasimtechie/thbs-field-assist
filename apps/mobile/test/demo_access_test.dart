import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/main.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/authentication/demo_access.dart';
import 'package:field_assist/features/offline_access/entitlement.dart';
import 'appearance_journey_test.dart' as fixture;

const configuredDemo = DemoAccess(
  requested: true,
  email: 'fibre@fieldassist.demo',
  password: 'synthetic-test-password',
);

EngineerIdentity engineer(String email) => EngineerIdentity(
  id: 'test-owner',
  name: 'Sam Fibre',
  email: email,
  organizationId: 'test-org',
  typeId: fixture.schema.typeId,
  typeName: 'Fibre engineer',
  assignmentRevision: 1,
);

class BootstrapProbe extends AppController {
  BootstrapProbe(this.config, {this.restoreWorks = true});
  final DemoAccess config;
  final bool restoreWorks;
  final completed = Completer<void>();
  final signedIn = <String>[];
  int restores = 0;
  @override
  DemoAccess get demoAccess => config;
  @override
  Future<void> bootstrap() async {
    await super.bootstrap();
    completed.complete();
  }

  @override
  Future<void> unlock() async {
    restores++;
    state = state.copy(
      stage: restoreWorks ? AccessStage.ready : AccessStage.locked,
    );
  }

  @override
  Future<void> signIn(String email, String password) async {
    signedIn.add(email);
    expect(password, config.password);
    state = state.copy(stage: AccessStage.ready, user: engineer(email));
  }
}

class OfflineBootstrapProbe extends BootstrapProbe {
  OfflineBootstrapProbe({this.expired = false})
    : super(
        const DemoAccess(
          requested: true,
          bundled: true,
          email: 'fibre@fieldassist.demo',
          password: 'synthetic-test-password',
        ),
      );
  final bool expired;
  int packageOpens = 0;
  @override
  Future<void> prepareBundledDemo() async {
    packageOpens++;
    state = state.copy(
      stage: expired ? AccessStage.provisioning : AccessStage.ready,
      error: expired ? 'The offline lease expired' : '',
    );
  }
}

class NonExpiringUpgradeProbe extends BootstrapProbe {
  NonExpiringUpgradeProbe({required this.alreadyNonExpiring})
    : super(
        const DemoAccess(
          requested: true,
          bundled: true,
          email: 'closure@fieldassist.demo',
          password: 'synthetic-test-password',
        ),
      );
  final bool alreadyNonExpiring;
  int packageOpens = 0;
  @override
  Future<OfflineLease> assertAccess() async => alreadyNonExpiring
      ? OfflineLease(
          id: fixture.lease.id,
          userId: fixture.lease.userId,
          organizationId: fixture.lease.organizationId,
          deviceId: fixture.lease.deviceId,
          typeId: fixture.lease.typeId,
          allowedTemplates: fixture.lease.allowedTemplates,
          assignmentRevision: fixture.lease.assignmentRevision,
          issuedAt: fixture.lease.issuedAt,
          expiresAt: null,
        )
      : fixture.lease;
  @override
  Future<void> prepareBundledDemo() async {
    packageOpens++;
    state = state.copy(stage: AccessStage.ready);
  }
}

class OpenReports extends fixture.MemoryReports {
  final presence = <bool>[];
  @override
  Future<void> open(String owner, {required bool authorizePresence}) async {
    presence.add(authorizePresence);
  }

  @override
  Future<void> close() async {}
  @override
  Future<Object?> metadata(String key) async => key == 'installed-form'
      ? {...fixture.schema.source, 'schemaHash': fixture.schema.calculatedHash}
      : null;
  @override
  Future<List<LocalReport>> list() async => [];
}

class SessionApi extends ApiClient {
  SessionApi() : super(baseUrl: 'https://localhost/api/v1/');
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async => {
    'user': engineer('fibre@fieldassist.demo').toJson(),
    'token': 'synthetic-token',
  };
}

class SessionProbe extends AppController {
  SessionProbe(this.config);
  final DemoAccess config;
  final records = OpenReports();
  final sessionApi = SessionApi();
  @override
  DemoAccess get demoAccess => config;
  @override
  SecureReportRepository get repository => records;
  @override
  ApiClient get api => sessionApi;
  @override
  AppState build() => super.build().copy(stage: AccessStage.signedOut);
  @override
  Future<void> bootstrap() async {}
  @override
  Future<void> provision() async {
    state = state.copy(stage: AccessStage.ready);
  }

  @override
  Future<OfflineLease> assertAccess() async => fixture.lease;
  @override
  void startCollaboration() {}
  @override
  Future<void> restoreCollaboration() async {}
}

class LifecycleProbe extends fixture.DesignController {
  LifecycleProbe(this.config);
  final DemoAccess config;
  int locks = 0;
  @override
  DemoAccess get demoAccess => config;
  @override
  Future<void> lock() async {
    locks++;
    state = state.copy(stage: AccessStage.locked);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'demo access is opt-in, synthetic-account-only and unavailable outside debug builds',
    () {
      expect(const DemoAccess.fromEnvironment().enabled, false);
      expect(configuredDemo.nonExpiringOfflineAccess, false);
      expect(
        const DemoAccess(
          requested: true,
          bundled: true,
          email: 'closure@fieldassist.demo',
          password: 'synthetic',
        ).nonExpiringOfflineAccess,
        true,
      );
      expect(
        const DemoAccess(
          requested: true,
          email: 'closure@fieldassist.demo',
          password: 'synthetic',
        ).nonExpiringOfflineAccess,
        false,
      );
      expect(DemoAccess.allowed(requested: true, debugBuild: false), false);
      expect(DemoAccess.allowed(requested: false, debugBuild: true), false);
      expect(configuredDemo.matches('fibre@fieldassist.demo'), true);
      expect(configuredDemo.matches('someone@example.com'), false);
      expect(
        const DemoAccess(
          requested: true,
          email: 'someone@example.com',
          password: 'test',
        ).configured,
        false,
      );
    },
  );

  for (final expired in [false, true]) {
    test(
      expired
          ? 'expired bundled access renews online while retaining local workspace'
          : 'fresh bundled demo opens without online sign-in',
      () async {
        final probe = OfflineBootstrapProbe(expired: expired),
            container = ProviderContainer(
              overrides: [appProvider.overrideWith(() => probe)],
            );
        addTearDown(container.dispose);
        container.read(appProvider);
        await probe.completed.future;
        expect(probe.packageOpens, 1);
        expect(probe.signedIn, expired ? ['fibre@fieldassist.demo'] : isEmpty);
        expect(container.read(appProvider).stage, AccessStage.ready);
      },
    );
  }

  for (final alreadyNonExpiring in [false, true]) {
    test(
      alreadyNonExpiring
          ? 'returning non-expiring demo restores without replacing its grant'
          : 'upgrading a timed demo installs bundled access before restoring',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'active-user': 'test-owner',
          'identity:test-owner': jsonEncode(
            engineer('closure@fieldassist.demo').toJson(),
          ),
        });
        final probe = NonExpiringUpgradeProbe(
          alreadyNonExpiring: alreadyNonExpiring,
        );
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(() => probe)],
        );
        addTearDown(container.dispose);
        container.read(appProvider);
        await probe.completed.future;
        expect(probe.packageOpens, alreadyNonExpiring ? 0 : 1);
        expect(probe.restores, alreadyNonExpiring ? 1 : 0);
        expect(probe.signedIn, isEmpty);
        expect(container.read(appProvider).stage, AccessStage.ready);
      },
    );
  }

  for (final item in [
    (
      'fresh demo',
      configuredDemo,
      null,
      true,
      0,
      ['fibre@fieldassist.demo'],
      AccessStage.ready,
    ),
    (
      'returning demo',
      configuredDemo,
      'fibre@fieldassist.demo',
      true,
      1,
      <String>[],
      AccessStage.ready,
    ),
    (
      'demo with expired restore',
      configuredDemo,
      'fibre@fieldassist.demo',
      false,
      1,
      ['fibre@fieldassist.demo'],
      AccessStage.ready,
    ),
    (
      'another account is not auto-unlocked',
      configuredDemo,
      'private@example.com',
      true,
      0,
      ['fibre@fieldassist.demo'],
      AccessStage.ready,
    ),
    (
      'normal fresh launch',
      const DemoAccess(),
      null,
      true,
      0,
      <String>[],
      AccessStage.signedOut,
    ),
    (
      'normal returning launch',
      const DemoAccess(),
      'fibre@fieldassist.demo',
      true,
      0,
      <String>[],
      AccessStage.locked,
    ),
  ]) {
    test(item.$1, () async {
      if (item.$3 != null) {
        FlutterSecureStorage.setMockInitialValues({
          'active-user': 'test-owner',
          'identity:test-owner': jsonEncode(engineer(item.$3!).toJson()),
          'device:test-owner': 'test-device',
          'token:test-owner': 'synthetic-token',
        });
      }
      final probe = BootstrapProbe(item.$2, restoreWorks: item.$4);
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(() => probe)],
      );
      addTearDown(container.dispose);
      container.read(appProvider);
      await probe.completed.future;
      expect(container.read(appProvider).stage, item.$7);
      expect(probe.restores, item.$5);
      expect(probe.signedIn, item.$6);
    });
  }

  testWidgets(
    'demo recovery enters the workspace without credential fields or a device prompt',
    (tester) async {
      final probe = SessionProbe(configuredDemo);
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(() => probe)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FieldAssistApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Open demo'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Unlock securely'), findsNothing);
      await tester.tap(find.text('Open demo'));
      await tester.pumpAndSettle();
      expect(container.read(appProvider).stage, AccessStage.ready);
      expect(probe.records.presence, [false]);
      expect(find.text('Open demo'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  for (final demo in [false, true]) {
    test(
      'device presence is ${demo ? 'skipped in the configured demo' : 'required normally'} for sign-in and restore',
      () async {
        final probe = SessionProbe(demo ? configuredDemo : const DemoAccess());
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(() => probe)],
        );
        addTearDown(container.dispose);
        container.read(appProvider);
        await Future<void>.delayed(Duration.zero);
        await probe.signIn('fibre@fieldassist.demo', 'synthetic-test-password');
        expect(probe.records.presence, [!demo]);
        await probe.unlock();
        expect(probe.records.presence, [!demo, !demo]);
        expect(
          container.read(appProvider).stage,
          AccessStage.ready,
          reason: container.read(appProvider).error,
        );
        await Future<void>.delayed(Duration.zero);
      },
    );

    testWidgets(
      'backgrounding ${demo ? 'keeps the demo open' : 'locks a normal workspace'}',
      (tester) async {
        final probe = LifecycleProbe(
          demo ? configuredDemo : const DemoAccess(),
        );
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(() => probe)],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const FieldAssistApp(),
          ),
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(probe.locks, demo ? 0 : 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
