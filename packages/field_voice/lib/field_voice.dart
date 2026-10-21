library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'field_voice_bindings_generated.dart' as native;

class VoiceFailure implements Exception {
  const VoiceFailure(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

class SynthesizedAudio {
  const SynthesizedAudio(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}

abstract interface class SpeechRecognizer {
  Future<String> transcribe(Float32List pcm16k);
}

abstract interface class FieldExtractor {
  Future<Map<String, dynamic>> extract(
    String transcript,
    List<Map<String, dynamic>> tools,
    String context,
  );
}

abstract interface class SpeechSynthesizer {
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1});
}

/// All process-global, non-thread-safe Cactus calls belong to one worker.
/// The pinned API cannot unload weights. Retain buffers until process exit;
/// unload resets conversation/TTS; activating new weights requires a restart.
class FieldVoice
    implements SpeechRecognizer, FieldExtractor, SpeechSynthesizer {
  SendPort? _port;
  ReceivePort? _responses;
  final _pending = <int, Completer<Object?>>{};
  int _sequence = 0, _generation = 0;
  Future<void>? _starting;
  Future<void> _start() async {
    if (_port != null) return;
    if (_starting != null) return _starting;
    _starting = () async {
      final ready = ReceivePort();
      await Isolate.spawn(_worker, ready.sendPort);
      _port = await ready.first as SendPort;
      ready.close();
      _responses = ReceivePort();
      _responses!.listen((dynamic message) {
        final m = message as List;
        final c = _pending.remove(m[0] as int);
        if (c == null) return;
        if (m[1] == true) {
          c.complete(m[2]);
        } else {
          final error = m[2] as Map;
          c.completeError(
            VoiceFailure(error['code'] as String, error['message'] as String),
          );
        }
      });
    }();
    await _starting;
  }

  Future<Object?> _call(String operation, Map<String, dynamic> args) async {
    await _start();
    final id = ++_sequence, gen = _generation;
    final c = Completer<Object?>();
    _pending[id] = c;
    _port!.send([id, operation, args, _responses!.sendPort]);
    final result = await c.future;
    if (gen != _generation) {
      throw const VoiceFailure(
        'CANCELLED',
        'Voice turn paused. Late results were discarded.',
      );
    }
    return result;
  }

  Future<void> load(String directory) async {
    await _call('load', {'directory': directory});
  }

  Future<void> unload() async {
    cancel();
    await _call('reset', {});
  }

  void cancel() {
    _generation++;
  }

  @override
  Future<String> transcribe(Float32List pcm16k) async =>
      await _call('transcribe', {'pcm': pcm16k}) as String;
  @override
  Future<Map<String, dynamic>> extract(
    String transcript,
    List<Map<String, dynamic>> tools,
    String context,
  ) async =>
      await _call('extract', {
            'text': transcript,
            'tools': tools,
            'context': context,
          })
          as Map<String, dynamic>;
  @override
  Future<SynthesizedAudio> synthesize(String text, {double speed = 1}) async {
    final audio =
        await _call('synthesize', {'text': text, 'speed': speed}) as Map;
    return SynthesizedAudio(
      audio['samples'] as Float32List,
      audio['sampleRate'] as int,
    );
  }

  Future<void> smokeTest() async {
    await transcribe(Float32List(16000));
    final r = await extract('Site access is available.', [
      {
        'name': 'record_access',
        'description': 'Record an explicit site access status.',
        'parameters': {
          'type': 'object',
          'properties': {
            'status': {
              'type': 'string',
              'enum': ['available', 'restricted', 'unavailable'],
            },
          },
          'required': ['status'],
        },
      },
    ], 'Extract only explicitly stated facts.');
    final calls = r['function_calls'] as List? ?? [];
    if (calls.isEmpty) {
      throw const VoiceFailure(
        'SMOKE_FAILED',
        'Offline answer understanding did not pass its readiness check.',
      );
    }
    final audio = await synthesize('Ready for offline reporting.');
    if (audio.samples.isEmpty) {
      throw const VoiceFailure(
        'SMOKE_FAILED',
        'Offline spoken questions did not pass their readiness check.',
      );
    }
  }
}

void _worker(SendPort ready) async {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  final retained = <Pointer<Uint8>>[];
  String? loadedDirectory;
  sherpa.OfflineTts? tts;
  String lastError() => native.faLastError().cast<Utf8>().toDartString();
  await for (final dynamic message in inbox) {
    final m = message as List;
    final id = m[0] as int, operation = m[1] as String;
    final args = m[2] as Map<String, dynamic>;
    final reply = m[3] as SendPort;
    try {
      Object? result;
      switch (operation) {
        case 'load':
          if (native.faAvailable() != 1) {
            throw const VoiceFailure(
              'NATIVE_LIBRARY_MISSING',
              'Offline speech is not included for this platform. Manual entry is available.',
            );
          }
          final directory = args['directory'] as String;
          if (loadedDirectory != null && directory != loadedDirectory) {
            throw const VoiceFailure(
              'RESTART_REQUIRED',
              'Restart the app to activate the new model package.',
            );
          }
          if (loadedDirectory == null) {
            for (final name in ['needle3.cact', 'whistle.cact']) {
              final bytes = await File('$directory/$name').readAsBytes();
              final pointer = calloc<Uint8>(bytes.length);
              pointer.asTypedList(bytes.length).setAll(0, bytes);
              final status = native.faLoad(pointer, bytes.length);
              if (status < 0) {
                calloc.free(pointer);
                throw VoiceFailure('MODEL_LOAD_FAILED', lastError());
              }
              retained.add(pointer);
            }
            loadedDirectory = directory;
          }
          sherpa.initBindings();
          tts ??= sherpa.OfflineTts(
            sherpa.OfflineTtsConfig(
              model: sherpa.OfflineTtsModelConfig(
                kokoro: sherpa.OfflineTtsKokoroModelConfig(
                  model: '$directory/kokoro/model.onnx',
                  voices: '$directory/kokoro/voices.bin',
                  tokens: '$directory/kokoro/tokens.txt',
                  dataDir: '$directory/kokoro/espeak-ng-data',
                ),
                numThreads: 2,
                debug: false,
                provider: 'cpu',
              ),
            ),
          );
          result = true;
        case 'transcribe':
          if (loadedDirectory == null) {
            throw const VoiceFailure(
              'NOT_LOADED',
              'Install and verify the local voice package first.',
            );
          }
          final pcm = args['pcm'] as Float32List;
          final input = calloc<Float>(pcm.length),
              out = calloc<Char>(262144),
              language = 'en'.toNativeUtf8();
          try {
            input.asTypedList(pcm.length).setAll(0, pcm);
            if (native.faTranscribe(
                  input,
                  pcm.length,
                  language.cast(),
                  out,
                  262144,
                ) <
                0) {
              throw VoiceFailure('TRANSCRIPTION_FAILED', lastError());
            }
            result =
                (jsonDecode(out.cast<Utf8>().toDartString()) as Map)['text']
                    as String;
          } finally {
            calloc.free(input);
            calloc.free(out);
            calloc.free(language);
          }
        case 'extract':
          if (loadedDirectory == null) {
            throw const VoiceFailure(
              'NOT_LOADED',
              'Install and verify the local voice package first.',
            );
          }
          final system = (args['context'] as String).toNativeUtf8(),
              tools = jsonEncode(args['tools']).toNativeUtf8(),
              text = (args['text'] as String).toNativeUtf8(),
              out = calloc<Char>(262144);
          try {
            native.faReset();
            if (native.faInit(system.cast(), tools.cast()) < 0) {
              throw VoiceFailure('SCHEMA_TOO_LARGE', lastError());
            }
            if (native.faComplete(text.cast(), out, 262144) < 0) {
              throw VoiceFailure('EXTRACTION_FAILED', lastError());
            }
            result =
                jsonDecode(out.cast<Utf8>().toDartString())
                    as Map<String, dynamic>;
          } finally {
            calloc.free(system);
            calloc.free(tools);
            calloc.free(text);
            calloc.free(out);
          }
        case 'synthesize':
          if (tts == null) {
            throw const VoiceFailure(
              'NOT_LOADED',
              'Install and verify the offline spoken-question package first.',
            );
          }
          final audio = tts.generate(
            text: args['text'] as String,
            sid: 0,
            speed: (args['speed'] as num).toDouble(),
          );
          result = {
            'samples': Float32List.fromList(audio.samples),
            'sampleRate': audio.sampleRate,
          };
        case 'reset':
          native.faReset();
          tts?.free();
          tts = null;
          result = true;
        default:
          throw const VoiceFailure(
            'UNSUPPORTED_OPERATION',
            'Unsupported voice operation.',
          );
      }
      reply.send([id, true, result]);
    } catch (e, stack) {
      // Only model initialization errors are logged in development builds.
      // Actual dictated answers and report contents must never enter diagnostics.
      if (!const bool.fromEnvironment('dart.vm.product') &&
          operation == 'load') {
        stderr.writeln(
          'Field Assist voice $operation failed (${e.runtimeType}): $e\n$stack',
        );
      }
      reply.send([
        id,
        false,
        {
          'code': e is VoiceFailure
              ? e.code
              : 'RUNTIME_${operation.toUpperCase()}',
          'message': e is VoiceFailure
              ? e.message
              : 'Local voice processing failed. Repair the voice package online or continue by touch.',
        },
      ]);
    }
  }
}
