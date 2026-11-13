/// Speaker mapping for the already bundled, pinned Kokoro English v0.19 model.
/// https://k2-fsa.github.io/sherpa/onnx/tts/all/English/kokoro-en-v0_19.html
class OfflineSpeechVoice {
  const OfflineSpeechVoice(
    this.id,
    this.speakerId,
    this.name,
    this.description,
  );
  final String id, name, description;
  final int speakerId;
}

const offlineSpeechVoices = [
  OfflineSpeechVoice('bm_george', 9, 'George', 'British English · Male'),
  OfflineSpeechVoice('bf_emma', 7, 'Emma', 'British English · Female'),
  OfflineSpeechVoice('am_michael', 6, 'Michael', 'American English · Male'),
  OfflineSpeechVoice('af_sarah', 3, 'Sarah', 'American English · Female'),
];

OfflineSpeechVoice? offlineSpeechVoice(String? id) {
  for (final voice in offlineSpeechVoices) {
    if (voice.id == id) return voice;
  }
  return null;
}

const speechVoicePreview =
    'Hi. I am your Field Assist voice. Tell me what you did, and I will help finish your report.';
