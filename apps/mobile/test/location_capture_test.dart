import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/location/location_capture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('field_assist/location');
  Json fix({DateTime? time}) => ReportLocation(
    latitude: 0,
    longitude: 0,
    accuracyMeters: 3000,
    capturedAt: time ?? DateTime.now().toUtc(),
    isMocked: true,
  ).toJson();
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'permission is awaited before GPS and duplicate taps cannot cancel it',
    () async {
      final permission = Completer<void>(), entered = Completer<void>();
      final calls = <String>[], stages = <LocationCaptureStage>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'prepare') {
          entered.complete();
          await permission.future;
        }
        return call.method == 'capture' ? fix() : null;
      });
      final first = const LocationCapture().capture(onStage: stages.add);
      await entered.future;
      await expectLater(
        const LocationCapture().capture(),
        throwsA(
          isA<LocationCaptureFailure>().having(
            (e) => e.code,
            'code',
            'LOCATION_BUSY',
          ),
        ),
      );
      expect(calls, ['prepare']);
      expect(stages, [LocationCaptureStage.permission]);
      permission.complete();
      await first;
      expect(calls, ['prepare', 'capture', 'cancel']);
      expect(stages, [
        LocationCaptureStage.permission,
        LocationCaptureStage.locating,
      ]);
    },
  );

  test(
    'permission denial does not start GPS and a subsequent attempt can recover',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'prepare') {
          throw PlatformException(code: 'PERMISSION_DENIED');
        }
        return null;
      });
      await expectLater(
        const LocationCapture().capture(),
        throwsA(isA<LocationCaptureFailure>()),
      );
      expect(calls, ['prepare', 'cancel']);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'capture' ? fix() : null,
      );
      await const LocationCapture().capture();
    },
  );

  test(
    'zero coordinates and approximate accuracy survive the native boundary',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'capture' ? fix() : null;
      });
      final result = await const LocationCapture().capture();
      expect(result.latitude, 0);
      expect(result.longitude, 0);
      expect(result.accuracyMeters, 3000);
      expect(result.isMocked, isTrue);
      expect(calls, ['prepare', 'capture', 'cancel']);
    },
  );
  for (final code in [
    'LOCATION_DISABLED',
    'PERMISSION_DENIED',
    'LOCATION_TIMEOUT',
  ]) {
    test(
      '$code preserves an actionable failure and cancels the request',
      () async {
        var cancelled = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'capture') {
            throw PlatformException(
              code: code,
              message: 'Your draft is saved.',
            );
          }
          if (call.method == 'cancel') cancelled = true;
          return null;
        });
        await expectLater(
          const LocationCapture().capture(),
          throwsA(
            isA<LocationCaptureFailure>().having((e) => e.code, 'code', code),
          ),
        );
        expect(cancelled, isTrue);
      },
    );
  }
  test(
    'old native fixes cannot be silently stamped with a new capture time',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'capture'
            ? fix(
                time: DateTime.now().toUtc().subtract(
                  const Duration(minutes: 5),
                ),
              )
            : null,
      );
      await expectLater(
        const LocationCapture().capture(),
        throwsA(
          isA<LocationCaptureFailure>().having(
            (e) => e.code,
            'code',
            'LOCATION_INVALID',
          ),
        ),
      );
    },
  );
  test('invalid coordinates and unknown accuracy are rejected', () {
    for (final entry in [
      {'latitude': 91},
      {'longitude': 181},
      {'accuracyMeters': -1},
      {'latitude': double.nan},
    ]) {
      expect(
        () => ReportLocation.fromJson({...fix(), ...entry}),
        throwsFormatException,
      );
    }
  });
  test(
    'a queued snapshot can be read days later without recapturing location',
    () {
      final raw = fix(time: DateTime.utc(2026, 10, 1));
      expect(ReportLocation.fromJson(raw).toJson(), raw);
      expect(
        () => ReportLocation.fromJson(
          raw,
        ).requireFresh(DateTime.utc(2026, 10, 15)),
        throwsFormatException,
      );
    },
  );
}
