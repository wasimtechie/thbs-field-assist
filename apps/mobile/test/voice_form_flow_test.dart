import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/persistence/report_repository.dart';
import 'package:field_assist/features/forms/form_screen.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'package:field_assist/features/voice/voice_coordinator.dart';
import 'package:field_assist/features/voice/voice_session_screen.dart';
import 'package:field_assist/features/voice/conversation.dart';
import 'appearance_journey_test.dart' as fixture;
import 'support/voice_fakes.dart';

class SpokenFormController extends fixture.DesignController {
  final store = fixture.MemoryReports()..values = {};
  final engine = TestEngine([]);
  @override
  SecureReportRepository get repository => store;
  @override
  FieldVoice get voice => engine;
  @override
  AppState build() => super.build().copy(voiceReady: true, playback: false);
  @override
  Future<void> reloadReports() async {
    final report = await store.get('test-report-001');
    if (ref.mounted) state = state.copy(reports: [report]);
  }
}

void main() {
  test(
    'explicit spoken quantities and negative readings keep units, decimals and uncertainty',
    () {
      final length = schema.fields.firstWhere((f) => f.id == 'cable_installed');
      final optical = schema.fields.firstWhere(
        (f) => f.id == 'optical_reading',
      );
      for (final input in [
        'Twelve metres.',
        '12 meters',
        'I installed twelve metres',
        'twelve',
      ]) {
        expect(directSpokenAnswer(length, input)!.toJson(), {
          'amount': 12,
          'unit': 'm',
        });
      }
      for (final input in [
        'minus twenty two point four',
        'Minus 22.4.',
        '-22.4 dBm',
      ]) {
        expect(directSpokenAnswer(optical, input)!.toJson(), -22.4);
      }
      for (final input in [
        'twelve or thirteen metres',
        'did not replace twelve metres',
        'about twelve metres',
        'twelve feet',
        'not sure',
      ]) {
        expect(directSpokenAnswer(length, input), isNull);
      }
    },
  );
  test(
    'ending waits for recognition and durable save instead of discarding speech',
    () async {
      Answers values = {};
      final audio = TestAudio([]), engine = TestEngine([]);
      engine.recognition = Completer<String>();
      final saved = Completer<void>(), committing = Completer<void>();
      final voice = VoiceCoordinator(
        engine: engine,
        schema: schema,
        readValues: () => values,
        playback: false,
        audio: audio,
        onPatch: (patch, _) async {
          committing.complete();
          await saved.future;
          values = patch.values;
        },
      );
      addTearDown(voice.shutdown);
      await voice.begin();
      audio.feed();
      final ending = voice.finishAndPause();
      engine.recognition!.complete('Partially completed');
      await committing.future;
      expect(values, isEmpty);
      expect(voice.savedMessage, isEmpty);
      saved.complete();
      await ending;
      expect(values['installation_outcome']!.toJson(), 'partial');
      expect(voice.state, VoiceState.paused);
      expect(voice.savedValues['Installation outcome'], 'Partial');
      expect(audio.events.where((e) => e == 'capture'), hasLength(1));
    },
  );

  for (final confirmByTouch in [false, true]) {
    test(
      'approximate quantity requires ${confirmByTouch ? 'touch' : 'spoken'} confirmation before saving',
      () async {
        Answers values = decodeAnswers({
          'installation_outcome': 'partial',
          'work_performed': 'Synthetic work',
        });
        final engine = TestEngine([])..answer = 'Around thirty meters.';
        final audio = TestAudio([]);
        var writes = 0;
        final voice = VoiceCoordinator(
          engine: engine,
          schema: schema,
          readValues: () => values,
          audio: audio,
          playback: false,
          onPatch: (patch, source) async {
            writes++;
            expect(source, confirmByTouch ? 'manual' : 'voice');
            values = patch.values;
          },
        );
        addTearDown(voice.shutdown);
        await voice.begin();
        audio.feed();
        await voice.finish();
        expect(voice.activeField!.id, 'cable_installed');
        expect(voice.suggestedValue, '30 m');
        expect(voice.question, contains('Should I record 30 m'));
        expect(values['cable_installed'], isNull);
        expect(writes, 0);
        expect(voice.savedMessage, isEmpty);
        if (confirmByTouch) {
          await voice.confirmNumericSuggestion();
        } else {
          engine.answer = 'Yes.';
          audio.feed();
          await voice.finish();
        }
        expect(values['cable_installed']!.toJson(), {
          'amount': 30,
          'unit': 'm',
        });
        expect(writes, 1);
        expect(voice.numericSuggestion, isNull);
        expect(engine.extractionCalls, 0);
      },
    );
  }
  test('declining an estimated value asks again without writing it', () async {
    Answers values = decodeAnswers({
      'installation_outcome': 'partial',
      'work_performed': 'Synthetic work',
    });
    final engine = TestEngine([])..answer = 'About thirty metres';
    final audio = TestAudio([]);
    final voice = VoiceCoordinator(
      engine: engine,
      schema: schema,
      readValues: () => values,
      audio: audio,
      playback: false,
      onPatch: (patch, _) async => values = patch.values,
    );
    addTearDown(voice.shutdown);
    await voice.begin();
    audio.feed();
    await voice.finish();
    engine.answer = 'No';
    audio.feed();
    await voice.finish();
    expect(voice.numericSuggestion, isNull);
    expect(values['cable_installed'], isNull);
    expect(voice.activeField!.id, 'cable_installed');
    engine.answer = 'Twenty eight metres';
    audio.feed();
    await voice.finish();
    expect(values['cable_installed']!.toJson(), {'amount': 28, 'unit': 'm'});
  });

  test('optional questions are asked and can be explicitly skipped', () async {
    final source = {
      ...schema.source,
      'fields': [
        ...schema.source['fields'] as List,
        {
          'id': 'notes',
          'sectionId': 'work',
          'order': 20,
          'type': 'long_text',
          'label': 'Extra notes',
          'required': false,
          'voice': {
            'enabled': true,
            'question': 'Any extra notes?',
            'description': 'Optional engineer notes.',
          },
        },
      ],
    };
    final form = FormDefinition.fromJson(source);
    Answers values = decodeAnswers({
      'installation_outcome': 'partial',
      'work_performed': 'Synthetic work',
      'cable_installed': {'amount': 12, 'unit': 'm'},
      'connectivity_test': 'not_tested',
      'exception_reason': 'Customer absent',
    });
    final voice = VoiceCoordinator(
      engine: TestEngine([]),
      schema: form,
      readValues: () => values,
      audio: TestAudio([]),
      playback: false,
      onPatch: (patch, _) async => values = patch.values,
    );
    addTearDown(voice.shutdown);
    await voice.begin();
    expect(voice.activeField!.id, 'notes');
    expect(voice.question, 'Any extra notes?');
    await voice.skipOptional();
    expect(voice.state, VoiceState.readyToReview);
    expect(values.containsKey('notes'), isFalse);
  });

  for (final completed in [false, true]) {
    testWidgets(
      '${completed ? 'completed' : 'partial'} voice answers fill actual form controls, refresh reports and reopen',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final audio = TestAudio([]);
        final container = ProviderContainer(
          overrides: [
            appProvider.overrideWith(SpokenFormController.new),
            voiceAudioFactoryProvider.overrideWithValue(() => audio),
          ],
        );
        addTearDown(container.dispose);
        container.read(appProvider);
        final app =
            container.read(appProvider.notifier) as SpokenFormController;
        Widget screen(String key) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            key: ValueKey(key),
            theme: fieldTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const FormScreen(reportId: 'test-report-001'),
          ),
        );
        await tester.pumpWidget(screen('first'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fill by voice'));
        await tester.pumpAndSettle();
        final session = tester
            .widget<VoiceSessionScreen>(find.byType(VoiceSessionScreen))
            .coordinator;
        final answers = <String, String>{
          'installation_outcome': completed
              ? 'Fully completed'
              : 'Partially completed',
          'work_performed': 'Installed cable and checked the route',
          'cable_installed': 'Twelve metres',
          if (completed) 'optical_reading': 'Minus 22.4',
          'connectivity_test': 'Not tested',
          if (!completed) 'exception_reason': 'The customer was unavailable',
        };
        for (final entry in answers.entries) {
          expect(session.activeField?.id, entry.key);
          app.engine.answer = entry.value;
          final endDuringAnswer = !completed && entry.key == answers.keys.last;
          if (endDuringAnswer) app.engine.recognition = Completer<String>();
          audio.feed();
          if (endDuringAnswer) {
            await tester.tap(find.text('End'));
            await tester.pump();
            expect(find.text('Finishing…'), findsOneWidget);
            app.engine.recognition!.complete(entry.value);
          } else {
            await tester.tap(find.text('Done speaking'));
          }
          await tester.pumpAndSettle();
          expect(session.changed, contains(entry.key));
          expect(app.store.values[entry.key], isNotNull);
        }
        expect(app.engine.extractionCalls, 0);
        if (completed) expect(session.question, contains('ONT serial number'));
        if (completed) {
          await tester.tap(find.text('End'));
          await tester.pumpAndSettle();
        }
        expect(find.byType(VoiceSessionScreen), findsNothing);
        Future<void> controlsAreFilled() async {
          final text = tester
              .widgetList<EditableText>(find.byType(EditableText))
              .map((w) => w.controller.text)
              .toList();
          expect(text, contains('Installed cable and checked the route'));
          expect(text, contains('12'));
          expect(
            text,
            contains(completed ? '-22.4' : 'The customer was unavailable'),
          );
          final selected = tester
              .widgetList<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .map((w) => w.initialValue)
              .toList();
          expect(selected, contains(completed ? 'completed' : 'partial'));
          await tester.scrollUntilVisible(
            find.textContaining('Connectivity test', findRichText: true),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            tester
                .widgetList<DropdownButtonFormField<String>>(
                  find.byType(DropdownButtonFormField<String>),
                )
                .map((w) => w.initialValue),
            contains('not_tested'),
          );
        }

        await controlsAreFilled();
        expect(
          container
              .read(appProvider)
              .reports
              .single
              .values['cable_installed']!
              .toJson(),
          {'amount': 12, 'unit': 'm'},
        );
        await tester.pumpWidget(screen('reopened'));
        await tester.pumpAndSettle();
        await controlsAreFilled();
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
}
