import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/closure/closure_screen.dart';
import 'appearance_journey_test.dart' as journey;
import 'support/voice_fakes.dart';
import 'package:field_assist/features/voice/voice_audio.dart';

final closureForm = FormDefinition.fromJson(
  jsonDecode(
        File('../../fixtures/templates/closure-mvp.json').readAsStringSync(),
      )
      as Json,
);

class ClosureReports extends journey.MemoryReports {
  final data = <String, Object>{};
  ClosureReports() {
    values = decodeAnswers({
      'scenario': 'S1',
      'work_stage': 'final_provision',
      'route_obstructed': false,
      'access_permission': true,
      'ont_fitted': true,
      'fibre_connected': true,
      'penetration_required': true,
    });
  }
  @override
  Future<LocalReport> get(String id) async => LocalReport(
    id: 'closure-test',
    ownerId: 'test-owner',
    schema: closureForm,
    values: values,
    state: current,
    revision: 1,
    entitlementId: journey.lease.id,
    updatedAt: DateTime.now(),
  );
  @override
  Future<Object?> metadata(String key) async => data[key];
  @override
  Future<void> saveClosureCapture(String id, Json capture) async {
    data['closure-capture:$id'] = {...capture};
  }
}

class ClosureController extends journey.DesignController {
  final records = ClosureReports();
  @override
  SecureReportRepository get repository => records;
  @override
  AppState build() => super.build().copy(form: closureForm);
  @override
  Future<void> reloadReports() async {
    state = state.copy(reports: [await records.get('closure-test')]);
  }
}

class VoiceClosureController extends ClosureController {
  final engine = TestEngine([])
    ..answer = 'Installed ONT. Optical receive -18.2 dBm; service test passed.';
  @override
  TestEngine get voice => engine;
  @override
  AppState build() => super.build().copy(voiceReady: true);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'narrative facts stay candidates until accepted and missing consent stays missing',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(ClosureController.new)],
      );
      addTearDown(container.dispose);
      final controller =
          container.read(appProvider.notifier) as ClosureController;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fieldTheme(),
            home: const ClosureScreen(
              reportId: 'closure-test',
              fullChecklist: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fill with voice AI'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.scrollUntilVisible(find.text('Fill manually'), 200);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Fill manually')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fill manually'));
      await tester.pumpAndSettle();
      const narrative =
          'Installed ONT at agreed location. Optical receive -18.2 dBm; service test passed. Customer shown equipment.';
      final input = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == 'Original engineer narrative',
      );
      await tester.enterText(input, narrative);
      await tester.pumpAndSettle();
      final extract = find.text('Find explicit facts');
      await Scrollable.ensureVisible(tester.element(extract), alignment: .3);
      await tester.pumpAndSettle();
      await tester.tap(extract);
      await tester.pumpAndSettle();
      expect(controller.records.values['optical_rx_dbm'], isNull);
      final capture =
          controller.records.data['closure-capture:closure-test'] as Json;
      expect(
        (capture['candidates'] as List).any(
          (c) => c['fieldId'] == 'optical_rx_dbm' && c['value'] == -18.2,
        ),
        isTrue,
      );
      final accept = find.text('Accept these facts into the draft');
      await Scrollable.ensureVisible(tester.element(accept), alignment: .3);
      await tester.pumpAndSettle();
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(encodeAnswers(controller.records.values)['optical_rx_dbm'], -18.2);
      expect(controller.records.values['drilling_consent'], isNull);
      expect(controller.records.values['optical_test'], isNull);
      expect(controller.records.current, ReportState.draft);
      expect(find.textContaining('Review closure ·'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'voice and option entry fill real draft callbacks, with final review still required',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = TestAudio([]);
      final container = ProviderContainer(
        overrides: [
          appProvider.overrideWith(VoiceClosureController.new),
          voiceAudioFactoryProvider.overrideWithValue(() => audio),
        ],
      );
      addTearDown(container.dispose);
      final controller =
          container.read(appProvider.notifier) as VoiceClosureController;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fieldTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const ClosureScreen(
              reportId: 'closure-test',
              fullChecklist: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fill with voice AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fill with voice AI'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      audio.feed();
      audio.meter!(.05);
      audio.bytes!(Uint8List(48000));
      audio.meter!(0);
      await tester.pumpAndSettle();
      expect(controller.records.values['optical_rx_dbm']?.toJson(), -18.2);
      expect(controller.records.values['drilling_consent'], isNull);
      expect(controller.records.values['optical_test'], isNull);
      expect(controller.records.current, ReportState.draft);
      final capture =
          controller.records.data['closure-capture:closure-test'] as Json;
      expect(
        (capture['candidates'] as List).firstWhere(
          (c) => c['fieldId'] == 'optical_rx_dbm',
        )['verificationStatus'],
        'candidate',
      );
      await tester.ensureVisible(find.text('No'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(controller.records.values['identity_verified']?.toJson(), false);
      final updated =
          controller.records.data['closure-capture:closure-test'] as Json;
      expect(
        (updated['candidates'] as List).firstWhere(
          (c) => c['fieldId'] == 'identity_verified',
        )['sourceType'],
        'manual',
      );
      expect(controller.records.current, ReportState.draft);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
