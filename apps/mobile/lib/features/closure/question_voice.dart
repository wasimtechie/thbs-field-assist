import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:field_voice/field_voice.dart';
import '../voice/speech_output_level.dart';

/// Prepared questions and fallback synthesis stay entirely on the phone.
class QuestionVoice implements SpeechSynthesizer {
  QuestionVoice(
    this.fallback, {
    AssetBundle? bundle,
    this.voiceId = attentiveSpeechVoice,
    this.rate = 1,
  }) : bundle = bundle ?? rootBundle;
  final SpeechSynthesizer fallback;
  final AssetBundle bundle;
  final String voiceId;
  final double rate;
  Future<Map<String, dynamic>>? _index;
  String description = 'Prepared model questions · on-device listening';

  @override
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1}) async {
    final promptHash = sha256.convert(utf8.encode(text)).toString();
    try {
      if (speed * rate != 1) {
        throw StateError('Use local synthesis for the selected speech rate.');
      }
      final catalog = await (_index ??= bundle
          .loadString('assets/voice_questions/index.json')
          .then((text) => jsonDecode(text) as Map<String, dynamic>));
      final index =
          (catalog['voices'] as Map<String, dynamic>?)?[voiceId]
              as Map<String, dynamic>? ??
          catalog;
      final profile = offlineSpeechVoice(voiceId);
      final settings = index['settings'] as Map<String, dynamic>?;
      if (index['model'] != attentiveSpeechModel ||
          profile == null ||
          index['voice'] != voiceId ||
          settings?['speakerId'] != profile.speakerId ||
          settings?['speed'] != attentiveSpeechSpeed ||
          settings?['backgroundAudio'] != false) {
        throw StateError('Prepared speech does not match the fixed voice.');
      }
      final entry =
          (index['prompts'] as Map<String, dynamic>)[promptHash]
              as Map<String, dynamic>?;
      if (entry != null && entry['text'] == text) {
        final path = entry['file'] as String;
        if (!(RegExp(r'^[a-f0-9]{64}\.wav$').hasMatch(path) ||
            path == '$voiceId-$promptHash.wav')) {
          throw StateError('Invalid voice asset.');
        }
        final data = await bundle.load('assets/voice_questions/$path');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (sha256.convert(bytes).toString() != entry['sha256']) {
          throw StateError('Voice asset integrity failure.');
        }
        description =
            'Offline · prepared ${index['model']} voice · on-device listening';
        return levelSpeechOutput(decodeQuestionWav(bytes));
      }
    } catch (_) {
      /* An absent/stale pack uses the verified local synthesis engine. */
    }
    description = 'Offline · on-device $voiceId voice';
    return levelSpeechOutput(
      await fallback.synthesize(text, speed: speed * rate),
    );
  }
}

/// Used for an audition without changing the engineer's saved voice selection.
class VoiceAudition implements SpeechSynthesizer {
  VoiceAudition(this.engine, this.voiceId);
  final FieldVoice engine;
  final String voiceId;
  @override
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1}) =>
      engine.synthesizeVoice(text, voiceId: voiceId, speed: speed);
}

SynthesizedAudio decodeQuestionWav(Uint8List bytes) {
  if (bytes.length < 44 || bytes.length > 4600000) {
    throw const FormatException('Invalid question audio size.');
  }
  final view = ByteData.sublistView(bytes);
  String tag(int at) => String.fromCharCodes(bytes.sublist(at, at + 4));
  if (tag(0) != 'RIFF' || tag(8) != 'WAVE') {
    throw const FormatException('Question is not WAV audio.');
  }
  int? rate, start, length;
  for (var at = 12; at + 8 <= bytes.length;) {
    final size = view.getUint32(at + 4, Endian.little), next = at + 8 + size;
    if (next > bytes.length) {
      throw const FormatException('Truncated question audio.');
    }
    if (tag(at) == 'fmt ') {
      if (size < 16 ||
          view.getUint16(at + 8, Endian.little) != 1 ||
          view.getUint16(at + 10, Endian.little) != 1 ||
          view.getUint16(at + 22, Endian.little) != 16) {
        throw const FormatException('Expected mono PCM16 question audio.');
      }
      rate = view.getUint32(at + 12, Endian.little);
    }
    if (tag(at) == 'data') {
      start = at + 8;
      length = size;
    }
    at = next + (size % 2);
  }
  if (rate == null ||
      ![16000, 22050, 24000, 44100, 48000].contains(rate) ||
      start == null ||
      length == null ||
      length == 0 ||
      length.isOdd ||
      length / 2 / rate > 46) {
    throw const FormatException('Invalid question audio format.');
  }
  final samples = Float32List(length ~/ 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = view.getInt16(start + i * 2, Endian.little) / 32768;
  }
  return SynthesizedAudio(samples, rate);
}
