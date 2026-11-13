import 'dart:convert';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/settings/voice_picker.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'compact_closure_test.dart' as compact;
import 'question_voice_test.dart' show VoiceAssets;
import 'support/voice_fakes.dart';

class AuditionEngine extends TestEngine {
  AuditionEngine() : super([]);
  @override
  Future<SynthesizedAudio> synthesizeVoice(
    String text, {
    required String voiceId,
    double speed = 1,
  }) {
    events.add('audition:$voiceId');
    return synthesize(text, speed: speed);
  }
}

class VoiceController extends compact.CompactController {
  final audition = AuditionEngine();
  @override
  TestEngine get voice => audition;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
    'voice selection persists, auditions play and greeting variants advance',
    (tester) async {
      final audio = TestAudio([]);
      final container = ProviderContainer(
        overrides: [
          appProvider.overrideWith(VoiceController.new),
          voiceAudioFactoryProvider.overrideWithValue(() => audio),
        ],
      );
      addTearDown(container.dispose);
      final app = container.read(appProvider.notifier) as VoiceController;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VoicePicker(
                  bundle: VoiceAssets({
                    'assets/voice_questions/index.json': Uint8List.fromList(
                      utf8.encode('{}'),
                    ),
                  }),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('AI voice'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('select-voice-bf_emma')),
      );
      await tester.tap(find.byKey(const ValueKey('select-voice-bf_emma')));
      await tester.pumpAndSettle();
      expect(container.read(appProvider).speechVoiceId, 'bf_emma');
      expect(app.voice.speechVoiceId, 'bf_emma');
      expect(
        (app.records.data['settings'] as Json)['speechVoiceId'],
        'bf_emma',
      );
      await tester.ensureVisible(find.byTooltip('Preview Michael'));
      await tester.tap(find.byTooltip('Preview Michael'));
      await tester.pumpAndSettle();
      expect(audio.events, contains('play'));
      expect(
        container.read(appProvider).speechVoiceId,
        'bf_emma',
        reason: 'An audition must not select a different voice',
      );
      expect(await app.nextVoiceGreetingIndex(), 0);
      expect(await app.nextVoiceGreetingIndex(), 1);
      expect(await app.nextVoiceGreetingIndex(), 2);
      expect(await app.nextVoiceGreetingIndex(), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'editing spoken summary remaps inferred readings and retains original speech',
    (tester) async {
      const old =
          'I installed the ONT. Optical receive -18.2 dBm. The service test passed. The job is fully completed.';
      const corrected =
          'I installed the ONT. Optical receive -18.19 dBm. The service test failed. The job is fully completed.';
      final records = compact.CompactReports();
      records.data['closure-demo-summary:closure-test'] = {
        'values': {
          'actual_work': old,
          'claimed_outcome': 'completed',
          'optical_rx_dbm': -18.2,
          'operational_test': 'passed',
        },
        'sources': {
          'actual_work': {'sourceType': 'speech', 'sourceSpan': old},
          for (final id in [
            'claimed_outcome',
            'optical_rx_dbm',
            'operational_test',
          ])
            id: {
              'sourceType': 'speech',
              'derivedFrom': 'actual_work',
              'derivedSummary': old,
            },
        },
      };
      final container = ProviderContainer(
        overrides: [
          appProvider.overrideWith(
            () => compact.CompactController(records: records),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: fieldTheme(),
            home: CompactClosureScreen(
              reportId: 'closure-test',
              fullChecklist: () => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit spoken words').first);
      await tester.tap(find.text('Edit spoken words').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work done').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('edited-transcript')),
        corrected,
      );
      await tester.ensureVisible(find.text('Save & update form'));
      await tester.tap(find.text('Save & update form'));
      await tester.pumpAndSettle();
      final saved = records.data['closure-demo-summary:closure-test'] as Json;
      expect((saved['values'] as Json)['actual_work'], corrected);
      expect((saved['values'] as Json)['optical_rx_dbm'], -18.19);
      expect((saved['values'] as Json)['operational_test'], 'failed');
      expect(
        saved['sources']['actual_work']['originalSpeech']['sourceSpan'],
        old,
      );
      expect(saved['reviewedAt'], isNull);
      await tester.tap(find.text('Review 5-field summary'));
      await tester.pumpAndSettle();
      expect(find.text('Review visit summary'), findsOneWidget);
      expect(find.text('Edit spoken words'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
