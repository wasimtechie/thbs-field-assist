import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:field_voice/field_voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/design_system/theme.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/closure_voice_assistant.dart';
import 'package:field_assist/features/offline_access/entitlement.dart';
import 'package:field_assist/features/voice/pcm_meter.dart';
import 'package:field_assist/features/voice/voice_audio.dart';
import 'offline_demo_test.dart' show NoNetworkApi;
import 'guided_voice_test.dart' show resample;

// Controlled SOFTWARE end-to-end test, not an acoustic phone benchmark.
// The real CompactClosureScreen, AppController, Moonshine/Silero, extraction,
// signed access checks, encrypted save, question voice/cache and native player
// are retained. Only microphone acquisition is replaced by paced synthetic PCM.
// Run on a separate simulator; never submit or alter presentation reports.
class TurnTrace {
  final clock = Stopwatch()..start();
  final events = <String, int>{};
  final access = <int>[];
  final saves = <int>[];
  final audible = Completer<int>();
  int? speechEndUs;
  void mark(String name) =>
      events.putIfAbsent(name, () => clock.elapsedMicroseconds);
  int relative(int at) => ((at - speechEndUs!) / 1000).round();
}

class TimingController extends AppController {
  final offlineApi = NoNetworkApi();
  TurnTrace? trace;
  @override
  ApiClient get api => offlineApi;

  @override
  Future<OfflineLease> assertAccess() async {
    final watch = Stopwatch()..start();
    final result = await super.assertAccess();
    final current = trace;
    if (current?.speechEndUs != null && !current!.audible.isCompleted) {
      current.access.add(watch.elapsedMilliseconds);
    }
    return result;
  }

  @override
  Future<void> saveSummaryDraft(
    String reportId,
    Json snapshot, {
    required String ownerId,
  }) async {
    final current = trace;
    if (current?.speechEndUs != null) current!.mark('saveStarted');
    final watch = Stopwatch()..start();
    await super.saveSummaryDraft(reportId, snapshot, ownerId: ownerId);
    if (current?.speechEndUs != null && !current!.audible.isCompleted) {
      current.saves.add(watch.elapsedMilliseconds);
      current.mark('saveCompleted');
    }
  }
}

class PacedReplayAudio implements VoiceAudio {
  final output = DeviceVoiceAudio();
  Future<void>? _closing;
  TurnTrace? trace;
  void Function(Uint8List)? input;
  void Function(double)? meter;
  int captureNumber = 0, serial = 0;
  static const channel = MethodChannel('field_assist/voice_playback');

  @override
  Future<void> configure(void Function() interrupted) =>
      output.configure(interrupted);
  @override
  Future<bool> hasPermission() async => true; // This adapter never opens a mic.
  @override
  Future<void> capture({
    required void Function(Uint8List) onBytes,
    required void Function(double) onLevel,
    required void Function(Object) onError,
  }) async {
    serial++;
    captureNumber++;
    input = onBytes;
    meter = onLevel;
  }

  @override
  Future<void> stopCapture() async {
    if (trace?.speechEndUs != null) trace!.mark('captureStopRequested');
    serial++;
    input = null;
    meter = null;
    await output.stopCapture();
  }

  @override
  Future<bool> play(
    SynthesizedAudio audio,
    void Function(double) onLevel,
  ) async {
    final active = trace;
    final measured =
        active?.speechEndUs != null && !active!.audible.isCompleted;
    var done = false;
    if (measured) {
      active.mark('playRequested');
      // First 20 ms output window with RMS >= .004, matching input threshold.
      final frameSamples = audio.sampleRate ~/ 50;
      var firstVoice = -1;
      for (var at = 0; at < audio.samples.length; at += frameSamples) {
        final end = math.min(at + frameSamples, audio.samples.length);
        var power = 0.0;
        for (var i = at; i < end; i++) {
          power += audio.samples[i] * audio.samples[i];
        }
        if (math.sqrt(power / (end - at)) >= .004) {
          firstVoice = at;
          break;
        }
      }
      if (firstVoice < 0) throw StateError('Reply contains no voiced audio.');
      final firstSeconds = firstVoice / audio.sampleRate;
      unawaited(() async {
        try {
          while (!done && !active.audible.isCompleted) {
            final position = await channel.invokeMapMethod<String, dynamic>(
              'diagnosticPlaybackPosition',
            );
            if (position?['playing'] == true &&
                (position!['seconds'] as num) >= firstSeconds) {
              active.mark('firstVoicedPlaybackCursor');
              active.audible.complete(active.clock.elapsedMicroseconds);
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        } catch (error, stack) {
          if (!active.audible.isCompleted) {
            active.audible.completeError(error, stack);
          }
        }
      }());
    }
    try {
      return await output.play(audio, onLevel);
    } finally {
      done = true;
    }
  }

  // Deliver one 20 ms frame at a time in wall-clock time. Ground truth is the
  // delivery of the last voiced frame, not the recognizer's own endpoint.
  Future<void> answer(Uint8List pcm, {TurnTrace? measure}) async {
    final captured = serial, emit = input!, level = meter!;
    var lastVoicedEnd = 0;
    for (var at = 0; at + 640 <= pcm.length; at += 640) {
      PcmLevelMeter((rms) {
        if (rms >= .004) lastVoicedEnd = at + 640;
      }).add(Uint8List.sublistView(pcm, at, at + 640));
    }
    if (lastVoicedEnd == 0) throw StateError('Fixture has no speech.');
    final bytes = Uint8List(pcm.length + 32000 * 8)..setAll(0, pcm);
    final timer = Stopwatch()..start(), levels = PcmLevelMeter(level);
    for (var at = 0; at < bytes.length && serial == captured; at += 640) {
      final end = math.min(at + 640, bytes.length);
      final targetUs = end * 1000000 ~/ 32000;
      final remaining = targetUs - timer.elapsedMicroseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(microseconds: remaining));
      }
      if (serial != captured) break;
      if (measure != null && at < lastVoicedEnd && end >= lastVoicedEnd) {
        measure.speechEndUs = measure.clock.elapsedMicroseconds;
      }
      final chunk = Uint8List.sublistView(bytes, at, end);
      emit(chunk);
      levels.add(chunk);
    }
  }

  @override
  Future<void> stopPlayback() => output.stopPlayback();
  @override
  Future<void> close() => _closing ??= () async {
    await stopCapture();
    await output.close();
  }();
}

Future<void> until(bool Function() predicate, {int seconds = 60}) async {
  final clock = Stopwatch()..start();
  while (!predicate()) {
    if (clock.elapsed.inSeconds >= seconds) {
      throw TimeoutException(
        'Voice timing checkpoint',
        Duration(seconds: seconds),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'offline current-app speech end to first native voiced reply',
    (tester) async {
      expect(
        Platform.isIOS,
        isTrue,
        reason: 'Native AVAudioPlayer cursor probe is iOS-only.',
      );
      await tester.runAsync(() async {
        final probe = await PacedReplayAudio.channel.invokeMapMethod<String, dynamic>('diagnosticPlaybackPosition');
        expect(probe?['playing'], false);
      });
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(TimingController.new)],
      );
      final app = container.read(appProvider.notifier) as TimingController;
      final root = GlobalKey<NavigatorState>();
      PacedReplayAudio? activeAudio;
      final scope = ProviderContainer(
        parent: container,
        overrides: [
          voiceAudioFactoryProvider.overrideWithValue(() => activeAudio!),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: scope,
          child: MaterialApp(
              theme: fieldTheme(),
            navigatorKey: root,
            home: const Scaffold(body: Text('Offline voice response timing')),
          ),
        ),
      );
      await tester.runAsync(
        () => until(
          () => container.read(appProvider).stage == AccessStage.ready && container.read(appProvider).voiceReady,
          seconds: 180,
        ),
      );
      expect(
        container.read(appProvider).voiceReady,
        true,
        reason: container.read(appProvider).notice,
      );
      final form = container.read(appProvider).form!,
          owner = container.read(appProvider).user!.id;
      final records = <Json>[];
      const initial = <String, dynamic>{
        'actual_work':
            'Installed the ONT in the living room using the existing duct.',
        'claimed_outcome': 'completed',
      };
      const summary =
          'I installed the O N T in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two d B M. The service test passed. The job is fully completed. I showed the customer the equipment.';
      const prime =
          'I installed the O N T in the living room. I used the existing duct for the fibre route. The job is fully completed.';
      final cases =
          <
            ({
              String id,
              String words,
              Json initial,
              Json expected,
              String? prime,
            })
          >[
            (
              id: 'short-optical',
              words: 'Minus eighteen point two d B M.',
              initial: initial,
              expected: {'optical_rx_dbm': -18.2},
              prime: null,
            ),
            (
              id: 'short-choice',
              words: 'Passed.',
              initial: {...initial, 'optical_rx_dbm': -18.2},
              expected: {'operational_test': 'passed'},
              prime: null,
            ),
            (
              id: 'corrected-optical',
              words:
                  'The reading is eighteen point two. No, sorry. The final reading is minus eighteen point one nine d B M.',
              initial: initial,
              expected: {'optical_rx_dbm': -18.19},
              prime: null,
            ),
            (
              id: 's1-summary',
              words: summary,
              initial: {},
              expected: {
                'optical_rx_dbm': -18.2,
                'claimed_outcome': 'completed',
                'operational_test': 'passed',
              },
              prime: null,
            ),
            (
              id: 'after-anything-else',
              words:
                  'The optical receive reading was minus eighteen point one nine d B M. The service test passed.',
              initial: {},
              expected: {
                'optical_rx_dbm': -18.19,
                'operational_test': 'passed',
              },
              prime: prime,
            ),
          ];
      final fixtures = <String, Uint8List>{};
      await tester.runAsync(() async {
        for (final words in {...cases.map((c) => c.words), prime}) {
          fixtures[words] = resample(
            await app.voice.synthesizeVoice(words, voiceId: 'am_michael'),
          );
        }
      });
      const repeats = int.fromEnvironment(
        'TURN_TIMING_REPEATS',
        defaultValue: 5,
      );
      for (var iteration = 0; iteration < repeats; iteration++) {
        for (final scenario in cases) {
          final report = await app.repository.create(
            form,
            (await app.assertAccess()).id,
          );
          await app.saveSummaryDraft(report.id, {
            'formatVersion': 1,
            'kind': 'six-field-demo-summary',
            'reportId': report.id,
            'values': scenario.initial,
            'sources': {
              for (final e in scenario.initial.entries)
                e.key: {
                  'sourceType': 'manual',
                  'sourceSpan': e.value.toString(),
                },
            },
            'operationalClosureApproved': false,
          }, ownerId: owner);
          final audio = PacedReplayAudio();
          activeAudio = audio;
          unawaited(
            root.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => CompactClosureScreen(
                  reportId: report.id,
                  fullChecklist: () => const SizedBox.shrink(),
                ),
              ),
            ),
          );
          final openWatch = Stopwatch()..start();
          while (find.text('Fill with voice AI').evaluate().isEmpty &&
              openWatch.elapsed.inSeconds < 15) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(find.text('Fill with voice AI'), findsOneWidget);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Fill with voice AI'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Fill with voice AI'));
          await tester.pump();
          await tester.runAsync(() => until(() => audio.input != null));
          if (scenario.prime != null) {
            await tester.runAsync(() async {
              final before = audio.captureNumber;
              await audio.answer(fixtures[scenario.prime]!);
              await until(
                () => audio.captureNumber > before && audio.input != null,
              );
            });
          }
          final trace = TurnTrace();
          audio.trace = trace;
          app.trace = trace;
          debugPrint('TURN_TIMING_START ${scenario.id} ${iteration + 1}');
          await tester.runAsync(() async {
            final feeding = audio.answer(
              fixtures[scenario.words]!,
              measure: trace,
            );
            await trace.audible.future.timeout(const Duration(seconds: 90));
            await feeding;
          });
          final saved =
              await app.repository.metadata('closure-demo-summary:${report.id}')
                  as Json;
          final values = saved['values'] as Json;
          // Keep clarification/unmatched turns in the latency sample. A fast
          // reply does not establish that the requested field was filled.
          final matches = scenario.expected.entries.every((e) => values[e.key] == e.value);
          final assistantText = find.descendant(of: find.byType(ClosureVoiceAssistant), matching: find.byType(Text))
              .evaluate().map((e) => (e.widget as Text).data).whereType<String>().toList();
          final record = <String, dynamic>{
            'case': scenario.id,
            'iteration': iteration + 1,
            'speechEndToVoicedReplyMs': trace.relative(
              await trace.audible.future,
            ),
            'eventsMs': {
              for (final e in trace.events.entries)
                e.key: trace.relative(e.value),
            },
            'accessChecksMs': trace.access,
            'durableSavesMs': trace.saves,
            'savedValues': values,
            'expectedValues': scenario.expected,
            'expectedValuesVerified': matches,
            'assistantScreenText': assistantText,
            'speechSources': saved['sources'],
          };
          records.add(record);
          debugPrint('SPEECH_TO_SPEECH_SAMPLE ${jsonEncode(record)}');
          audio.trace = null;
          app.trace = null;
          root.currentState!.popUntil((route) => route.isFirst);
          await tester.pumpAndSettle();
          await tester.runAsync(() => audio.close());
        }
      }
      final evidence = <String, dynamic>{
        'measuredAt': DateTime.now().toUtc().toIso8601String(),
        'scope':
            'iOS simulator debug on host Mac; controlled synthetic speech delivered at real-time pace into the production capture boundary, with the actual compact form/assistant/controller, native streaming STT/VAD, structured extraction, Keychain/ES256 checks, SQLCipher saves and default question voice/native AVAudioPlayer. No network or microphone. Output detected from native playing cursor crossing the first voiced reply frame; not a speaker/microphone acoustic measurement or physical-phone performance.',
        'inputFrameMs': 20,
        'voicedRmsThreshold': .004,
        'outputPollMs': 10,
        'modelsResidentBeforeTurns': true,
        'defaultVoice': 'bm_george',
        'speechRate': 1,
        'samples': records,
        'networkRequests': app.offlineApi.requests,
      };
      // The adapter rejects transport before I/O. Record blocked background
      // sign-in attempts rather than discarding completed offline voice turns.
      binding.reportData = evidence;
      debugPrint('SPEECH_TO_SPEECH_EVIDENCE ${jsonEncode(evidence)}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await app.voice.unload();
        await app.repository.close();
      });
      scope.dispose();
      container.dispose();
    },
    timeout: const Timeout(Duration(minutes: 25)),
  );
}
