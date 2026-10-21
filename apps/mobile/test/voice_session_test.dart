import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/design_system/workspace.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'package:field_assist/features/voice/voice_session_screen.dart';
import 'support/voice_fakes.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'immersive ${brightness.name} voice choices save and End returns to form',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Answers values = {};
        final voice = VoiceCoordinator(
          engine: TestEngine([]),
          schema: schema,
          readValues: () => values,
          audio: TestAudio([]),
          playback: false,
          onPatch: (patch, _) async {
            values = patch.values;
          },
        );
        addTearDown(voice.shutdown);
        const capture = bool.fromEnvironment('CAPTURE_VOICE_UI');
        if (capture) {
          await tester.runAsync(() async {
            for (final family in ['Roboto', 'MaterialIcons']) {
              final file = family == 'Roboto'
                  ? 'Roboto-Regular.ttf'
                  : 'MaterialIcons-Regular.otf';
              await (FontLoader(family)..addFont(
                    File(
                      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/$file',
                    ).readAsBytes().then(ByteData.sublistView),
                  ))
                  .load();
            }
          });
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: workspaceTheme(fieldTheme(brightness: brightness)),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => VoiceSessionScreen(
                            coordinator: voice,
                            schema: schema,
                          ),
                        ),
                      ),
                      child: const Text('Open voice'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open voice'));
        await tester.pumpAndSettle();
        expect(find.text('Fully completed'), findsOneWidget);
        expect(find.text('Partially completed'), findsOneWidget);
        expect(find.text('Not completed'), findsOneWidget);
        Future<void> shot(String name) async {
          if (!capture) return;
          await tester.runAsync(() async {
            final frame =
                await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final png = await frame.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '../../docs/evidence/voice-${brightness.name}-$name.png',
            ).writeAsBytes(png!.buffer.asUint8List());
            frame.dispose();
          });
        }

        await shot('question');
        await tester.tap(find.text('Partially completed'));
        await tester.pumpAndSettle();
        expect(values['installation_outcome']!.toJson(), 'partial');
        expect(find.text('Answer saved on this device'), findsOneWidget);
        await shot('saved');
        tester.platformDispatcher.textScaleFactorTestValue = 1.6;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('End'));
        await tester.pumpAndSettle();
        expect(find.text('Open voice'), findsOneWidget);
        expect(find.text('Field Assist Voice'), findsNothing);
      },
    );
  }
}
