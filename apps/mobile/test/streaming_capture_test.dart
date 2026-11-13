import 'dart:async';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/features/voice/streaming_capture.dart';

class StreamFixture implements StreamingSpeechTurn {
  final received = <double>[];
  bool voice = true, cancelled = false, finished = false;
  Completer<SpeechProgress>? pending;
  @override
  Future<SpeechProgress> add(Float32List samples) async {
    received.addAll(samples);
    return pending?.future ??
        SpeechProgress(
          text: voice ? 'The reading was minus 18.2DBM.' : '',
          heardSpeech: voice,
          speaking: voice && received.length < 6400,
          audioSeconds: received.length / 16000,
          lastSpeechSeconds: voice ? .4 : 0,
        );
  }

  @override
  Future<void> cancel() async => cancelled = true;
  @override
  Future<String> finish() async {
    finished = true;
    return voice ? 'The reading was minus 18.2DBM.' : '';
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

class QueuedSpeech extends StreamFixture {
  final first = Completer<SpeechProgress>();
  int calls = 0;
  @override
  Future<SpeechProgress> add(Float32List pcm) async {
    if (++calls == 1) return first.future;
    return const SpeechProgress(
      text: 'The service test passed.',
      heardSpeech: true,
      speaking: true,
      audioSeconds: 4,
      lastSpeechSeconds: 4,
    );
  }
}

class TextWithoutVad extends StreamFixture {
  @override
  Future<SpeechProgress> add(Float32List pcm) async {
    received.addAll(pcm);
    return SpeechProgress(
      text: received.length >= 8000 ? 'The serving asset is CBT-SYN-10.' : '',
      heardSpeech: false,
      speaking: false,
      audioSeconds: received.length / 16000,
      lastSpeechSeconds: 0,
    );
  }
}

void main() {
  test(
    'recognized text survives a missing VAD flag and gets a full pause allowance',
    () async {
      final ends = <bool>[];
      final pump = StreamingCapture(
        turn: TextWithoutVad(),
        silence: summarySpeechPause,
        noSpeech: additionalSpeechWait,
        onProgress: (_) {},
        onEnd: ends.add,
        onError: (e) => fail('$e'),
      );
      for (var i = 0; i < 12; i++) {
        pump.add(Uint8List(5120));
        await settle();
      }
      expect(pump.heardSpeech, true);
      expect(ends, isEmpty);
      for (var i = 0; i < 5; i++) {
        pump.add(Uint8List(5120));
        await settle();
      }
      expect(ends, [false]);
      await pump.cancel();
    },
  );
  test(
    'queued new speech is processed before an older quiet update can end the recording',
    () async {
      final turn = QueuedSpeech();
      final ends = <bool>[];
      final pump = StreamingCapture(
        turn: turn,
        silence: summarySpeechPause,
        noSpeech: additionalSpeechWait,
        onProgress: (_) {},
        onEnd: ends.add,
        onError: (e) => fail('$e'),
      );
      pump.add(Uint8List(5120));
      await settle();
      pump.add(Uint8List(16000));
      turn.first.complete(
        const SpeechProgress(
          text: 'The optical receive reading was -18.2 dB.',
          heardSpeech: true,
          speaking: false,
          audioSeconds: 3,
          lastSpeechSeconds: 1,
        ),
      );
      await settle();
      expect(turn.calls, 2);
      expect(ends, isEmpty);
      await pump.cancel();
    },
  );
  test(
    'PCM chunk boundaries preserve all samples and finalization drains the tail',
    () async {
      final turn = StreamFixture();
      final pcm = ByteData(10000);
      for (var i = 0; i < 5000; i++) {
        pcm.setInt16(i * 2, i - 2500, Endian.little);
      }
      final bytes = pcm.buffer.asUint8List();
      final pump = StreamingCapture(
        turn: turn,
        silence: const Duration(milliseconds: 450),
        noSpeech: const Duration(seconds: 8),
        onProgress: (_) {},
        onEnd: (_) {},
        onError: (e) => fail('$e'),
      );
      pump.add(bytes.sublist(0, 101));
      pump.add(bytes.sublist(101, 6001));
      pump.add(bytes.sublist(6001));
      expect(await pump.finish(), 'The reading was minus 18.2DBM.');
      expect(turn.received, hasLength(5000));
      for (var i = 0; i < 5000; i++) {
        expect(turn.received[i], closeTo((i - 2500) / 32768, 1e-7));
      }
      expect(turn.finished, true);
    },
  );
  test(
    'neural speech state ends a real answer once; noise does not keep it open',
    () async {
      final turn = StreamFixture();
      final ends = <bool>[];
      final pump = StreamingCapture(
        turn: turn,
        silence: const Duration(milliseconds: 450),
        noSpeech: const Duration(seconds: 8),
        onProgress: (_) {},
        onEnd: ends.add,
        onError: (e) => fail('$e'),
      );
      for (var i = 0; i < 8; i++) {
        pump.add(Uint8List(5120));
        await settle();
      }
      expect(ends, [false]);
      expect(pump.heardSpeech, true);
      await pump.finish();
    },
  );
  test(
    'no-speech is a neural decision and never fabricates a transcript',
    () async {
      final turn = StreamFixture()..voice = false;
      final ends = <bool>[];
      final pump = StreamingCapture(
        turn: turn,
        silence: const Duration(milliseconds: 450),
        noSpeech: const Duration(seconds: 2),
        onProgress: (_) {},
        onEnd: ends.add,
        onError: (e) => fail('$e'),
      );
      for (var i = 0; i < 14; i++) {
        pump.add(Uint8List(5120));
        await settle();
      }
      expect(ends, [true]);
      expect(await pump.finish(), '');
    },
  );
  test(
    'cancellation ignores late partial recognition and never ends another turn',
    () async {
      final turn = StreamFixture()..pending = Completer<SpeechProgress>();
      var updates = 0, ends = 0;
      final pump = StreamingCapture(
        turn: turn,
        silence: const Duration(milliseconds: 450),
        noSpeech: const Duration(seconds: 2),
        onProgress: (_) => updates++,
        onEnd: (_) => ends++,
        onError: (e) => fail('$e'),
      );
      pump.add(Uint8List(5120));
      await settle();
      await pump.cancel();
      turn.pending!.complete(
        const SpeechProgress(
          text: 'passed',
          heardSpeech: true,
          speaking: false,
          audioSeconds: 3,
          lastSpeechSeconds: 1,
        ),
      );
      await settle();
      expect(turn.cancelled, true);
      expect(updates, 0);
      expect(ends, 0);
    },
  );
  test(
    'an overloaded device pauses safely instead of dropping microphone frames',
    () async {
      final turn = StreamFixture()..pending = Completer<SpeechProgress>();
      final errors = <Object>[];
      final pump = StreamingCapture(
        turn: turn,
        silence: const Duration(milliseconds: 450),
        noSpeech: const Duration(seconds: 2),
        onProgress: (_) {},
        onEnd: (_) {},
        onError: errors.add,
      );
      pump.add(Uint8List(5120));
      pump.add(Uint8List(16000 * 2 * 5));
      expect(errors, hasLength(1));
      await pump.cancel();
      turn.pending!.complete(
        const SpeechProgress(
          text: '',
          heardSpeech: false,
          speaking: false,
          audioSeconds: 0,
          lastSpeechSeconds: 0,
        ),
      );
      await settle();
    },
  );
}
