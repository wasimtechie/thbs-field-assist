import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/forms/form_screen.dart';
import 'package:field_assist/features/fttp/fttp_widgets.dart';
import 'package:field_assist/features/home/home_screen.dart';
import 'appearance_journey_test.dart' as journey;

final form = FormDefinition.fromJson({
  ...jsonDecode(
        File('../../fixtures/templates/fttp-demo.json').readAsStringSync(),
      )
      as Json,
  'versionId': '50000000-0000-4000-8000-000000000005',
  'versionNumber': 1,
  'schemaHash': 'unused',
});

class FttpReports extends journey.MemoryReports {
  final savedMetadata = <String, Object>{};
  FttpReports() {
    values = fttpExample(false);
  }
  @override
  Future<LocalReport> get(String id) async => LocalReport(
    id: 'test-fttp-report',
    ownerId: 'test-owner',
    schema: form,
    values: values,
    state: current,
    revision: 1,
    entitlementId: journey.lease.id,
    updatedAt: DateTime.now(),
  );
  @override
  Future<Object?> metadata(String key) async => savedMetadata[key];
  @override
  Future<void> setMetadata(String key, Object value) async {
    savedMetadata[key] = value;
  }
}

class FttpController extends journey.DesignController {
  final fttpReports = FttpReports();
  @override
  SecureReportRepository get repository => fttpReports;
  @override
  AppState build() => super.build().copy(form: form);
  @override
  Future<void> reloadReports() async {
    state = state.copy(reports: [await fttpReports.get('test-fttp-report')]);
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('FTTP home shows its job pack without a missing-form warning', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appProvider.overrideWith(FttpController.new)],
        child: MaterialApp(theme: fieldTheme(), home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your next installation.'), findsOneWidget);
    expect(find.textContaining('No default form is assigned'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FTTP draft resumes its saved stage with its answers intact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [appProvider.overrideWith(FttpController.new)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appProvider.notifier) as FttpController;
    Future<void> openDraft() async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fieldTheme(),
            home: const FormScreen(reportId: 'test-fttp-report'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await openDraft();
    final testsChip = find.widgetWithText(ChoiceChip, '3. Service tests');
    await tester.ensureVisible(testsChip);
    await tester.tap(testsChip);
    await tester.pumpAndSettle();
    expect(
      controller.fttpReports.savedMetadata['fttp-step:test-fttp-report'],
      2,
    );
    final optical = find.byType(TextFormField).first;
    await tester.ensureVisible(optical);
    await tester.enterText(optical, '-21.7');
    await tester.pumpAndSettle();
    expect(
      encodeAnswers(
        container.read(appProvider).reports.single.values,
      )['optical_reading'],
      -21.7,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await openDraft();
    expect(tester.widget<ChoiceChip>(testsChip).selected, isTrue);
    expect(
      encodeAnswers(controller.fttpReports.values)['optical_reading'],
      -21.7,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('review edit opens the stage containing the requested field', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [appProvider.overrideWith(FttpController.new)],
    );
    addTearDown(container.dispose);
    final controller = container.read(appProvider.notifier) as FttpController;
    controller.fttpReports.savedMetadata['fttp-step:test-fttp-report'] = 4;
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const FormScreen(reportId: 'test-fttp-report'),
        ),
        GoRoute(
          path: '/review/:id',
          builder: (_, _) => const ReviewScreen(reportId: 'test-fttp-report'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: fieldTheme(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    final edit = find.byTooltip('Edit Visit outcome');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Installation completed'), findsOneWidget);
    expect(
      controller.fttpReports.savedMetadata['fttp-step:test-fttp-report'],
      0,
    );
    expect(tester.takeException(), isNull);
  });
}
