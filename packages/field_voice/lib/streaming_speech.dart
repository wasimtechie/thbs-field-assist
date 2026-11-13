import 'dart:typed_data';

/// A recognition update from real PCM, including neural Silero speech state.
class SpeechProgress {
  const SpeechProgress({
    required this.text,
    required this.heardSpeech,
    required this.speaking,
    required this.audioSeconds,
    required this.lastSpeechSeconds,
    this.inferenceMilliseconds = 0,
  });
  final String text;
  final bool heardSpeech, speaking;
  final double audioSeconds, lastSpeechSeconds;
  final int inferenceMilliseconds;

  factory SpeechProgress.fromMap(Map map) => SpeechProgress(
    text: map['text'] as String,
    heardSpeech: map['heardSpeech'] as bool,
    speaking: map['speaking'] as bool,
    audioSeconds: (map['audioSeconds'] as num).toDouble(),
    lastSpeechSeconds: (map['lastSpeechSeconds'] as num).toDouble(),
    inferenceMilliseconds: map['inferenceMilliseconds'] as int? ?? 0,
  );
}

abstract interface class StreamingSpeechRecognizer {
  bool get streamingAvailable;
  Future<StreamingSpeechTurn> startSpeechTurn();
}

abstract interface class StreamingSpeechTurn {
  /// Calls are serialized by the caller; bounded chunks prevent a native queue
  /// of stale microphone audio from delaying the next question.
  Future<SpeechProgress> add(Float32List samples);
  Future<String> finish();
  Future<void> cancel();
}
