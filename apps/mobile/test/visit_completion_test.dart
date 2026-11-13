import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/app/router.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/collaboration/collaboration_service.dart';
import 'package:field_assist/features/jobs/visit_progress.dart';
import 'package:field_assist/features/jobs/work_order.dart';
import 'package:field_assist/main.dart';
import 'compact_closure_test.dart' as compact;
import 'closure_journey_test.dart' as full;
import 'jobs_test.dart' as jobs;

final visitJob = jobs.job(typeId: full.closureForm.typeId);
LocalReport report({int revision = 1}) => LocalReport(
  id: 'closure-test',
  ownerId: 'test-owner',
  schema: full.closureForm,
  values: {},
  state: ReportState.draft,
  revision: 1,
  entitlementId: 'test-lease',
  updatedAt: DateTime.utc(2026, 10, 23),
  workOrderId: visitJob.id,
  workOrderAssignmentRevision: revision,
);
const summaryValues = {
  'actual_work': 'Installed ONT in living room',
  'claimed_outcome': 'completed',
  'serving_asset': 'CBT-SYN-10',
  'optical_rx_dbm': -18.2,
  'operational_test': 'passed',
  'next_action': 'No further work required',
};
Json submission({
  String outcome = 'completed',
  String status = 'waiting',
  String at = '2026-10-23T10:00:00Z',
}) => {
  'id': 'summary',
  'status': status,
  'payload': {
    'clientReportId': 'closure-test',
    'workOrderId': visitJob.id,
    'confirmedAt': at,
    'values': {...summaryValues, 'claimed_outcome': outcome},
  },
};

class VisitRecords extends compact.CompactReports {
  @override
  Future<LocalReport> get(String id) async => report();
}

class VisitController extends compact.CompactController {
  VisitController({VisitRecords? records})
    : super(records: records ?? VisitRecords());
  @override
  AppState build() =>
      super.build().copy(workOrders: [visitJob], reports: [report()]);
  void visits(CollaborationState value) =>
      state = state.copy(collaboration: value);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'completed summaries persist without approving the work order, while blocked work stays active',
    () {
      final complete = VisitProgress(visitJob, [report()], [submission()]);
      expect(complete.inCompleted, true);
      expect(complete.label, 'Visit completed');
      expect(complete.delivery, contains('Waiting to sync'));
      expect(complete.approved, false);
      expect(visitJob.status, 'assigned');
      final blocked = VisitProgress(
        visitJob,
        [report()],
        [submission(outcome: 'blocked')],
      );
      expect(blocked.inCompleted, false);
      expect(blocked.label, contains('Follow-up required'));
      expect(
        VisitProgress(
          visitJob,
          [report(revision: 2)],
          [submission()],
        ).inCompleted,
        false,
      );
      final reopened = WorkOrder.fromJson({
        ...visitJob.source,
        'status': 'follow_up',
        'updatedAt': '2026-10-23T11:00:00Z',
      });
      expect(
        VisitProgress(reopened, [report()], [submission()]).inCompleted,
        false,
      );
      final approved = WorkOrder.fromJson({
        ...visitJob.source,
        'status': 'completed',
      });
      expect(VisitProgress(approved, [], []).label, 'Approved & completed');
    },
  );
  for (final offline in [false, true]) {
    testWidgets(
      '${offline ? 'offline' : 'online'} complete and Done opens Completed; back never reopens review',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [appProvider.overrideWith(VisitController.new)],
        );
        addTearDown(container.dispose);
        final app = container.read(appProvider.notifier) as VisitController;
        app.api.offline = offline;
        app.records.data['closure-demo-summary:closure-test'] = {
          'values': summaryValues,
          'sources': {},
        };
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const FieldAssistApp(),
          ),
        );
        await tester.pumpAndSettle();
        final router = container.read(routerProvider);
        router.go('/jobs?view=completed');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Active jobs'));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.toString(), '/jobs');
        router.push('/forms/closure-test');
        await tester.pumpAndSettle();
        expect(find.textContaining('Check-in not recorded'), findsOneWidget);
        expect(
          tester.getBottomLeft(find.text('Fill with voice AI')).dy,
          lessThan(tester.getTopLeft(find.text('Review 6-field summary')).dy),
          reason:
              'The primary voice action stays above the review footer on a narrow phone.',
        );
        await tester.tap(find.text('Review 6-field summary'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Complete visit & submit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/jobs?view=completed',
        );
        expect(
          router.canPop(),
          false,
          reason:
              'Done removes the form and review routes from the back stack.',
        );
        expect(find.text('Visit completed'), findsOneWidget);
        expect(
          find.text(
            offline
                ? 'Saved on device · Waiting to sync'
                : 'Summary received by dashboard',
          ),
          findsOneWidget,
        );
        expect(find.text('Review visit summary'), findsNothing);
        expect(
          container.read(appProvider).workOrders.single.status,
          'assigned',
        );
        router.go('/home');
        await tester.pumpAndSettle();
        expect(find.text('Review visit summary'), findsNothing);
        expect(find.text('0 open'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        final reopened = ProviderContainer(
          overrides: [
            appProvider.overrideWith(
              () => VisitController(records: app.records as VisitRecords),
            ),
          ],
        );
        addTearDown(reopened.dispose);
        reopened.read(appProvider);
        await reopened.read(appProvider.notifier).reloadSummarySubmissions();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: reopened,
            child: const FieldAssistApp(),
          ),
        );
        await tester.pumpAndSettle();
        reopened.read(routerProvider).go('/jobs?view=completed');
        await tester.pumpAndSettle();
        expect(
          find.text('Visit completed'),
          findsOneWidget,
          reason:
              'Completion is derived from the durable confirmation after reopening.',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'resuming shows the saved check-in without asking for a duplicate arrival',
    (tester) async {
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(VisitController.new)],
      );
      addTearDown(container.dispose);
      final app = container.read(appProvider.notifier) as VisitController;
      app.visits(
        CollaborationState(
          visits: [
            {
              'id': 'visit',
              'workOrderId': visitJob.id,
              'assignmentRevision': 1,
              'startedAt': '2026-10-23T08:00:00Z',
              'state': 'working',
              'events': [
                {
                  'requestId': 'arrive',
                  'action': 'check_in',
                  'sequence': 1,
                  'occurredAt': '2026-10-23T08:00:00Z',
                },
              ],
            },
          ],
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FieldAssistApp(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(routerProvider).go('/forms/closure-test');
      await tester.pumpAndSettle();
      expect(find.textContaining('On site since'), findsOneWidget);
      expect(find.text('Check in'), findsNothing);
      await tester.tap(find.text('Time on site'));
      await tester.pumpAndSettle();
      expect(find.text('Check out'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
