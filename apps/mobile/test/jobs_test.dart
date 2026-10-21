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
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/jobs/jobs_screen.dart';
import 'package:field_assist/features/jobs/work_order.dart';
import 'appearance_journey_test.dart' as journey;

WorkOrder job({
  String status = 'assigned',
  String typeId = '',
  String id = '80000000-0000-4000-8000-000000000001',
}) => WorkOrder.fromJson({
  'id': id,
  'title': 'Inspect cable at Orion hub',
  'site': 'Synthetic Orion hub · Bengaluru',
  'instructions': 'Capture the printed label and record the work outcome.',
  'assetReference': 'CBL-2026-0042',
  'typeId': typeId.isEmpty ? journey.schema.typeId : typeId,
  'priority': 'urgent',
  'status': status,
  'reviewNote': status == 'follow_up'
      ? 'Verify the connectivity result on your next visit.'
      : '',
  'dueAt': DateTime.now()
      .subtract(const Duration(hours: 1))
      .toUtc()
      .toIso8601String(),
  'updatedAt': DateTime.now().toUtc().toIso8601String(),
});

class JobReports extends SecureReportRepository {
  JobReports() : super(const FlutterSecureStorage());
  final records = <LocalReport>[];
  @override
  Future<LocalReport> create(
    FormDefinition schema,
    String entitlementId, {
    String? workOrderId,
    int? assignmentRevision,
  }) async {
    final r = LocalReport(
      id: 'test-job-report',
      ownerId: 'test-owner',
      schema: schema,
      values: {},
      state: ReportState.draft,
      revision: 1,
      entitlementId: entitlementId,
      updatedAt: DateTime.now(),
      workOrderId: workOrderId,
    );
    records.insert(0, r);
    return r;
  }

  @override
  Future<List<LocalReport>> list() async => records;
}

class JobController extends journey.DesignController {
  final jobs = JobReports();
  @override
  SecureReportRepository get repository => jobs;
  @override
  AppState build() => super.build().copy(
    workOrders: [
      job(),
      job(status: 'follow_up', id: '80000000-0000-4000-8000-000000000002'),
    ],
    operationsSyncedAt: DateTime.now(),
  );
  @override
  Future<void> reloadReports() async {
    state = state.copy(reports: await jobs.list());
  }
}

class WrongTypeController extends JobController {
  @override
  AppState build() =>
      super.build().copy(workOrders: [job(typeId: 'another-engineer-type')]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('received work is awaiting review, and only open work is overdue', () {
    expect(job().overdue, true);
    expect(job(status: 'submitted').canStart, false);
    expect(job(status: 'submitted').overdue, false);
    expect(job(status: 'completed').canStart, false);
    expect(job(status: 'follow_up').canStart, true);
  });
  test('starting the same downloaded job resumes its existing draft', () async {
    final c = ProviderContainer(
      overrides: [appProvider.overrideWith(JobController.new)],
    );
    addTearDown(c.dispose);
    c.read(appProvider);
    final controller = c.read(appProvider.notifier);
    final first = await controller.startAssignedJob(job().id),
        second = await controller.startAssignedJob(job().id);
    expect(first.id, second.id);
    expect(first.workOrderId, job().id);
    expect(c.read(appProvider).reports.length, 1);
  });
  test('queued job report blocks a second draft', () async {
    final c = ProviderContainer(
      overrides: [appProvider.overrideWith(JobController.new)],
    );
    addTearDown(c.dispose);
    c.read(appProvider);
    final controller = c.read(appProvider.notifier) as JobController;
    controller.jobs.records.add(
      LocalReport(
        id: 'queued-report',
        ownerId: 'test-owner',
        schema: journey.schema,
        values: {},
        state: ReportState.queued,
        revision: 1,
        entitlementId: journey.lease.id,
        updatedAt: DateTime.now(),
        workOrderId: job().id,
      ),
    );
    await controller.reloadReports();
    await expectLater(controller.startAssignedJob(job().id), throwsStateError);
    expect(controller.jobs.records.length, 1);
  });
  test(
    'job from another engineer type cannot use the installed form',
    () async {
      final c = ProviderContainer(
        overrides: [appProvider.overrideWith(WrongTypeController.new)],
      );
      addTearDown(c.dispose);
      c.read(appProvider);
      await expectLater(
        c.read(appProvider.notifier).startAssignedJob(job().id),
        throwsStateError,
      );
    },
  );
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      '${brightness.name} jobs show offline brief and actionable follow-up',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (const bool.fromEnvironment('CAPTURE_OPERATIONS_UI')) {
          await tester.runAsync(() async {
            for (final e in {
              'Roboto': 'Roboto-Regular.ttf',
              'MaterialIcons': 'MaterialIcons-Regular.otf',
            }.entries) {
              final bytes = await File(
                '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${e.value}',
              ).readAsBytes();
              await (FontLoader(
                e.key,
              )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
            }
          });
        }
        final c = ProviderContainer(
          overrides: [appProvider.overrideWith(JobController.new)],
        );
        addTearDown(c.dispose);
        final key = GlobalKey();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: fieldTheme(brightness: brightness),
                home: const JobsScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('My jobs'), findsOneWidget);
        expect(find.textContaining('Downloaded '), findsOneWidget);
        expect(find.text('Awaiting review'), findsNothing);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_OPERATIONS_UI')) {
          await tester.runAsync(() async {
            final image =
                await (key.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../../docs/evidence/operations-jobs-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: fieldTheme(brightness: brightness),
              home: JobDetailScreen(
                jobId: job(
                  status: 'follow_up',
                  id: '80000000-0000-4000-8000-000000000002',
                ).id,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Supervisor note'), findsOneWidget);
        expect(
          find.text('Verify the connectivity result on your next visit.'),
          findsOneWidget,
        );
        await tester.scrollUntilVisible(find.text('Start follow-up report'),180);
        expect(find.text('Start follow-up report'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('My jobs entry opens the downloaded queue from home', (
    tester,
  ) async {
    final c = ProviderContainer(
      overrides: [appProvider.overrideWith(JobController.new)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const FieldAssistApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('My jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Your next visit,\nready to go.'), findsOneWidget);
  });
}
