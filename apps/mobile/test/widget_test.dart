import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/main.dart';
import 'package:field_assist/app/app_controller.dart';

class SignedOutController extends AppController {
  @override
  AppState build() => const AppState(stage: AccessStage.signedOut);
}

void main() {
  testWidgets(
    'sign in is reachable, validates input, and supports large text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appProvider.overrideWith(SignedOutController.new)],
          child: const FieldAssistApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready for\nthe field.'), findsOneWidget);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Enter your work email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
