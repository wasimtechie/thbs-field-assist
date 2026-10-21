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
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/label_scan/cable_scan_screen.dart';
import 'package:field_assist/features/label_scan/cable_label.dart';
import 'appearance_journey_test.dart' as journey;
import 'cable_label_test.dart' as fixture;

// UI-only fixtures. Production camera/OCR and persistence remain real.
final previewForm = FormDefinition.fromJson({
  ...fixture.cableForm.source,
  'versionNumber': 4,
});

class CableReports extends journey.MemoryReports {
  @override
  Future<LocalReport> get(String id) async => LocalReport(
    id: 'test-report-001',
    ownerId: 'test-owner',
    schema: previewForm,
    values: values,
    state: ReportState.draft,
    revision: 1,
    entitlementId: journey.lease.id,
    updatedAt: DateTime(2026, 10, 15),
  );
}

class CableController extends journey.DesignController {
  final cable = CableReports();
  @override
  SecureReportRepository get repository => cable;
  @override
  AppState build() => super.build().copy(form: previewForm);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_SCAN_UI')) return;
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../../docs/evidence/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> fonts(WidgetTester tester) async {
    if (!const bool.fromEnvironment('CAPTURE_SCAN_UI')) return;
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': 'Roboto-Regular.ttf',
        'MaterialIcons': 'MaterialIcons-Regular.otf',
      }.entries) {
        final bytes = await File(
          '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${entry.value}',
        ).readAsBytes();
        await (FontLoader(
          entry.key,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
  }

  testWidgets(
    'camera entry appears in the configured cable identification section',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await fonts(tester);
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(CableController.new)],
      );
      addTearDown(container.dispose);
      final key = GlobalKey();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(key: key, child: const FieldAssistApp()),
        ),
      );
      container.read(routerProvider).go('/forms/test-report-001');
      await tester.pumpAndSettle();
      expect(find.text('Scan cable label'), findsOneWidget);
      expect(find.text('Read it from the label.'), findsOneWidget);
      expect(find.text('Fill by voice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'cable-scan-form');
    },
  );
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      '${brightness.name} scan review is editable and preserves explicit consent',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fonts(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: fieldTheme(brightness: brightness),
              home: Scaffold(
                appBar: AppBar(title: const Text('Review scanned details')),
                body: CableLabelReview(
                  form: fixture.cableForm,
                  existing: {},
                  readout: CableLabelReadout.parse(fixture.labelText),
                  onApply: (_) {},
                  onRetake: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Apply to report'), findsOneWidget);
        expect(find.text('Check the label. Keep control.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(tester, key, 'cable-scan-review-${brightness.name}');
      },
    );
  }
}
