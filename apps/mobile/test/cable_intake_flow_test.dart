import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/design_system/workspace.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/forms/form_screen.dart';
import 'package:field_assist/features/label_scan/cable_label.dart';
import 'package:field_assist/features/label_scan/cable_scan_screen.dart';
import 'package:field_assist/features/label_scan/cable_intake_screen.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'package:field_assist/features/voice/voice_session_screen.dart';
import 'appearance_journey_test.dart' as fixture;
import 'cable_label_test.dart' as label;
import 'voice_form_flow_test.dart' as spoken;
import 'support/voice_fakes.dart';

class IntakeReports extends fixture.MemoryReports {
  final sources = <String>[];
  IntakeReports() {
    values = {};
  }
  @override
  Future<LocalReport> get(String id) async => LocalReport(
    id: id,
    ownerId: 'test-owner',
    schema: label.cableForm,
    values: values,
    state: ReportState.draft,
    revision: 1,
    entitlementId: fixture.lease.id,
    updatedAt: DateTime(2026, 10, 16),
  );
  @override
  Future<LocalReport> save(
    String id,
    Answers answers, {
    String source = 'manual',
  }) async {
    sources.add(source);
    return super.save(id, answers, source: source);
  }
}

class IntakeController extends spoken.SpokenFormController {
  final cable = IntakeReports();
  @override
  SecureReportRepository get repository => cable;
  @override
  AppState build() => super.build().copy(form: label.cableForm);
  @override
  Future<void> reloadReports() async {
    if (ref.mounted) {
      state = state.copy(reports: [await cable.get('test-report-001')]);
    }
  }
}

Future<void> fonts(WidgetTester tester) async {
  if (!const bool.fromEnvironment('CAPTURE_INTAKE_UI')) return;
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

Future<void> tap(WidgetTester tester, String label) async {
  final finder = find.text(label).last;
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Widget shell(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: workspaceTheme(fieldTheme(brightness: brightness)),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scanCancelled in [false, true]) {
    testWidgets(
      scanCancelled
          ? 'cancelled scan retains intake choices without microphone'
          : 'scan review and selected missing details save before work voice begins',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fonts(tester);
        final audio = TestAudio([]);
        final container = ProviderContainer(
          overrides: [
            appProvider.overrideWith(IntakeController.new),
            voiceAudioFactoryProvider.overrideWithValue(() => audio),
            cableScanPageProvider.overrideWithValue(
              (form, existing) => Builder(
                builder: (context) => Scaffold(
                  body: scanCancelled
                      ? Center(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel scan'),
                          ),
                        )
                      : CableLabelReview(
                          form: form,
                          existing: existing,
                          readout: CableLabelReadout.parse(
                            'MANUFACTURER: Demo Cable Works\nFIBRE COUNT: 24',
                          ),
                          onApply: (patch) => Navigator.pop(context, patch),
                          onRetake: () {},
                        ),
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(appProvider);
        final app = container.read(appProvider.notifier) as IntakeController;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: shell(const FormScreen(reportId: 'test-report-001')),
          ),
        );
        await tester.pumpAndSettle();
        await tap(tester, 'Fill by voice');
        expect(find.byType(CableIntakeScreen), findsOneWidget);
        expect(audio.events, isNot(contains('capture')));
        await tap(tester, 'Scan label');
        expect(app.cable.values, isEmpty);
        if (scanCancelled) {
          await tap(tester, 'Cancel scan');
          expect(find.text('Enter details'), findsOneWidget);
          expect(audio.events, isNot(contains('permission')));
          await tap(tester, 'Not available');
          expect(find.byType(VoiceSessionScreen), findsOneWidget);
          expect(app.cable.values, isEmpty);
        } else {
          expect(find.byType(CableLabelReview), findsOneWidget);
          await tap(tester, 'Apply to report');
          expect(
            app.cable.values[label.target('manufacturer').id]!.toJson(),
            'Demo Cable Works',
          );
          expect(app.cable.sources, ['camera_ocr_reviewed']);
          expect(app.cable.values['cable_installed'], isNull);
          await tap(tester, 'Add missing details');
          expect(find.text('Manufacturer'), findsNothing);
          expect(find.text('Fibre / core count'), findsNothing);
          await tap(tester, 'Batch / lot number');
          await tap(tester, 'Enter selected details');
          expect(find.textContaining('batch / lot number?'), findsOneWidget);
          expect(find.textContaining('manufactured'), findsNothing);
          await tester.enterText(find.byType(TextField), '00-OI-10');
          await tap(tester, 'Save & continue');
          expect(
            app.cable.values[label.target('batch').id]!.toJson(),
            '00-OI-10',
          );
          expect(app.cable.sources.last, 'manual');
          expect(audio.events, isNot(contains('capture')));
          await tap(tester, 'Continue to work questions');
          expect(find.byType(VoiceSessionScreen), findsOneWidget);
        }
        final voice = tester
            .widget<VoiceSessionScreen>(find.byType(VoiceSessionScreen))
            .coordinator;
        expect(voice.activeField!.id, 'installation_outcome');
        expect(audio.events, contains('capture'));
        await tap(tester, 'Partially completed');
        await tap(tester, 'End');
        expect(find.byType(FormScreen), findsOneWidget);
        expect(app.cable.values['installation_outcome']!.toJson(), 'partial');
        expect(
          container
              .read(appProvider)
              .reports
              .single
              .values['installation_outcome']!
              .toJson(),
          'partial',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'manual detail save failure stays on the question and a retry preserves exact ID',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await fonts(tester);
      Answers values = {};
      var fail = true;
      final voice = VoiceCoordinator(
        engine: TestEngine([]),
        schema: label.cableForm,
        readValues: () => values,
        audio: TestAudio([]),
        playback: false,
        onPatch: (_, _) async {},
      );
      addTearDown(voice.shutdown);
      await tester.pumpWidget(
        shell(
          CableDetailsScreen(
            form: label.cableForm,
            readValues: () => values,
            voice: voice,
            onSave: (patch) async {
              if (fail) throw StateError('Disk full');
              values = {...values, ...patch};
            },
          ),
        ),
      );
      await tap(tester, 'Cable ID / number');
      await tap(tester, 'Enter selected details');
      await tester.enterText(find.byType(TextField), '00-OI-10');
      await tap(tester, 'Save & continue');
      expect(find.textContaining('Disk full'), findsOneWidget);
      expect(values, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '00-OI-10',
      );
      fail = false;
      await tap(tester, 'Save & continue');
      expect(values[label.target('cable_id').id]!.toJson(), '00-OI-10');
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} cable introduction fits a narrow phone and large text',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fonts(tester);
        final audio = TestAudio([]), engine = TestEngine([]);
        final voice = VoiceCoordinator(
          engine: engine,
          schema: label.cableForm,
          readValues: () => {},
          audio: audio,
          echoTail: Duration.zero,
          onPatch: (_, _) async {},
        );
        addTearDown(voice.shutdown);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: shell(
              CableIntakeScreen(
                form: label.cableForm,
                readValues: () => {},
                voice: voice,
                onScan: () async => false,
                onSave: (_) async {},
              ),
              brightness: brightness,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          engine.events.any(
            (v) => v.contains('Do you have the cable or drum label?'),
          ),
          isTrue,
        );
        expect(audio.events, isNot(contains('permission')));
        if (const bool.fromEnvironment('CAPTURE_INTAKE_UI')) {
          await tester.runAsync(() async {
            final frame =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await frame.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '../../docs/evidence/cable-intake-${brightness.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            frame.dispose();
          });
        }
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Enter details'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
