import 'package:field_voice/field_voice.dart';

/// Small RAM-only Kokoro cache. No raw engineer audio or transcript is cached.
class PromptAudioCache implements SpeechSynthesizer {
  PromptAudioCache(this.engine);
  final SpeechSynthesizer engine;
  final _entries = <String, Future<SynthesizedAudio>>{};
  final _sizes = <String, int>{};
  void _remove(String key) {
    _entries.remove(key);
    _sizes.remove(key);
  }

  @override
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1}) {
    final key = '$speed:$text';
    final cached = _entries.remove(key);
    if (cached != null) {
      _entries[key] = cached;
      return cached;
    }
    while (_entries.length >= 12) {
      _remove(_entries.keys.first);
    }
    final result = engine.synthesize(text, speed: speed);
    _entries[key] = result;
    result.then<void>(
      (audio) {
        if (!identical(_entries[key], result)) return;
        _sizes[key] = audio.samples.lengthInBytes;
        while (_sizes.values.fold<int>(0, (a, b) => a + b) > 8 * 1024 * 1024) {
          _remove(_entries.keys.first);
        }
      },
      onError: (Object _, StackTrace _) {
        if (identical(_entries[key], result)) _remove(key);
      },
    );
    return result;
  }

  void clear() {
    _entries.clear();
    _sizes.clear();
  }
}
