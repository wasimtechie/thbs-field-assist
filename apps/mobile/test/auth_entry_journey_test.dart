import 'dart:async';
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
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/design_system/appearance.dart';
import 'package:field_assist/features/authentication/access_screens.dart';

class EntryController extends AppController {
  final submitted = <(String, String)>[];
  final waiting = Completer<void>();
  @override
  AppState build() =>
      const AppState(stage: AccessStage.signedOut, reduceMotion: true);
  @override
  Future<void> signIn(String email, String password) async {
    submitted.add((email, password));
    state = state.copy(busy: true);
    await waiting.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<ProviderContainer> setup(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = ProviderContainer(
      overrides: [appProvider.overrideWith(EntryController.new)],
    );
    addTearDown(container.dispose);
    container.read(appearanceProvider);
    await container
        .read(appearanceProvider.notifier)
        .select(
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const FieldAssistApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        180,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'access guidance and password help preserve typed credentials without submitting them',
    (tester) async {
      final container = await setup(tester);
      await tapVisible(tester, find.byTooltip('Change appearance'));
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Dark'));
      expect(
        Theme.of(tester.element(find.byType(SignInScreen))).brightness,
        Brightness.dark,
      );
      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Light'));
      expect(
        Theme.of(tester.element(find.byType(SignInScreen))).brightness,
        Brightness.light,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'demo.engineer@example.invalid',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Synthetic password',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isTrue,
      );
      await tapVisible(tester, find.byTooltip('Show password'));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).obscureText,
        isFalse,
      );
      await tapVisible(tester, find.byTooltip('Hide password'));
      await tapVisible(tester, find.text('Forgot password?'));
      expect(find.text('Let’s get you back in'), findsOneWidget);
      await tapVisible(tester, find.text('Got it'));
      await tapVisible(tester, find.text('Get access'));
      expect(find.text('A place on your team.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(
        (container.read(appProvider.notifier) as EntryController).submitted,
        isEmpty,
      );
      await tapVisible(tester, find.text('I have my details'));
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(0))
            .controller!
            .text,
        'demo.engineer@example.invalid',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        'Synthetic password',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard submit trims email, preserves password and blocks duplicate sign-in',
    (tester) async {
      final container = await setup(tester, size: const Size(360, 740));
      await tester.enterText(
        find.byType(TextFormField).at(0),
        '  demo.engineer@example.invalid  ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        ' Synthetic password ',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      final controller =
          container.read(appProvider.notifier) as EntryController;
      expect(controller.submitted, [
        ('demo.engineer@example.invalid', ' Synthetic password '),
      ]);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
        isFalse,
      );
      expect(find.text('Signing in…'), findsOneWidget);
      controller.waiting.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} entry supports a narrow screen, keyboard inset and large text',
      (tester) async {
        await setup(
          tester,
          brightness: brightness,
          size: const Size(320, 640),
          scale: 1.6,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Sign in'));
        expect(find.text('Enter your work email.'), findsOneWidget);
        expect(find.text('Enter your password.'), findsOneWidget);
        await tapVisible(tester, find.text('Get access'));
        await tapVisible(tester, find.text('I have my details'));
        await tester.scrollUntilVisible(
          find.text('Welcome back.'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Welcome back.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'render the real light and dark authentication screens for visual review',
    (tester) async {
      if (!const bool.fromEnvironment('CAPTURE_AUTH_UI')) return;
      await tester.runAsync(() async {
        for (final family in ['Roboto', 'Ahem', 'MaterialIcons']) {
          final file = family == 'MaterialIcons'
              ? 'MaterialIcons-Regular.otf'
              : 'Roboto-Regular.ttf';
          final fonts = FontLoader(family)
            ..addFont(
              File(
                '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/$file',
              ).readAsBytes().then((b) => ByteData.sublistView(b)),
            );
          await fonts.load();
        }
      });
      tester.view.physicalSize = const Size(780, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      Widget phone(Brightness brightness) => Expanded(
        child: ProviderScope(
          overrides: [appProvider.overrideWith(EntryController.new)],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: fieldTheme(brightness: brightness),
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(390, 844),
                padding: EdgeInsets.only(top: 24, bottom: 16),
                disableAnimations: true,
              ),
              child: SignInScreen(),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [phone(Brightness.light), phone(Brightness.dark)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> save(String name) async {
        await tester.runAsync(() async {
          final picture =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            '../../docs/evidence/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }

      await save('auth-redesign-signin');
      for (var i = 0; i < 2; i++) {
        await tapVisible(tester, find.text('Get access').first);
      }
      await save('auth-redesign-access');
      expect(tester.takeException(), isNull);
    },
  );
}
