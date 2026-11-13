import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/closure_voice_turn.dart';
import 'support/voice_fakes.dart';

void main() {
  final form = FormDefinition.fromJson(
    jsonDecode(
          File('../../fixtures/templates/closure-mvp.json').readAsStringSync(),
        )
        as Json,
  );
  final field = form.fields.firstWhere((f) => f.id == 'identity_verified');
  for (final uncertain in [false, true]) {
    testWidgets(
      'spoken ${uncertain ? 'uncertain' : 'explicit'} answer is reviewed before leaving the voice turn',
      (tester) async {
        final events = <String>[], audio = TestAudio(<String>[]);
        final engine = TestEngine(events)
          ..answer = uncertain ? 'I am not sure' : 'yes';
        ClosureVoiceAnswer? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.push<ClosureVoiceAnswer>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClosureVoiceTurn(
                          field: field,
                          recognizer: engine,
                          synthesizer: engine,
                          audio: audio,
                          assertAccess: () async {},
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          audio.events.indexOf('play'),
          lessThan(audio.events.indexOf('capture')),
        );
        audio.feed();
        await tester.tap(find.text('Finish answer'));
        await tester.pumpAndSettle();
        expect(result, isNull);
        expect(find.text('Check what I heard'), findsOneWidget);
        expect(engine.extractionCalls, 0);
        final action = find.text(
          uncertain ? 'Keep transcript for review' : 'Confirm this answer',
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(result!.transcript, engine.answer);
        expect(result!.answer?.toJson(), uncertain ? null : true);
      },
    );
  }
  testWidgets('a late recognition result after pause is discarded', (
    tester,
  ) async {
    final engine = TestEngine([])..recognition = Completer<String>();
    final audio = TestAudio([]);
    await tester.pumpWidget(
      MaterialApp(
        home: ClosureVoiceTurn(
          field: field,
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    audio.feed();
    await tester.tap(find.text('Finish answer'));
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    engine.recognition!.complete('yes');
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Confirm this answer'), findsNothing);
  });
}
