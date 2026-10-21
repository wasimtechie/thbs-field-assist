import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:field_voice/field_voice.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/features/voice/voice_audio.dart';

final schema = FormDefinition.fromJson(
  ((jsonDecode(File('../../fixtures/contracts.json').readAsStringSync())
              as Json)['templates']
          as Json)['fibre']['schema']
      as Json,
);

class TestEngine extends FieldVoice {
  TestEngine(this.events);
  final List<String> events;
  String answer = 'Partially completed';
  int extractionCalls = 0;
  Completer<String>? recognition;
  @override
  Future<String> transcribe(Float32List pcm) async {
    events.add('transcribe');
    return recognition == null ? answer : recognition!.future;
  }

  @override
  Future<Json> extract(
    String transcript,
    List<Json> tools,
    String context,
  ) async {
    extractionCalls++;
    return {'confidence': .9, 'function_calls': <Json>[]};
  }

  @override
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1}) async {
    events.add('speak:$text');
    return SynthesizedAudio(Float32List(100), 16000);
  }

  @override
  void cancel() {
    events.add('cancel');
  }
}

class TestAudio implements VoiceAudio {
  TestAudio(this.events);
  final List<String> events;
  bool permitted = true;
  void Function(Uint8List)? bytes;
  void Function(double)? meter;
  void Function()? interruption;
  @override
  Future<void> configure(void Function() onInterruption) async {
    events.add('configure');
    interruption = onInterruption;
  }

  @override
  Future<bool> hasPermission() async {
    events.add('permission');
    return permitted;
  }

  @override
  Future<void> capture({
    required void Function(Uint8List) onBytes,
    required void Function(double) onLevel,
    required void Function(Object) onError,
  }) async {
    events.add('capture');
    bytes = onBytes;
    meter = onLevel;
  }

  @override
  Future<void> stopCapture() async {
    events.add('stop-capture');
  }

  @override
  Future<bool> play(
    SynthesizedAudio audio,
    void Function(double) onLevel,
  ) async {
    events.add('play');
    return true;
  }

  @override
  Future<void> stopPlayback() async {
    events.add('stop-playback');
  }

  @override
  Future<void> close() async {}
  void feed() => bytes!(Uint8List(6400));
}
