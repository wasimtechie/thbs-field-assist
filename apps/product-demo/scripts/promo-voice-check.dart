import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../../packages/field_voice/lib/moonshine.dart';

/// Read synthetic narration back through the existing native STT for review.
/// This checks the film's audio, not product accuracy, latency or a microphone.
Future<void> main() async {
  final root=Directory.current.path;
  final directory='$root/apps/product-demo/out/voice-promo/voice-check';
  final rows=jsonDecode(File('$directory/manifest.json').readAsStringSync()) as List;
  final engine=MoonshineRecognizer();
  await engine.load('$root/.local/model-assets/moonshine-small-streaming',
      libraryPath:'$root/.local/moonshine-runtime/mac/libmoonshine.dylib');
  final result=<Map<String,dynamic>>[];
  try {
    for(final raw in rows){
      final row=raw as Map<String,dynamic>;
      final bytes=File(row['file'] as String).readAsBytesSync();
      final samples=Float32List.view(bytes.buffer,bytes.offsetInBytes,bytes.lengthInBytes~/4);
      final turn=await engine.start();
      for(var at=0;at<samples.length;at+=5120){
        await turn.add(Float32List.sublistView(samples,at,(at+5120).clamp(0,samples.length)));
      }
      final transcript=await turn.finish();
      result.add({'scene':row['scene'],'line':row['line'],'expected':row['expected'],'heard':transcript});
      stdout.writeln('${row['scene']}: $transcript');
    }
    File('$directory/readback.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert({'scope':'Synthetic film voice readback only; not a product accuracy benchmark.','lines':result})}\n');
  } finally {await engine.unload();}
  exit(0);
}
