import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:field_voice/field_voice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/closure_speech.dart';
import 'package:field_assist/features/closure/structured_visit_extraction.dart';
import 'package:field_assist/features/templates/asset_installer.dart';
import 'package:field_assist/features/voice/streaming_capture.dart';
import 'guided_voice_test.dart' show resample;

class DiagnosticExtractor implements FieldExtractor {
  DiagnosticExtractor(this.delegate);
  final FieldExtractor delegate;
  @override
  Future<Json> extract(String text, List<Json> tools, String context) async {
    final watch = Stopwatch()..start();
    try {
      final result = await delegate.extract(text, tools, context);
      debugPrint(
        'NEEDLE_NATIVE_RESULT: ${jsonEncode({'ms': watch.elapsedMilliseconds, 'result': result})}',
      );
      return result;
    } catch (error) {
      debugPrint(
        'NEEDLE_NATIVE_ERROR: ${jsonEncode({'ms': watch.elapsedMilliseconds, 'error': error.toString()})}',
      );
      rethrow;
    }
  }
}

/// Actual arm64 runtime and bundled weights. No microphone, authentication,
/// report writes, submission or backend connection is used by this diagnostic.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'offline native Moonshine, Silero and Needle fill only grounded fields',
    (tester) async {
      await tester.runAsync(() async {
        final snapshot =
            jsonDecode(
                  await rootBundle.loadString(
                    'assets/offline_demo/bootstrap.json',
                  ),
                )
                as Json;
        expect(snapshot['formatVersion'], 2);
        final directory = await AssetInstaller(
          ApiClient(baseUrl: 'http://127.0.0.1:1/api/v1/'),
        ).installBundled(snapshot, (_) {});
        final engine = FieldVoice();
        await engine.load(directory);
        expect(engine.streamingAvailable, true);
        expect(engine.summaryExtractor, isA<NeedleVisitExtractor>());
        await engine.smokeTest();
        final form = compactClosureForm(
          FormDefinition.fromJson(snapshot['template'] as Json),
        );
        final extractor = StructuredVisitExtractor(
          DiagnosticExtractor(engine.summaryExtractor),
        );
        final records = <Json>[];
        const cases = [
          (
            's1-summary',
            'I installed the O N T in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two d B M. The service test passed. The job is fully completed. I showed the customer the equipment.',
            true,
          ),
          (
            'reading-fragment',
            'The reading was minus eighteen point two d B M. The service test passed. The job is fully completed.',
            false,
          ),
          ('asset', 'C B T dash S Y N dash one zero.', false),
          ('short-no', 'No.', false),
          (
            'negative',
            'I have not completed the job. The service test did not pass.',
            true,
          ),
        ];
        for (final (id, words, noisy) in cases) {
          final speech = resample(await engine.synthesize(words));
          final bytes = ByteData(speech.length + 32000 * 4);
          bytes.buffer.asUint8List().setRange(
            9600 * 2,
            9600 * 2 + speech.length,
            speech,
          );
          if (noisy) {
            final random = math.Random(42);
            for (var i = 0; i < bytes.lengthInBytes ~/ 2; i++) {
              final signal = bytes.getInt16(i * 2, Endian.little) / 32768;
              final noise =
                  .007 * math.sin(2 * math.pi * 100 * i / 16000) +
                  (random.nextDouble() * 2 - 1) * .006;
              bytes.setInt16(
                i * 2,
                ((signal + noise).clamp(-1, 1) * 32767).round(),
                Endian.little,
              );
            }
          }
          final finished = Completer<bool>();
          var partials = 0;
          final watch = Stopwatch()..start();
          final capture = StreamingCapture(
            turn: await engine.startSpeechTurn(),
            silence: ['asset', 'short-no'].contains(id)
                ? answerSpeechPause
                : summarySpeechPause,
            noSpeech: const Duration(seconds: 8),
            onProgress: (value) {
              if (value.text.isNotEmpty) partials++;
            },
            onEnd: (empty) {
              if (!finished.isCompleted) finished.complete(empty);
            },
            onError: (error) {
              if (!finished.isCompleted) finished.completeError(error);
            },
          );
          final pcm = bytes.buffer.asUint8List();
          for (
            var at = 0;
            at < pcm.length && !finished.isCompleted;
            at += 640
          ) {
            capture.add(
              Uint8List.sublistView(pcm, at, (at + 640).clamp(0, pcm.length)),
            );
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          expect(
            finished.isCompleted,
            true,
            reason: '$id must detect the end without a tap',
          );
          expect(await finished.future, false);
          final text = await capture.finish();
          final finalized = watch.elapsedMilliseconds;
          final facts = await extractor.extract(
            form,
            text,
            current: () => true,
          );
          final values = {
            for (final fact in facts) fact['fieldId']: fact['value'],
          };
          if (id == 'short-no') {
            expect(
              summaryFinished(text),
              true,
              reason:
                  'A short no must end summary collection without another retry.',
            );
          } else if (id == 'asset') {
            expect(
              closureSpokenAnswer(
                form.fields.firstWhere((f) => f.id == 'serving_asset'),
                text,
              )?.toJson(),
              'CBT-SYN-10',
            );
          } else if (id == 'negative') {
            expect(values['claimed_outcome'], isNull);
            expect(values['operational_test'], isNull);
          } else {
            expect(values['claimed_outcome'], 'completed', reason: text);
            expect(values['operational_test'], 'passed', reason: text);
            expect(values['optical_rx_dbm'], -18.2, reason: text);
            expect(
              compactClosureLabels.keys.where((key) => values[key] == null),
              ['serving_asset', 'next_action'],
            );
          }
          expect(partials, greaterThan(0));
          final record = {
            'case': id,
            'transcript': text,
            'values': values,
            'partialUpdates': partials,
            'finalizationWallMs': finalized,
            'extractionMs': watch.elapsedMilliseconds - finalized,
          };
          records.add(record);
          debugPrint('MOONSHINE_DEVICE_NATIVE: ${jsonEncode(record)}');
        }
        for (final text in [
          'I finished all the work. Connectivity checks were successful.',
          'I completed all of the work. The service checks were successful.',
        ]) {
          final watch = Stopwatch()..start();
          final facts = await extractor.extract(
            form,
            text,
            current: () => true,
          );
          final values = {
            for (final fact in facts) fact['fieldId']: fact['value'],
          };
          expect(values['claimed_outcome'], 'completed', reason: text);
          expect(values['operational_test'], 'passed', reason: text);
          debugPrint(
            'NEEDLE_DEVICE_NATIVE: ${jsonEncode({'transcript': text, 'values': values, 'elapsedMs': watch.elapsedMilliseconds})}',
          );
        }
        final silence = await engine.startSpeechTurn();
        final empty = await silence.add(Float32List(16000 * 2));
        expect(empty.heardSpeech, false);
        expect(empty.text, isEmpty);
        expect(await silence.finish(), isEmpty);
        await engine.unload();
        debugPrint(
          'MOONSHINE_OFFLINE_NATIVE_PASSED: ${records.length} speech cases, 2 semantic cases, silence and model readiness.',
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
