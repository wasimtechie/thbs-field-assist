import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:field_assist/main.dart';
import 'package:field_assist/app/app_controller.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/closure/compact_closure_screen.dart';
import 'package:field_assist/features/closure/compact_narrative.dart';
import 'package:field_assist/features/closure/visit_summary_submission.dart';
import 'package:field_assist/features/voice/speech_input.dart';
import 'guided_voice_test.dart' show resample;

class NoNetworkApi extends ApiClient {
  NoNetworkApi() : super(baseUrl: 'https://unreachable.invalid/api/v1/') {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add('DIO: ${options.path}');
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        },
      ),
    );
  }
  final requests = <String>[];
  @override
  Future<Json> send(
    String route, {
    String method = 'GET',
    Object? body,
    Map<String, String>? headers,
  }) async {
    requests.add(route);
    throw const ServiceFailure(
      'NETWORK',
      'Synthetic offline check: network disabled',
      retryable: true,
    );
  }
}

class OfflineProofController extends AppController {
  final noNetwork = NoNetworkApi();
  @override
  ApiClient get api => noNetwork;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh demo boots, recognises the S1 summary and retains a reviewed submission with every network request rejected',
    (tester) async {
      final container = ProviderContainer(
        overrides: [appProvider.overrideWith(OfflineProofController.new)],
      );
      addTearDown(container.dispose);
      final app =
          container.read(appProvider.notifier) as OfflineProofController;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const FieldAssistApp(),
        ),
      );
      final clock = Stopwatch()..start();
      while (container.read(appProvider).stage != AccessStage.ready &&
          clock.elapsed < const Duration(minutes: 3)) {
        await tester.pump(const Duration(milliseconds: 250));
        if (container.read(appProvider).error.isNotEmpty) break;
      }
      final ready = container.read(appProvider);
      expect(ready.stage, AccessStage.ready, reason: ready.error);
      expect(ready.voiceReady, true, reason: ready.notice);
      expect(ready.workOrders, hasLength(7));
      expect(
        app.noNetwork.requests,
        isEmpty,
        reason:
            'First launch must not need login, provisioning or model downloads.',
      );
      expect(app.repository.cipherVersion, isNotEmpty);
      final lease = await app.assertAccess();
      expect(lease.allowedTemplates, contains(ready.form!.templateId));
      const summary =
          'I installed the O N T in the living room. I used the existing duct for the fibre route. The optical receive reading was minus eighteen point two d B M. The service test passed. The job is fully completed. I showed the customer the equipment.';
      final data = ByteData.sublistView(
            resample(await app.voice.synthesize(summary)),
          ),
          samples = Float32List(data.lengthInBytes ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
      }
      final transcript = await app.voice.transcribe(trimSpeechSilence(samples));
      final form = compactClosureForm(ready.form!),
          facts = compactNarrativeFacts(form, transcript);
      final values = decodeAnswers({
        for (final f in facts) f['fieldId'] as String: f['value'],
      });
      expect(values['optical_rx_dbm']?.toJson(), -18.2);
      expect(values['claimed_outcome']?.toJson(), 'completed');
      expect(values['operational_test']?.toJson(), 'passed');
      expect(compactClosureLabels.keys.where((id) => missing(values[id])), [
        'serving_asset',
        'next_action',
      ]);
      final job = ready.workOrders.firstWhere((j) => j.title.startsWith('S1'));
      final report = await app.startAssignedJob(job.id);
      final reviewed = {
        ...values,
        'serving_asset': const TextAnswer('CBT-SYN-10'),
        'next_action': const TextAnswer('No further work required'),
      };
      final sources = <String, dynamic>{
        for (final f in facts) f['fieldId'] as String: f,
      };
      final queued = await app.queueVisitSummary(
        reportId: report.id,
        workOrderId: job.id,
        values: reviewed,
        sources: sources,
      );
      expect(queued['status'], 'waiting');
      while (container.read(appProvider).summarySubmissions.single['error'] ==
              null &&
          clock.elapsed < const Duration(minutes: 4)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        container.read(appProvider).summarySubmissions.single['status'],
        'waiting',
      );
      final saved =
          await app.repository.metadata(VisitSummaryOutbox.storageKey) as List;
      final id = (saved.single as Json)['id'];
      final payload = jsonEncode((saved.single as Json)['payload']);
      await app.lock();
      await app.unlock();
      expect(container.read(appProvider).stage, AccessStage.ready);
      final reopened =
          await app.repository.metadata(VisitSummaryOutbox.storageKey) as List;
      expect((reopened.single as Json)['id'], id);
      expect(jsonEncode((reopened.single as Json)['payload']), payload);
      expect((reopened.single as Json)['receipt'], isNull);
      debugPrint(
        'OFFLINE_PROOF: fresh install, signed access, 7 jobs, bundled native STT/TTS, S1 summary -> 2 missing fields, encrypted queued confirmation survives reopen. Deferred sync attempts fail safely. Transcript: $transcript',
      );
      await app.lock();
    },
  );
}
