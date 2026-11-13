import 'dart:async';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';

// Long reports need sentence/thinking pauses; short field answers stay fast.
const summarySpeechPause = Duration(milliseconds: 1800);
const answerSpeechPause = Duration(milliseconds: 450);
const additionalSpeechWait = Duration(seconds: 8);

/// Serialized, bounded microphone -> Moonshine/Silero pump. Recognition runs
/// during speech, while only a finalized transcript can be saved to the form.
class StreamingCapture {
  StreamingCapture({
    required this.turn,
    required this.onProgress,
    required this.onEnd,
    required this.onError,
    required this.silence,
    required this.noSpeech,
    this.silenceFor,
  });
  final StreamingSpeechTurn turn;
  final void Function(SpeechProgress) onProgress;
  final void Function(bool noSpeech) onEnd;
  final void Function(Object) onError;
  final Duration silence, noSpeech;
  final Duration Function(SpeechProgress)? silenceFor;
  final _pending = BytesBuilder(copy: false);
  Future<void>? _draining;
  bool _stopped = false, _closing = false, _notified = false;
  Object? _failure;
  bool heardSpeech = false;
  String _lastText = '';
  double _lastTextSeconds = 0;

  void add(Uint8List bytes) {
    if (_stopped || _closing || _failure != null) return;
    if (_pending.length + bytes.length > 16000 * 2 * 4) {
      _fail(StateError('Speech processing is falling behind on this device.'));
      return;
    }
    _pending.add(bytes);
    if (_draining == null && _pending.length >= 5120) {
      _draining = _drain().whenComplete(() => _draining = null);
    }
  }

  void _fail(Object error) {
    if (_stopped || _failure != null) return;
    _failure = error;
    onError(error);
  }

  Future<void> _drain({bool all = false}) async {
    try {
      while (!_stopped &&
          _failure == null &&
          _pending.length >= (all ? 2 : 5120)) {
        final bytes = _pending.takeBytes();
        final count = (bytes.length.clamp(0, 16000) ~/ 2) * 2;
        if (count < bytes.length) {
          _pending.add(Uint8List.sublistView(bytes, count));
        }
        final data = ByteData.sublistView(bytes, 0, count);
        final samples = Float32List(count ~/ 2);
        for (var i = 0; i < samples.length; i++) {
          samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
        }
        final progress = await turn.add(samples);
        if (_stopped || _failure != null) return;
        final recognized = progress.text.trim();
        if (recognized.isNotEmpty && recognized != _lastText) {
          _lastText = recognized;
          _lastTextSeconds = progress.audioSeconds;
        }
        heardSpeech =
            heardSpeech || progress.heardSpeech || recognized.isNotEmpty;
        onProgress(progress);
        // A newer microphone frame may already be waiting behind inference.
        // Process it before deciding that an older silent frame ends the turn.
        if (!_notified && !_closing && _pending.length < 5120) {
          final empty =
              !heardSpeech &&
              progress.audioSeconds >= noSpeech.inMicroseconds / 1000000;
          final quiet =
              heardSpeech &&
              !progress.speaking &&
              progress.audioSeconds -
                      (progress.heardSpeech
                          ? progress.lastSpeechSeconds
                          : _lastTextSeconds) >=
                  (silenceFor?.call(progress) ?? silence).inMicroseconds /
                      1000000;
          if (empty || quiet) {
            _notified = true;
            onEnd(empty);
          }
        }
      }
    } catch (error) {
      _fail(error);
    }
  }

  Future<String> finish() async {
    _closing = true;
    await _draining;
    await _drain(all: true);
    if (_failure != null) throw _failure!;
    if (_stopped) throw StateError('Speech capture cancelled.');
    _stopped = true;
    return turn.finish();
  }

  Future<void> cancel() async {
    if (_stopped) return;
    _stopped = true;
    _pending.clear();
    await turn.cancel();
  }
}
