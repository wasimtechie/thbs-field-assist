import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/main.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/app/router.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/appearance.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/offline_access/entitlement.dart';

// Test-only fixtures. Never used by lib/main.dart or included in a shipped APK.
final schema = FormDefinition.fromJson(
  ((jsonDecode(File('../../fixtures/contracts.json').readAsStringSync())
              as Json)['templates']
          as Json)['fibre']['schema']
      as Json,
);
final lease = OfflineLease(
  id: 'test-lease',
  userId: 'test-owner',
  organizationId: 'test-org',
  deviceId: 'test-device',
  typeId: schema.typeId,
  allowedTemplates: [schema.templateId],
  assignmentRevision: 1,
  issuedAt: DateTime(2026, 10, 15),
  expiresAt: DateTime(2026, 10, 18),
);

class MemoryReports extends SecureReportRepository {
  MemoryReports() : super(const FlutterSecureStorage());
  Answers values = decodeAnswers({
    'installation_outcome': 'partial',
    'work_performed':
        'Installed cable and checked the route. Follow-up visit required.',
    'cable_installed': {'amount': 12, 'unit': 'm'},
    'connectivity_test': 'not_tested',
    'exception_reason': 'Connection awaiting a follow-up visit.',
  });
  ReportState current = ReportState.draft;
  @override
  String? get cipherVersion => 'test fixture';
  @override
  Future<LocalReport> get(String id) async => LocalReport(
    id: 'test-report-001',
    ownerId: 'test-owner',
    schema: schema,
    values: values,
    state: current,
    revision: 1,
    entitlementId: lease.id,
    updatedAt: DateTime(2026, 10, 15),
  );
  @override
  Future<LocalReport> save(
    String id,
    Answers answers, {
    String source = 'manual',
  }) async {
    values = answers;
    return get(id);
  }

  @override
  Future<LocalReport> confirm(
    String id, {
    required String timezone,
    required ReportLocation location,
  }) async {
    current = ReportState.queued;
    return get(id);
  }
}

class DesignController extends AppController {
  final memory = MemoryReports();
  @override
  SecureReportRepository get repository => memory;
  @override
  AppState build() => AppState(
    stage: AccessStage.ready,
    form: schema,
    lease: lease,
    voiceReady: false,
    user: EngineerIdentity(
      id: 'test-owner',
      name: 'Sam Fibre',
      email: 'fibre@fieldassist.demo',
      organizationId: 'test-org',
      typeId: schema.typeId,
      typeName: 'Fibre Installation Engineer',
      assignmentRevision: 1,
    ),
  );
  @override
  Future<OfflineLease> assertAccess() async => lease;
  @override
  Future<LocalReport> startReport() async => memory.get('test-report-001');
  @override
  Future<void> reloadReports() async {
    state = state.copy(reports: [await memory.get('test-report-001')]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('field_assist/location'),
          (call) async => call.method == 'capture'
              ? ReportLocation(
                  latitude: 12.9716,
                  longitude: 77.5946,
                  accuracyMeters: 10,
                  capturedAt: DateTime.now().toUtc(),
                  isMocked: true,
                ).toJson()
              : null,
        );
  });
  test(
    'location denial preserves the draft and a granted retry can queue it',
    () async {
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(DesignController.new)],
      );
      addTearDown(container.dispose);
      container.read(appProvider);
      final app = container.read(appProvider.notifier) as DesignController;
      final before = encodeAnswers(app.memory.values);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('field_assist/location');
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'capture') {
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Allow location access. Your draft is saved.',
          );
        }
        return null;
      });
      await expectLater(app.confirmReport('test-report-001'), throwsException);
      expect(app.memory.current, ReportState.draft);
      expect(encodeAnswers(app.memory.values), before);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'capture'
            ? ReportLocation(
                latitude: 12.9716,
                longitude: 77.5946,
                accuracyMeters: 10,
                capturedAt: DateTime.now().toUtc(),
                isMocked: true,
              ).toJson()
            : null,
      );
      await app.confirmReport('test-report-001');
      expect(app.memory.current, ReportState.queued);
      expect(encodeAnswers(app.memory.values), before);
    },
  );
  test('locking during location capture keeps the report as a draft', () async {
    final container = ProviderContainer(
      overrides: [appProvider.overrideWith(DesignController.new)],
    );
    addTearDown(container.dispose);
    container.read(appProvider);
    final app = container.read(appProvider.notifier) as DesignController;
    final before = encodeAnswers(app.memory.values);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('field_assist/location'),
          (call) async {
            if (call.method != 'capture') return null;
            await app.lock();
            return ReportLocation(
              latitude: 12.9716,
              longitude: 77.5946,
              accuracyMeters: 10,
              capturedAt: DateTime.now().toUtc(),
              isMocked: true,
            ).toJson();
          },
        );
    await expectLater(app.confirmReport('test-report-001'), throwsStateError);
    expect(app.memory.current, ReportState.draft);
    expect(encodeAnswers(app.memory.values), before);
  });
  test(
    'appearance choice survives a new controller and defaults to original light',
    () async {
      final first = ProviderContainer();
      expect(first.read(appearanceProvider), ThemeMode.light);
      await first.read(appearanceProvider.notifier).select(ThemeMode.dark);
      expect(first.read(appearanceProvider), ThemeMode.dark);
      first.dispose();
      final second = ProviderContainer();
      second.read(appearanceProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(second.read(appearanceProvider), ThemeMode.dark);
      second.dispose();
    },
  );
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '${mode.name} report journey retains values, review and truthful queued receipt',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(DesignController.new)],
        );
        addTearDown(container.dispose);
        container.read(appearanceProvider);
        await container.read(appearanceProvider.notifier).select(mode);
        final capture = const bool.fromEnvironment('CAPTURE_APP_UI');
        if (capture) {
          await tester.runAsync(() async {
            for (final family in ['Roboto', 'Ahem', 'MaterialIcons']) {
              final file = family == 'MaterialIcons'
                  ? 'MaterialIcons-Regular.otf'
                  : 'Roboto-Regular.ttf';
              final fonts = FontLoader(family)
                ..addFont(
                  File(
                    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/$file',
                  ).readAsBytes().then((b) => ByteData.sublistView(b)),
                );
              await fonts.load();
            }
          });
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: boundary,
              child: const FieldAssistApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> screenshot(String name) async {
          if (!capture) return;
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = File(
              '../../docs/evidence/mobile-refresh-${mode.name}-$name.png',
            );
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await screenshot('home');
        await tester.tap(find.text('Start report'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Installation outcome', findRichText: true),
          findsOneWidget,
        );
        await screenshot('form');
        await tester.tap(find.text('Review'));
        await tester.pumpAndSettle();
        expect(find.text('12 m'), findsOneWidget);
        await screenshot('review');
        await tester.scrollUntilVisible(
          find.byType(CheckboxListTile),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Confirm with location'),
          150,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('Confirm with location'));
        await tester.pumpAndSettle();
        expect(find.text('Saved on\nthis device.'), findsOneWidget);
        expect(find.text('Received and\nrecorded.'), findsNothing);
        await screenshot('receipt');
        await tester.tap(find.text('View sync queue'));
        await tester.pumpAndSettle();
        expect(find.text('Queued'), findsOneWidget);
        await screenshot('queue');
        container.read(routerProvider).go('/settings');
        await tester.pumpAndSettle();
        expect(find.text('Light'), findsOneWidget);
        expect(find.text('Dark'), findsOneWidget);
        await screenshot('settings');
        // The wide title and controls must remain usable at large system text sizes.
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        container.read(routerProvider).go('/home');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Start report'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
