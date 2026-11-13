import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/features/closure/question_voice.dart';
import 'package:field_assist/features/voice/voice_audio.dart';

class FallbackSpeech implements SpeechSynthesizer {
  int calls = 0;
  double? lastSpeed;
  @override
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1}) async {
    calls++;
    lastSpeed = speed;
    return SynthesizedAudio(Float32List.fromList([.25, -.25]), 16000);
  }
}

class VoiceAssets extends CachingAssetBundle {
  VoiceAssets(this.files);
  final Map<String, Uint8List> files;
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(files[key]!);
}

void main() {
  test(
    'a selected voice never borrows a default-speaker recording and custom speed uses synthesis',
    () async {
      const text = 'A short question.';
      final key = sha256.convert(utf8.encode(text)).toString();
      final wav = encodeVoiceWav(
        SynthesizedAudio(Float32List.fromList([.3, -.3]), 24000),
      );
      final defaultEntry = {
        'model': attentiveSpeechModel,
        'voice': attentiveSpeechVoice,
        'settings': {
          'speakerId': attentiveSpeechSpeakerId,
          'speed': attentiveSpeechSpeed,
          'backgroundAudio': false,
        },
        'prompts': {
          key: {
            'text': text,
            'file': '$key.wav',
            'sha256': sha256.convert(wav).toString(),
          },
        },
      };
      final fallback = FallbackSpeech();
      final assets = VoiceAssets({
        'assets/voice_questions/index.json': Uint8List.fromList(
          utf8.encode(jsonEncode(defaultEntry)),
        ),
        'assets/voice_questions/$key.wav': wav,
      });
      await QuestionVoice(
        fallback,
        bundle: assets,
        voiceId: 'bf_emma',
      ).synthesize(text);
      expect(fallback.calls, 1);
      await QuestionVoice(fallback, bundle: assets, rate: 1.2).synthesize(text);
      expect(fallback.calls, 2);
      expect(fallback.lastSpeed, 1.2);
    },
  );

  test(
    'matching selected-speaker entries play the verified selected voice',
    () async {
      const text = 'Hello from Emma.';
      final key = sha256.convert(utf8.encode(text)).toString();
      final wav = encodeVoiceWav(
        SynthesizedAudio(Float32List.fromList([.4, -.4]), 24000),
      );
      final assets = VoiceAssets({
        'assets/voice_questions/index.json': Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'voices': {
                'bf_emma': {
                  'model': attentiveSpeechModel,
                  'voice': 'bf_emma',
                  'settings': {
                    'speakerId': 7,
                    'speed': attentiveSpeechSpeed,
                    'backgroundAudio': false,
                  },
                  'prompts': {
                    key: {
                      'text': text,
                      'file': 'bf_emma-$key.wav',
                      'sha256': sha256.convert(wav).toString(),
                    },
                  },
                },
              },
            }),
          ),
        ),
        'assets/voice_questions/bf_emma-$key.wav': wav,
      });
      final fallback = FallbackSpeech();
      final result = await QuestionVoice(
        fallback,
        bundle: assets,
        voiceId: 'bf_emma',
      ).synthesize(text);
      expect(result.sampleRate, 24000);
      expect(fallback.calls, 0);
    },
  );
  test(
    'an exact, integrity-checked question plays without loading a synthesis model',
    () async {
      const text = 'Was permission confirmed? Say yes or no.';
      final key = sha256.convert(utf8.encode(text)).toString();
      final wav = encodeVoiceWav(
        SynthesizedAudio(Float32List.fromList([.5, -.5]), 24000),
      );
      final assets = VoiceAssets({
        'assets/voice_questions/index.json': Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'model': attentiveSpeechModel,
              'voice': attentiveSpeechVoice,
              'settings': {
                'speakerId': attentiveSpeechSpeakerId,
                'speed': attentiveSpeechSpeed,
                'backgroundAudio': false,
              },
              'prompts': {
                key: {
                  'text': text,
                  'file': '$key.wav',
                  'sha256': sha256.convert(wav).toString(),
                },
              },
            }),
          ),
        ),
        'assets/voice_questions/$key.wav': wav,
      });
      final fallback = FallbackSpeech();
      final cached = QuestionVoice(fallback, bundle: assets);
      final audio = await cached.synthesize(text);
      expect(audio.sampleRate, 24000);
      expect(audio.samples[0], closeTo(.1, .001));
      expect(fallback.calls, 0);
      expect(cached.description, contains('prepared'));
      await cached.synthesize('A different question.');
      expect(fallback.calls, 1);
    },
  );
  test(
    'a legacy or different voice pack is rejected even when its audio hash matches',
    () async {
      const text = 'Hello.';
      final key = sha256.convert(utf8.encode(text)).toString();
      final wav = encodeVoiceWav(
        SynthesizedAudio(Float32List.fromList([.5, -.5]), 24000),
      );
      final assets = VoiceAssets({
        'assets/voice_questions/index.json': Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'model': 'previous-voice',
              'prompts': {
                key: {
                  'text': text,
                  'file': '$key.wav',
                  'sha256': sha256.convert(wav).toString(),
                },
              },
            }),
          ),
        ),
        'assets/voice_questions/$key.wav': wav,
      });
      final fallback = FallbackSpeech();
      final voice = QuestionVoice(fallback, bundle: assets);
      final result = await voice.synthesize(text);
      expect(fallback.calls, 1);
      expect(result.sampleRate, 16000);
      expect(voice.description, contains(attentiveSpeechVoice));
    },
  );
  test('malformed and unsupported audio is rejected', () {
    final wave = encodeVoiceWav(SynthesizedAudio(Float32List(80), 16000));
    expect(() => decodeQuestionWav(wave.sublist(0, 30)), throwsFormatException);
    final invalid = Uint8List.fromList(wave);
    ByteData.sublistView(invalid).setUint16(22, 2, Endian.little);
    expect(() => decodeQuestionWav(invalid), throwsFormatException);
  });
}
