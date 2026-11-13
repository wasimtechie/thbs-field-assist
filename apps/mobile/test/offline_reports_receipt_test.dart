import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/app/router.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/visit_summary_submission.dart';
import 'package:field_assist/main.dart';
import 'package:field_assist/features/forms/form_screen.dart' show ReviewScreen;
import 'package:field_assist/features/sync/queue_screen.dart'
    show LocalReceiptScreen;
import 'appearance_journey_test.dart' as full;
import 'visit_completion_test.dart' as visit;

class OfflineVisitController extends visit.VisitController {
  @override
  AppState build() => super.build().copy(offline: true);
}

class DeferredVisitRecords extends visit.VisitRecords {
  final writeGate = Completer<void>();
  @override
  Future<void> setMetadata(String key, Object value) async {
    if (key.startsWith('closure-demo-summary:')) await writeGate.future;
    await super.setMetadata(key, value);
  }
}

class NavigationSaveController extends visit.VisitController {
  NavigationSaveController() : super(records: DeferredVisitRecords());
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'leaving the form does not cancel an in-flight local draft save',
    (tester) async {
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(NavigationSaveController.new)],
      );
      addTearDown(container.dispose);
      final app =
          container.read(appProvider.notifier) as NavigationSaveController;
      final records = app.records as DeferredVisitRecords;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FieldAssistApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      router.go('/forms/closure-test');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fill manually'));
      await tester.tap(find.text('Fill manually'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Installed the ONT in the living room.',
      );
      await tester.pump();
      router.go('/queue');
      await tester.pumpAndSettle();
      records.writeGate.complete();
      await tester.pumpAndSettle();
      expect(
        (records.data['closure-demo-summary:closure-test']
            as Json)['values']['actual_work'],
        'Installed the ONT in the living room.',
      );
      expect(find.text('Visit summary · Draft saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'offline summary draft appears in Reports, submission opens a receipt, and Android back leaves review',
    (tester) async {
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(OfflineVisitController.new)],
      );
      addTearDown(container.dispose);
      final app =
          container.read(appProvider.notifier) as OfflineVisitController;
      app.api.offline = true;
      app.records.data['closure-demo-summary:closure-test'] = {
        'values': visit.summaryValues,
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
      router.go('/forms/closure-test');
      await tester.pumpAndSettle();
      router.go('/queue');
      await tester.pumpAndSettle();
      expect(find.text('Visit summary · Draft saved'), findsOneWidget);
      expect(
        find.textContaining('5 of 5 answers saved on this device'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'A server connection is needed only for dashboard delivery',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Visit summary · Draft saved'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review 5-field summary'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete visit & submit'));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        startsWith('/visit-summaries/'),
      );
      expect(router.canPop(), false);
      expect(find.text('Review visit summary'), findsNothing);
      expect(
        find.text('Saved on this device · Waiting to sync'),
        findsOneWidget,
      );
      expect(
        (app.records.data[VisitSummaryOutbox.storageKey] as List)
            .single['status'],
        'waiting',
      );
      expect(find.textContaining('Receipt:'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.toString(),
        '/jobs?view=completed',
      );
      router.go('/queue');
      await tester.pumpAndSettle();
      expect(find.text('Visit summary · Draft saved'), findsNothing);
      await tester.tap(find.text('Submitted on device · Waiting to sync'));
      await tester.pumpAndSettle();
      expect(find.text('Visit summary receipt'), findsOneWidget);
      expect(find.text('Review visit summary'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'full report confirmation queues offline and stale review routes open its receipt',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('field_assist/location');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'capture'
            ? ReportLocation(
                latitude: 51.4,
                longitude: -.1,
                accuracyMeters: 10,
                capturedAt: DateTime.now().toUtc(),
                isMocked: true,
              ).toJson()
            : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(full.DesignController.new)],
      );
      addTearDown(container.dispose);
      final app = container.read(appProvider.notifier) as full.DesignController;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FieldAssistApp(),
        ),
      );
      await tester.pumpAndSettle();
      final router = container.read(routerProvider);
      router.go('/review/test-report-001');
      await tester.pumpAndSettle();
      final reviewScroll = find
          .descendant(
            of: find.byType(ReviewScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byType(CheckboxListTile),
        300,
        scrollable: reviewScroll,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Confirm with location'),
        200,
        scrollable: reviewScroll,
      );
      await tester.tap(find.text('Confirm with location'));
      await tester.pumpAndSettle();
      expect(app.memory.current, ReportState.queued);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/receipt/test-report-001',
      );
      expect(router.canPop(), false);
      await tester.scrollUntilVisible(
        find.text('Done'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(LocalReceiptScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/queue');
      router.go('/review/test-report-001');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        '/receipt/test-report-001',
      );
      expect(find.text('Review your report'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
