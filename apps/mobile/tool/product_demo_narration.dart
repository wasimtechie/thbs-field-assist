import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';

/// Product-film narration from local text-to-speech; never captures a microphone.
Future<void> main(List<String> args) async {
  final engine = FieldVoice();
  final demo = Directory(args[1]);
  final story = jsonDecode(File('${demo.path}/src/story.json').readAsStringSync()) as List;
  final output = Directory('${demo.path}/public/audio')..createSync(recursive: true);
  final timings = <String, Object>{};
  try {
    await engine.load(args[0]);
    for (final item in story) {
      final audio = await engine.synthesize(item['narration'] as String, speed: 1.04);
      final data = ByteData(44 + audio.samples.length * 2);
      void text(int at, String value) {
        for (var i = 0; i < value.length; i++) {
          data.setUint8(at + i, value.codeUnitAt(i));
        }
      }
      text(0, 'RIFF'); data.setUint32(4, data.lengthInBytes - 8, Endian.little);
      text(8, 'WAVE'); text(12, 'fmt ');
      data.setUint32(16, 16, Endian.little);
      data.setUint16(20, 1, Endian.little); data.setUint16(22, 1, Endian.little);
      data.setUint32(24, audio.sampleRate, Endian.little);
      data.setUint32(28, audio.sampleRate * 2, Endian.little);
      data.setUint16(32, 2, Endian.little); data.setUint16(34, 16, Endian.little);
      text(36, 'data'); data.setUint32(40, audio.samples.length * 2, Endian.little);
      for (var i = 0; i < audio.samples.length; i++) {
        data.setInt16(44 + i * 2, (audio.samples[i].clamp(-1, 1) * 32767).round(), Endian.little);
      }
      File('${output.path}/${item['id']}.wav').writeAsBytesSync(data.buffer.asUint8List());
      timings[item['id'] as String] = {
        'seconds': audio.samples.length / audio.sampleRate,
        'sampleRate': audio.sampleRate,
      };
      stdout.writeln('Narrated ${item['id']} (${(audio.samples.length / audio.sampleRate).toStringAsFixed(1)} s)');
    }
    File('${demo.path}/src/narration-timings.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(timings)}\n');
    await engine.unload();
    exit(0);
  } catch (error) {
    stderr.writeln('Narration failed: $error');
    exit(1);
  }
}
