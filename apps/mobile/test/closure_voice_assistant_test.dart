import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/closure_extraction.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/closure/closure_voice_turn.dart';
import 'support/voice_fakes.dart';

final form = FormDefinition.fromJson(
  jsonDecode(
        File('../../fixtures/templates/closure-mvp.json').readAsStringSync(),
      )
      as Json,
);
FieldDefinition field(String id) => form.fields.firstWhere((f) => f.id == id);

class GatedAudio extends TestAudio {
  GatedAudio(super.events, {this.gateAt = 1});
  final int gateAt;
  final playback = Completer<bool>();
  int plays = 0;
  @override
  Future<bool> play(
    SynthesizedAudio audio,
    void Function(double) onLevel,
  ) async {
    events.add('play');
    return ++plays == gateAt ? playback.future : true;
  }
}

Future<void> mount(
  WidgetTester tester,
  ClosureVoiceAssistant screen, {
  Size size = const Size(390, 844),
  double scale = 1,
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

/// Audio time, speech followed by silence: no Finish or Confirm button tap.
Future<void> utter(WidgetTester tester, TestAudio audio) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
  audio.feed();
  audio.meter!(.05);
  audio.bytes!(Uint8List(80000));
  audio.meter!(0);
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  for (final finishByTouch in [false, true]) {
    testWidgets(
      'natural spoken choices save and advance automatically, finishing by ${finishByTouch ? 'touch' : 'voice'}',
      (tester) async {
        final engine = TestEngine([])..answer = 'The work is fully completed.';
        final audio = TestAudio([]);
        final saved = <String, Answer>{};
        await mount(
          tester,
          ClosureVoiceAssistant(
            recognizer: engine,
            synthesizer: engine,
            audio: audio,
            assertAccess: () async {},
            needsNarrative: false,
            announceSavedAnswers: false,
            nextQuestion: (_) => [
              'claimed_outcome',
              'operational_test',
            ].where((id) => !saved.containsKey(id)).map(field).firstOrNull,
            proposeNarrative: (_, _) async => [],
            keepNarrative: (_, _, _) async {},
            keepAnswer: (target, response) async {
              if (response.answer != null) saved[target.id] = response.answer!;
            },
          ),
        );
        await utter(tester, audio);
        expect(saved['claimed_outcome']?.toJson(), 'completed');
        expect(
          find.text(closureSpokenQuestion(field('operational_test'))),
          findsWidgets,
        );
        engine.answer = 'The test probably passed';
        await utter(tester, audio);
        expect(saved.containsKey('operational_test'), false);
        if (finishByTouch) {
          await tester.ensureVisible(find.text('Passed'));
          await tester.tap(find.text('Passed'));
          await tester.pumpAndSettle();
        } else {
          engine.answer = 'The service test passed.';
          await utter(tester, audio);
        }
        expect(saved['operational_test']?.toJson(), 'passed');
        expect(engine.extractionCalls, 0);
        expect(
          engine.events,
          contains('speak:${closureAssistantPrompts['assistant_complete']}'),
        );
      },
    );
  }
  testWidgets(
    'anything else follows a saved summary; silence ends collection and opens review automatically',
    (tester) async {
      final engine = TestEngine([])
        ..answer = 'Installed the ONT and tested the service.';
      final audio = TestAudio([]),
          mapping = Completer<List<ClosureVoiceFact>>();
      var saved = 0;
      bool? completed;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  completed = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ClosureVoiceAssistant(
                        recognizer: engine,
                        synthesizer: engine,
                        audio: audio,
                        assertAccess: () async {},
                        needsNarrative: true,
                        collectSummaryFirst: true,
                        closeWhenComplete: true,
                        announceSavedAnswers: false,
                        completionPrompt:
                            closureAssistantPrompts['assistant_summary_complete'],
                        nextQuestion: (_) => null,
                        proposeNarrative: (_, _) => mapping.future,
                        keepNarrative: (_, _, _) async {
                          saved++;
                        },
                        keepAnswer: (_, _) async {},
                      ),
                    ),
                  );
                },
                child: const Text('Begin'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      audio.feed();
      audio.meter!(.05);
      audio.bytes!(Uint8List(80000));
      audio.meter!(0);
      await tester.pump();
      expect(engine.events, isNot(contains('speak:Anything else?')));
      expect(saved, 0);
      mapping.complete([]);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(saved, 1);
      expect(engine.events, contains('speak:Anything else?'));
      expect(find.text('Anything else?'), findsOneWidget);
      audio.bytes!(Uint8List(256000));
      audio.meter!(0);
      await tester.pumpAndSettle();
      expect(completed, true);
      expect(find.text('Begin'), findsOneWidget);
      expect(
        saved,
        1,
        reason: 'Silence is not an answer or another engineer narrative.',
      );
    },
  );
  testWidgets(
    'resetting a completed conversation ignores late recognition and restarts with the greeting',
    (tester) async {
      final engine = TestEngine([]), audio = TestAudio([]);
      final pending = Completer<String>();
      engine.recognition = pending;
      var resets = 0, writes = 0;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {
            writes++;
          },
          keepAnswer: (_, _) async {
            writes++;
          },
          resetAnswers: () async {
            resets++;
            return true;
          },
          cancelInference: engine.cancel,
        ),
      );
      await utter(tester, audio);
      expect(engine.events, contains('transcribe'));
      await tester.tap(find.text('Reset answers'));
      await tester.pumpAndSettle();
      pending.complete('open draft');
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(writes, 0);
      expect(find.text('Let’s finish your\nvisit together.'), findsOneWidget);
      expect(
        engine.events,
        contains('speak:${closureAssistantPrompts['assistant_greeting']}'),
      );
      expect(find.text('Reset answers'), findsNothing);
    },
  );

  testWidgets(
    'greeting starts automatically and finishes before microphone permission or capture',
    (tester) async {
      final engine = TestEngine([]), audio = GatedAudio([]);
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: true,
          nextQuestion: (_) => null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, _) async {},
        ),
      );
      expect(
        engine.events,
        contains('speak:${closureAssistantPrompts['assistant_greeting']}'),
      );
      expect(audio.events, isNot(contains('permission')));
      expect(audio.events, isNot(contains('capture')));
      expect(find.text('Ask me this question'), findsNothing);
      audio.playback.complete(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(audio.events, isNot(contains('capture')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(
        audio.events.indexOf('play'),
        lessThan(audio.events.indexOf('permission')),
      );
      expect(
        audio.events.indexOf('permission'),
        lessThan(audio.events.indexOf('capture')),
      );
    },
  );

  testWidgets(
    'spoken answer and silence fill draft and ask next question without any tap',
    (tester) async {
      final engine = TestEngine([])..answer = 'yes', audio = TestAudio([]);
      final saved = <ClosureVoiceAnswer>[];
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => saved.isEmpty
              ? field('identity_verified')
              : field('access_permission'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            saved.add(answer);
          },
        ),
      );
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      await utter(tester, audio);
      await tester.pumpAndSettle();
      expect(saved.single.answer?.toJson(), true);
      expect(saved.single.sourceType, 'speech');
      expect(
        engine.events,
        contains('speak:${closureSpokenQuestion(field('access_permission'))}'),
      );
      expect(find.text('Confirm answer'), findsNothing);
    },
  );

  testWidgets(
    'fast conversation waits for durable save then asks the next question without an acknowledgement',
    (tester) async {
      final engine = TestEngine([])..answer = 'yes', audio = TestAudio([]);
      final committed = Completer<void>();
      ClosureVoiceAnswer? saved;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          announceSavedAnswers: false,
          nextQuestion: (_) => saved == null
              ? field('identity_verified')
              : field('access_permission'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, value) async {
            await committed.future;
            saved = value;
          },
        ),
      );
      engine.events.clear();
      await utter(tester, audio);
      expect(saved, isNull);
      expect(engine.events.where((e) => e.startsWith('speak:')), isEmpty);
      committed.complete();
      await tester.pumpAndSettle();
      expect(saved?.answer?.toJson(), true);
      expect(engine.events.where((e) => e.startsWith('speak:')), [
        'speak:${closureSpokenQuestion(field('access_permission'))}',
      ]);
      expect(engine.extractionCalls, 0);
    },
  );

  testWidgets(
    'one option tap stops old playback, saves selection and advances automatically',
    (tester) async {
      final engine = TestEngine([]), audio = GatedAudio([]);
      ClosureVoiceAnswer? saved;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) =>
              saved == null ? field('identity_verified') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            saved = answer;
          },
        ),
      );
      await tester.ensureVisible(find.text('No'));
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(saved!.answer?.toJson(), false);
      expect(saved!.sourceType, 'manual');
      audio.playback.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Open my draft'), findsOneWidget);
      expect(engine.events.where((e) => e == 'transcribe'), isEmpty);
    },
  );

  testWidgets(
    'narrative is drafted automatically then missing checks are asked',
    (tester) async {
      final engine = TestEngine([])
            ..answer = 'Installed ONT. Optical receive -18.2 dBm.',
          audio = TestAudio([]);
      Set<String>? proposed;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: true,
          nextQuestion: (_) => field('identity_verified'),
          proposeNarrative: (text, _) async => [
            ClosureVoiceFact(field('actual_work'), {'value': text}),
            ClosureVoiceFact(field('optical_rx_dbm'), {'value': -18.2}),
          ],
          keepNarrative: (_, _, ids) async {
            proposed = ids;
          },
          keepAnswer: (_, _) async {},
        ),
      );
      await utter(tester, audio);
      await tester.pumpAndSettle();
      expect(proposed, {'actual_work', 'optical_rx_dbm'});
      expect(
        engine.events,
        contains('speak:${closureSpokenQuestion(field('identity_verified'))}'),
      );
    },
  );

  testWidgets(
    'unclear speech stays unanswered and a selected option then advances',
    (tester) async {
      final engine = TestEngine([])..answer = 'I am not sure',
          audio = TestAudio([]);
      var accepted = false;
      final answers = <ClosureVoiceAnswer>[];
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => accepted ? null : field('identity_verified'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            answers.add(answer);
            accepted = answer.answer != null;
          },
        ),
      );
      await utter(tester, audio);
      await tester.pumpAndSettle();
      expect(answers.single.answer, isNull);
      expect(accepted, false);
      expect(
        engine.events,
        contains(
          'speak:${closureClarification(field('identity_verified'), 'I am not sure', 1)}',
        ),
      );
      expect(find.text('Yes'), findsOneWidget);
      await tester.ensureVisible(find.text('Yes'));
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(answers.last.answer?.toJson(), true);
      expect(find.text('Open my draft'), findsOneWidget);
    },
  );

  testWidgets('spoken no is a negative answer and not a retry command', (
    tester,
  ) async {
    final engine = TestEngine([])..answer = 'No.', audio = TestAudio([]);
    Answer? saved;
    await mount(
      tester,
      ClosureVoiceAssistant(
        recognizer: engine,
        synthesizer: engine,
        audio: audio,
        assertAccess: () async {},
        needsNarrative: false,
        nextQuestion: (_) => saved == null ? field('access_permission') : null,
        proposeNarrative: (_, _) async => [],
        keepNarrative: (_, _, _) async {},
        keepAnswer: (_, answer) async {
          saved = answer.answer;
        },
      ),
    );
    await utter(tester, audio);
    await tester.pumpAndSettle();
    expect(saved?.toJson(), false);
    expect(find.text('Open my draft'), findsOneWidget);
  });

  testWidgets('repeat, pause, resume and skip work by voice alone', (
    tester,
  ) async {
    final engine = TestEngine([])..answer = 'repeat', audio = TestAudio([]);
    final kept = <ClosureVoiceAnswer>[];
    await mount(
      tester,
      ClosureVoiceAssistant(
        recognizer: engine,
        synthesizer: engine,
        audio: audio,
        assertAccess: () async {},
        needsNarrative: false,
        nextQuestion: (skipped) => skipped.contains('identity_verified')
            ? null
            : field('identity_verified'),
        proposeNarrative: (_, _) async => [],
        keepNarrative: (_, _, _) async {},
        keepAnswer: (_, answer) async {
          kept.add(answer);
        },
      ),
    );
    await utter(tester, audio);
    await tester.pumpAndSettle();
    expect(kept, isEmpty);
    engine.answer = 'pause';
    await utter(tester, audio);
    await tester.pumpAndSettle();
    expect(find.text('Paused'), findsOneWidget);
    engine.answer = 'resume';
    await utter(tester, audio);
    await tester.pumpAndSettle();
    expect(find.text('Yes'), findsOneWidget);
    engine.answer = 'skip';
    await utter(tester, audio);
    await tester.pumpAndSettle();
    expect(kept.single.answer, isNull);
    expect(find.text('Open my draft'), findsOneWidget);
  });

  testWidgets(
    'failed write preserves the answer and spoken retry saves before advancing',
    (tester) async {
      final engine = TestEngine([])..answer = 'yes', audio = TestAudio([]);
      var attempts = 0, saved = false;
      String? savedTranscript;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => saved ? null : field('identity_verified'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            if (++attempts == 1) throw StateError('disk full');
            savedTranscript = answer.transcript;
            saved = true;
          },
        ),
      );
      await utter(tester, audio);
      await tester.pumpAndSettle();
      expect(saved, false);
      expect(find.textContaining('Could not save.'), findsOneWidget);
      engine.answer = 'retry';
      await utter(tester, audio);
      await tester.pumpAndSettle();
      expect(saved, true, reason: 'attempts=$attempts events=${engine.events}');
      expect(attempts, 2);
      expect(savedTranscript, 'yes');
      expect(find.text('Open my draft'), findsOneWidget);
    },
  );

  testWidgets('late recognition after pause cannot fill or advance', (
    tester,
  ) async {
    final engine = TestEngine([])..recognition = Completer<String>(),
        audio = TestAudio([]);
    var writes = 0;
    await mount(
      tester,
      ClosureVoiceAssistant(
        recognizer: engine,
        synthesizer: engine,
        audio: audio,
        assertAccess: () async {},
        needsNarrative: false,
        nextQuestion: (_) => field('identity_verified'),
        proposeNarrative: (_, _) async => [],
        keepNarrative: (_, _, _) async {},
        keepAnswer: (_, _) async {
          writes++;
        },
      ),
    );
    await utter(tester, audio);
    await tester.pump();
    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();
    engine.recognition!.complete('yes');
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Resume conversation'), findsOneWidget);
  });

  testWidgets(
    'numeric fallback submits signed reading automatically and never invents Not measured as zero',
    (tester) async {
      final engine = TestEngine([]), audio = TestAudio([]);
      ClosureVoiceAnswer? kept;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => kept == null ? field('optical_rx_dbm') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            kept = answer;
          },
        ),
      );
      expect(find.text('Not measured'), findsOneWidget);
      await tester.ensureVisible(find.byType(TextField));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('TYPE YOUR ANSWER · VOICE PAUSED'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '-18.2');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(kept!.answer?.toJson(), -18.2);
      expect(kept!.sourceType, 'manual');
      expect(kept!.inputMethod, 'typed');
      expect(
        engine.events,
        contains('speak:${closureAssistantPrompts['assistant_answer_saved']}'),
      );
      expect(
        engine.events.where(
          (e) => e.startsWith('speak:') && e.contains('-18.2'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'narrative acknowledgement stays visible during real playback before the next question',
    (tester) async {
      final engine = TestEngine([])..answer = 'Installed ONT.',
          audio = GatedAudio([], gateAt: 2);
      var writes = 0;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: true,
          nextQuestion: (_) => field('identity_verified'),
          proposeNarrative: (text, _) async => [
            ClosureVoiceFact(field('actual_work'), {'value': text}),
          ],
          keepNarrative: (_, _, _) async {
            writes++;
          },
          keepAnswer: (_, _) async {},
        ),
      );
      await utter(tester, audio);
      expect(writes, 1);
      expect(find.text('Added to your draft.'), findsOneWidget);
      expect(find.text('Installed ONT.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      audio.playback.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Yes'), findsOneWidget);
    },
  );

  testWidgets(
    'opening the draft during a saved acknowledgement keeps the original answer source',
    (tester) async {
      final engine = TestEngine([])..answer = 'yes',
          audio = GatedAudio([], gateAt: 3);
      final kept = <ClosureVoiceAnswer>[];
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => kept.isEmpty ? field('identity_verified') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            kept.add(answer);
          },
        ),
      );
      await utter(tester, audio);
      expect(kept, hasLength(1));
      expect(find.text('Added to your draft.'), findsOneWidget);
      await tester.tap(find.byTooltip('Close voice assistant'));
      await tester.pumpAndSettle();
      audio.playback.complete(true);
      await tester.pumpAndSettle();
      expect(kept, hasLength(1));
      expect(kept.single.answer?.toJson(), true);
    },
  );

  testWidgets(
    'opening draft while narrative extraction is pending preserves the spoken summary only',
    (tester) async {
      final engine = TestEngine([])..answer = 'Installed ONT.',
          audio = TestAudio([]);
      final extraction = Completer<List<ClosureVoiceFact>>();
      String? retained;
      Set<String>? selected;
      var writes = 0;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: true,
          nextQuestion: (_) => field('identity_verified'),
          proposeNarrative: (_, _) => extraction.future,
          keepNarrative: (text, _, ids) async {
            retained = text;
            selected = ids;
            writes++;
          },
          keepAnswer: (_, _) async {},
        ),
      );
      await utter(tester, audio);
      await tester.tap(find.byTooltip('Close voice assistant'));
      await tester.pumpAndSettle();
      extraction.complete([
        ClosureVoiceFact(field('ont_fitted'), {'value': true}),
      ]);
      await tester.pumpAndSettle();
      expect(retained, 'Installed ONT.');
      expect(selected, isEmpty);
      expect(writes, 1);
    },
  );

  testWidgets(
    'spoken not measured skips the reading without fabricating zero',
    (tester) async {
      final engine = TestEngine([])..answer = 'Not measured.',
          audio = TestAudio([]);
      ClosureVoiceAnswer? kept;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (skipped) => skipped.contains('optical_rx_dbm')
              ? null
              : field('optical_rx_dbm'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            kept = answer;
          },
        ),
      );
      await utter(tester, audio);
      expect(kept!.answer, isNull);
      expect(kept!.transcript, 'Not measured.');
      expect(kept!.sourceType, 'speech');
      expect(find.text('Open my draft'), findsOneWidget);
      engine.answer = 'repeat';
      await utter(tester, audio);
      expect(find.text('Open my draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'selecting an option supersedes pending recognition and retains manual provenance',
    (tester) async {
      final engine = TestEngine([])..recognition = Completer<String>(),
          audio = TestAudio([]);
      final kept = <ClosureVoiceAnswer>[];
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => kept.isEmpty ? field('identity_verified') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            kept.add(answer);
          },
        ),
      );
      await utter(tester, audio);
      expect(engine.events, contains('transcribe'));
      await tester.ensureVisible(find.text('No'));
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      engine.recognition!.complete('yes');
      await tester.pumpAndSettle();
      expect(kept, hasLength(1));
      expect(kept.single.answer?.toJson(), false);
      expect(kept.single.sourceType, 'manual');
      expect(kept.single.inputMethod, 'option');
      expect(find.text('Open my draft'), findsOneWidget);
    },
  );

  testWidgets(
    'interruption during a write waits for the commit and resumes without duplication',
    (tester) async {
      final engine = TestEngine([])..answer = 'yes', audio = TestAudio([]);
      final committed = Completer<void>();
      var writes = 0, saved = false;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => saved ? null : field('identity_verified'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, _) async {
            writes++;
            await committed.future;
            saved = true;
          },
        ),
      );
      await utter(tester, audio);
      expect(writes, 1);
      audio.interruption!();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume conversation'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      committed.complete();
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(saved, true);
      expect(find.text('Open my draft'), findsOneWidget);
    },
  );

  testWidgets('control-only pause ignores answers until resume', (
    tester,
  ) async {
    final engine = TestEngine([])..answer = 'pause', audio = TestAudio([]);
    var writes = 0;
    await mount(
      tester,
      ClosureVoiceAssistant(
        recognizer: engine,
        synthesizer: engine,
        audio: audio,
        assertAccess: () async {},
        needsNarrative: false,
        nextQuestion: (_) => field('identity_verified'),
        proposeNarrative: (_, _) async => [],
        keepNarrative: (_, _, _) async {},
        keepAnswer: (_, _) async {
          writes++;
        },
      ),
    );
    await utter(tester, audio);
    engine.answer = 'yes';
    await utter(tester, audio);
    expect(writes, 0);
    expect(find.text('Paused'), findsOneWidget);
    engine.answer = 'resume';
    await utter(tester, audio);
    expect(find.text('ANSWER ALOUD OR CHOOSE BELOW'), findsOneWidget);
  });

  testWidgets(
    'small screen with keyboard keeps typed fallback scrollable without overflow',
    (tester) async {
      final engine = TestEngine([]), audio = TestAudio([]);
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => field('optical_rx_dbm'),
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, _) async {},
        ),
        size: const Size(320, 568),
        keyboardInset: 300,
      );
      await tester.ensureVisible(find.byType(TextField));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('Voice paused while typing'), findsOneWidget);
      expect(audio.events.last, 'stop-playback');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'enum choices appear and large text on a small screen has no overflow',
    (tester) async {
      final engine = TestEngine([]), audio = TestAudio([]);
      Answer? saved;
      await mount(
        tester,
        ClosureVoiceAssistant(
          recognizer: engine,
          synthesizer: engine,
          audio: audio,
          assertAccess: () async {},
          needsNarrative: false,
          nextQuestion: (_) => saved == null ? field('optical_test') : null,
          proposeNarrative: (_, _) async => [],
          keepNarrative: (_, _, _) async {},
          keepAnswer: (_, answer) async {
            saved = answer.answer;
          },
        ),
        size: const Size(320, 568),
        scale: 1.5,
      );
      expect(find.text('Passed'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Not tested'), findsOneWidget);
      await tester.ensureVisible(find.text('Not tested'));
      await tester.tap(find.text('Not tested'));
      await tester.pumpAndSettle();
      expect(saved?.toJson(), 'not_tested');
      expect(tester.takeException(), isNull);
    },
  );

  test('numeric readings preserve sign and uncertainty is not guessed', () {
    expect(
      closureSpokenAnswer(
        field('optical_rx_dbm'),
        'minus 18 point two dBm',
      )?.toJson(),
      -18.2,
    );
    expect(
      closureSpokenAnswer(
        field('optical_rx_dbm'),
        'minus eighteen point 2 dBm',
      )?.toJson(),
      -18.2,
    );
    expect(
      closureSpokenAnswer(
        field('optical_rx_dbm'),
        'minus eighteen point two dBm',
      )?.toJson(),
      -18.2,
    );
    expect(
      closureSpokenAnswer(field('blockage_distance'), '13.5 metres')?.toJson(),
      13.5,
    );
    for (final text in [
      'about minus eighteen',
      '-18 or -19 dBm',
      'not measured',
      'I think -18.2 dBm',
    ]) {
      expect(closureSpokenAnswer(field('optical_rx_dbm'), text), isNull);
    }
    expect(
      closureSpokenValue(field('optical_rx_dbm'), const NumberAnswer(-18.2)),
      'minus 18.2 dBm',
    );
  });
  test(
    'explicit yes/no variants preserve negatives without guessing qualifications',
    () {
      for (final text in ['yes I have', 'yes we did', "yes that's correct"]) {
        expect(
          closureSpokenAnswer(field('identity_verified'), text)?.toJson(),
          true,
        );
      }
      for (final text in ["no I haven't", 'no we have not', "no we didn't"]) {
        expect(
          closureSpokenAnswer(field('identity_verified'), text)?.toJson(),
          false,
        );
      }
      for (final text in [
        'yes maybe',
        "I think it's verified",
        'not sure',
        'no, actually yes',
      ]) {
        expect(
          closureSpokenAnswer(field('identity_verified'), text),
          isNull,
          reason: text,
        );
      }
    },
  );
  test(
    'automatic narrative fill leaves qualified facts unresolved and keeps explicit negatives',
    () {
      Json? fact(String text, String id) => literalClosureFacts(
        text,
      ).where((f) => f['fieldId'] == id).firstOrNull;
      expect(
        fact('I have not installed an ONT.', 'ont_fitted')?['value'],
        isNull,
      );
      expect(fact('I think RX -18.2 dBm.', 'optical_rx_dbm')?['value'], isNull);
      expect(fact('No hazards. Installed ONT.', 'ont_fitted')?['value'], true);
      expect(
        fact('No hazards. Installed ONT.', 'safety_hazard')?['value'],
        false,
      );
      expect(
        fact('Drilling consent was not granted.', 'drilling_consent')?['value'],
        false,
      );
    },
  );
}
