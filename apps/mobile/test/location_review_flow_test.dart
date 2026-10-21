import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/forms/form_screen.dart';
import 'appearance_journey_test.dart' show DesignController;

void main() {
  testWidgets(
    'one confirm tap requests permission, disables duplicates and preserves a denied draft',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(DesignController.new)],
      );
      addTearDown(container.dispose);
      container.read(appProvider);
      final app = container.read(appProvider.notifier) as DesignController;
      final permission = Completer<void>();
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('field_assist/location');
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'prepare') {
          await permission.future;
          throw PlatformException(
            code: 'PERMISSION_DENIED',
            message: 'Allow location in app permissions. Your draft is saved.',
          );
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fieldTheme(),
            home: const ReviewScreen(reportId: 'test-report-001'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final checkbox = find.byType(CheckboxListTile);
      await tester.scrollUntilVisible(
        checkbox,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      final button = find.text('Confirm with location');
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pump();
      expect(calls, ['prepare']);
      expect(find.text('Checking location permission…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Checking location permission…'),
                matching: find.byWidgetPredicate((w) => w is FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      permission.complete();
      await tester.pumpAndSettle();
      expect(calls, ['prepare', 'cancel']);
      expect(app.memory.current, ReportState.draft);
      await tester.scrollUntilVisible(
        find.text('Open app permissions'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Open app permissions'), findsOneWidget);
    },
  );
}
