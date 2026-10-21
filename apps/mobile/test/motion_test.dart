import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/design_system/theme.dart';

void main() {
  Widget surface(Widget child, {bool reduced = false}) => MaterialApp(
    theme: fieldTheme(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets(
    'press, release, cancel and disabled buttons preserve activation',
    (tester) async {
      var actions = 0;
      await tester.pumpWidget(
        surface(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () => actions++,
                child: const Text('Save'),
              ),
              const OutlinedButton(onPressed: null, child: Text('Disabled')),
            ],
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Save')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(actions, 0);
      final transform = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(TactileFeedback).first,
              matching: find.byType(Transform),
            ),
          )
          .first;
      expect(transform.transform.storage[13], greaterThan(0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(actions, 1);
      final cancel = await tester.startGesture(
        tester.getCenter(find.text('Save')),
      );
      await cancel.moveTo(const Offset(1, 1));
      await cancel.up();
      await tester.pumpAndSettle();
      expect(actions, 1);
      await tester.tap(find.text('Disabled'));
      await tester.pumpAndSettle();
      expect(actions, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard activation and reduced motion use the same controls', (
    tester,
  ) async {
    var actions = 0;
    await tester.pumpWidget(
      surface(
        FilledButton(
          autofocus: true,
          onPressed: () => actions++,
          child: const Text('Review'),
        ),
        reduced: true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 80));
    final transforms = tester.widgetList<Transform>(
      find.descendant(
        of: find.byType(TactileFeedback),
        matching: find.byType(Transform),
      ),
    );
    expect(transforms.every((t) => t.transform.isIdentity()), isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(tester.takeException(), isNull);
  });

  test('light appearance retains the original primary and voice colors', () {
    final light = fieldTheme();
    expect(light.colorScheme.primary, const Color(0xff6554c8));
    expect(light.colorScheme.secondary, const Color(0xff1c9a89));
    expect(light.scaffoldBackgroundColor, const Color(0xfff6f7fb));
    expect(
      fieldTheme(brightness: Brightness.dark).colorScheme.brightness,
      Brightness.dark,
    );
  });
}
