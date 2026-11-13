import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/location/location_capture.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';
import 'package:field_assist/features/jobs/work_order.dart';
import 'package:field_assist/features/time_tracking/site_time_card.dart';
import 'package:field_assist/features/time_tracking/time_tracking.dart';
import 'visit_completion_test.dart' as fixture;

class SiteController extends fixture.VisitController {
  bool deny = false;
  final recorded = <Json>[];
  @override
  Future<void> recordSiteTime(
    WorkOrder job,
    String action, {
    String note = '',
  }) async {
    if (deny) {
      throw const LocationCaptureFailure(
        'PERMISSION_DENIED',
        'Allow location access in app settings.',
      );
    }
    recorded.add({'action': action, 'note': note});
  }

  void confirmations(List<Json> rows) =>
      state = state.copy(summarySubmissions: rows);
}

Json activeVisit() => {
  'id': 'visit',
  'workOrderId': fixture.visitJob.id,
  'assignmentRevision': 1,
  'startedAt': '2026-10-23T08:00:00Z',
  'state': 'working',
  'events': [
    {
      'requestId': 'arrive',
      'sequence': 1,
      'action': 'check_in',
      'occurredAt': '2026-10-23T08:00:00Z',
    },
  ],
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'offline confirmation permits normal departure; drafts and older visits do not',
    () {
      expect(
        visitHasSubmission(fixture.visitJob.id, 1, '2026-10-23T08:00:00Z', [
          fixture.report(),
        ], []),
        false,
      );
      expect(
        visitHasSubmission(
          fixture.visitJob.id,
          1,
          '2026-10-23T08:00:00Z',
          [fixture.report()],
          [fixture.submission()],
        ),
        true,
      );
      expect(
        visitHasSubmission(
          fixture.visitJob.id,
          1,
          '2026-10-23T11:00:00Z',
          [fixture.report()],
          [fixture.submission()],
        ),
        false,
      );
      expect(
        visitHasSubmission(
          fixture.visitJob.id,
          2,
          '2026-10-23T08:00:00Z',
          [fixture.report()],
          [fixture.submission()],
        ),
        false,
      );
    },
  );
  for (final deny in [false, true]) {
    testWidgets(
      'Android check-in dialog closes safely with ${deny ? 'denied location' : 'a saved note'}',
      (tester) async {
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(SiteController.new)],
        );
        addTearDown(container.dispose);
        final app = container.read(appProvider.notifier) as SiteController;
        app.deny = deny;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: fieldTheme().copyWith(platform: TargetPlatform.android),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SiteTimeCard(job: fixture.visitJob),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check in'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField),
          'Arrived at the agreed entrance',
        );
        await tester.tap(find.text('Record action'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (deny) {
          expect(
            find.text('Allow location access in app settings.'),
            findsOneWidget,
          );
          expect(find.text('Open location settings'), findsOneWidget);
          expect(app.recorded, isEmpty);
          const channel = MethodChannel('field_assist/location');
          final messenger =
              TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'SETTINGS_UNAVAILABLE'),
          );
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
          await tester.tap(find.text('Open location settings'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Open your device settings'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } else {
          expect(app.recorded.single['note'], 'Arrived at the agreed entrance');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  for (final submitted in [false, true]) {
    testWidgets(
      'check-out ${submitted ? 'uses local submission offline' : 'requires an early departure reason'}',
      (tester) async {
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(SiteController.new)],
        );
        addTearDown(container.dispose);
        final app = container.read(appProvider.notifier) as SiteController;
        app.visits(CollaborationState(visits: [activeVisit()]));
        if (submitted) app.confirmations([fixture.submission()]);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: fieldTheme(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SiteTimeCard(job: fixture.visitJob),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Check out'));
        await tester.pumpAndSettle();
        if (!submitted) {
          expect(find.text('Leave before submitting?'), findsOneWidget);
          await tester.tap(find.text('Check out with reason'));
          await tester.pumpAndSettle();
          expect(app.recorded, isEmpty);
          expect(
            find.text('Add a reason, or finish your report first.'),
            findsOneWidget,
          );
          await tester.enterText(
            find.byType(TextFormField),
            'Customer unavailable; complete report after leaving',
          );
        }
        await tester.tap(
          find.text(submitted ? 'Record action' : 'Check out with reason'),
        );
        await tester.pumpAndSettle();
        expect(app.recorded.single['action'], 'check_out');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
