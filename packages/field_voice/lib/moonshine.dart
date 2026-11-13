import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'streaming_speech.dart';

// ABI pinned to Moonshine SDK 0.1.5, header version 30000. Models and native
// binaries are staged by scripts/provision-moonshine.py, never downloaded here.
final class _Option extends Struct {
  external Pointer<Utf8> name;
  external Pointer<Utf8> value;
}

final class _Line extends Struct {
  external Pointer<Utf8> text;
  external Pointer<Float> audio;
  @Uint64()
  external int audioCount;
  @Float()
  external double start;
  @Float()
  external double duration;
  @Uint64()
  external int id;
  @Int8()
  external int complete;
  @Int8()
  external int updated;
  @Int8()
  external int isNew;
  @Int8()
  external int textChanged;
  @Int8()
  external int speakersChanged;
  external Pointer<Void> speakers;
  @Uint64()
  external int speakerCount;
  @Uint32()
  external int latency;
  external Pointer<Void> words;
  @Uint64()
  external int wordCount;
}

final class _Transcript extends Struct {
  external Pointer<_Line> lines;
  @Uint64()
  external int count;
}

class _Native {
  _Native(DynamicLibrary library)
    : version = library.lookupFunction<Int32 Function(), int Function()>(
        'moonshine_get_version',
      ),
      load = library
          .lookupFunction<
            Int32 Function(
              Pointer<Utf8>,
              Uint32,
              Pointer<_Option>,
              Uint64,
              Int32,
            ),
            int Function(Pointer<Utf8>, int, Pointer<_Option>, int, int)
          >('moonshine_load_transcriber_from_files'),
      create = library
          .lookupFunction<
            Int32 Function(Int32, Uint32),
            int Function(int, int)
          >('moonshine_create_stream'),
      start = library
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'moonshine_start_stream',
          ),
      stop = library
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'moonshine_stop_stream',
          ),
      freeStream = library
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'moonshine_free_stream',
          ),
      free = library.lookupFunction<Void Function(Int32), void Function(int)>(
        'moonshine_free_transcriber',
      ),
      add = library
          .lookupFunction<
            Int32 Function(Int32, Int32, Pointer<Float>, Uint64, Int32, Uint32),
            int Function(int, int, Pointer<Float>, int, int, int)
          >('moonshine_transcribe_add_audio_to_stream'),
      transcribe = library
          .lookupFunction<
            Int32 Function(Int32, Int32, Uint32, Pointer<Pointer<_Transcript>>),
            int Function(int, int, int, Pointer<Pointer<_Transcript>>)
          >('moonshine_transcribe_stream');
  final int Function() version;
  final int Function(Pointer<Utf8>, int, Pointer<_Option>, int, int) load;
  final int Function(int, int) create, start, stop, freeStream;
  final void Function(int) free;
  final int Function(int, int, Pointer<Float>, int, int, int) add;
  final int Function(int, int, int, Pointer<Pointer<_Transcript>>) transcribe;
}

class MoonshineRecognizer {
  SendPort? _port;
  ReceivePort? _responses;
  Future<void>? _starting;
  final _pending = <int, Completer<Object?>>{};
  int _request = 0, _turn = 0;
  _Turn? _active;

  Future<Object?> _call(String operation, Map<String, Object?> args) async {
    if (_port == null) {
      _starting ??= () async {
        final ready = ReceivePort();
        await Isolate.spawn(_worker, ready.sendPort);
        _port = await ready.first as SendPort;
        ready.close();
        _responses = ReceivePort()
          ..listen((dynamic message) {
            final data = message as List;
            final completion = _pending.remove(data[0] as int);
            if (data[1] == true) {
              completion?.complete(data[2]);
            } else {
              completion?.completeError(StateError(data[2] as String));
            }
          });
      }();
      await _starting;
    }
    final id = ++_request;
    final completion = Completer<Object?>();
    _pending[id] = completion;
    _port!.send([id, operation, args, _responses!.sendPort]);
    return completion.future;
  }

  Future<void> load(String directory, {String? libraryPath}) async {
    await _call('load', {'directory': directory, 'library': libraryPath});
  }

  Future<StreamingSpeechTurn> start() async {
    await _active?.cancel();
    final token = ++_turn;
    await _call('start', {'turn': token});
    return _active = _Turn(this, token);
  }

  Future<String> transcribe(Float32List samples) async {
    final turn = await start();
    try {
      await turn.add(samples);
      return await turn.finish();
    } catch (_) {
      await turn.cancel();
      rethrow;
    }
  }

  void cancel() {
    final active = _active;
    if (active != null) unawaited(active.cancel().catchError((_) {}));
  }

  Future<void> unload() async {
    await _active?.cancel();
    if (_port != null) await _call('unload', {});
  }
}

class _Turn implements StreamingSpeechTurn {
  _Turn(this.owner, this.token);
  final MoonshineRecognizer owner;
  final int token;
  bool ended = false;
  @override
  Future<SpeechProgress> add(Float32List samples) async {
    if (ended) throw StateError('Speech turn ended.');
    final data = await owner._call('audio', {'turn': token, 'pcm': samples});
    if (ended) throw StateError('Speech turn cancelled.');
    return SpeechProgress.fromMap(data as Map);
  }

  @override
  Future<String> finish() async {
    if (ended) throw StateError('Speech turn ended.');
    ended = true;
    return await owner._call('finish', {'turn': token}) as String;
  }

  @override
  Future<void> cancel() async {
    if (ended) return;
    ended = true;
    await owner._call('cancel', {'turn': token});
  }
}

void _worker(SendPort ready) async {
  final inbox = ReceivePort();
  ready.send(inbox.sendPort);
  _Native? api;
  int model = -1, stream = -1, token = -1, samples = 0, analyzedSamples = 0;
  String? directory;
  void check(int status) {
    if (status < 0) {
      throw StateError('Offline Moonshine operation failed ($status).');
    }
  }

  void closeStream() {
    if (stream >= 0) {
      api!.freeStream(model, stream);
      stream = -1;
    }
  }

  Map<String, Object> result({bool finalizing = false}) {
    final output = calloc<Pointer<_Transcript>>();
    try {
      check(api!.transcribe(model, stream, finalizing ? 1 : 0, output));
      // Below the configured 320 ms interval Moonshine returns a cached VAD
      // snapshot. Do not count not-yet-analyzed audio as trailing silence: the
      // engineer may already have started the next word in that buffer.
      if (finalizing || samples - analyzedSamples >= 5120) {
        analyzedSamples = samples;
      }
      final transcript = output.value;
      final texts = <String>[];
      var speaking = false, lastEnd = 0.0, latency = 0;
      if (transcript != nullptr) {
        final count = transcript.ref.count;
        if (count > 1000) throw StateError('Unexpected speech segment count.');
        for (var i = 0; i < count; i++) {
          final line = (transcript.ref.lines + i).ref;
          if (line.text != nullptr) {
            final text = line.text.toDartString().trim();
            if (text.isNotEmpty) texts.add(text);
          }
          speaking = speaking || line.complete == 0;
          if (line.start + line.duration > lastEnd) {
            lastEnd = line.start + line.duration;
          }
          if (line.latency > latency) latency = line.latency;
        }
      }
      return {
        'text': texts.join(' '),
        'heardSpeech': transcript != nullptr && transcript.ref.count > 0,
        'speaking': speaking,
        'audioSeconds': analyzedSamples / 16000,
        'lastSpeechSeconds': lastEnd,
        'inferenceMilliseconds': latency,
      };
    } finally {
      // The transcript belongs to the transcriber, valid until its next call.
      calloc.free(output);
    }
  }

  await for (final dynamic message in inbox) {
    final request = message as List;
    final args = request[2] as Map;
    final reply = request[3] as SendPort;
    try {
      Object? value;
      switch (request[1]) {
        case 'load':
          if (api == null) {
            final explicit = args['library'] as String?;
            final library = explicit != null
                ? DynamicLibrary.open(explicit)
                : Platform.isIOS
                ? DynamicLibrary.process()
                : DynamicLibrary.open('libmoonshine.so');
            api = _Native(library);
            if (api.version() < 30000 || api.version() >= 40000) {
              throw StateError('Unexpected Moonshine native ABI.');
            }
          }
          if (directory == args['directory'] && model >= 0) {
            value = true;
            break;
          }
          closeStream();
          if (model >= 0) api.free(model);
          model = -1;
          final options = {
            'keyterms':
                'ONT,CBT,CSP,FTTP,fibre,fibre route,dBm,decibels,optical receive,optical receive reading,service test',
            'keyterm_boost': '2.0',
            'vad_threshold': '0.5',
            // Smooth intraword dips so brief pauses do not split/duplicate
            // words. This still admits short yes/no and control responses.
            'vad_window_duration': '0.256',
            'transcription_interval': '0.32',
            'max_tokens_per_second': '12',
            'log_output_text': 'false',
          };
          final list = calloc<_Option>(options.length);
          final path = (args['directory'] as String).toNativeUtf8();
          var at = 0;
          try {
            for (final entry in options.entries) {
              (list + at).ref
                ..name = entry.key.toNativeUtf8()
                ..value = entry.value.toNativeUtf8();
              at++;
            }
            model = api.load(path, 4, list, options.length, 30000);
            check(model);
            directory = args['directory'] as String;
            value = true;
          } finally {
            for (var i = 0; i < at; i++) {
              calloc.free((list + i).ref.name);
              calloc.free((list + i).ref.value);
            }
            calloc.free(list);
            calloc.free(path);
          }
        case 'start':
          if (model < 0) throw StateError('Moonshine models are not loaded.');
          closeStream();
          stream = api!.create(model, 0);
          check(stream);
          check(api.start(model, stream));
          token = args['turn'] as int;
          samples = 0;
          analyzedSamples = 0;
          value = true;
        case 'audio':
          if (args['turn'] != token || stream < 0) {
            throw StateError('Stale speech turn.');
          }
          final pcm = args['pcm'] as Float32List;
          if (samples + pcm.length > 16000 * 65) {
            throw StateError('Speech turn too long.');
          }
          final data = calloc<Float>(pcm.length);
          try {
            data.asTypedList(pcm.length).setAll(0, pcm);
            check(api!.add(model, stream, data, pcm.length, 16000, 0));
            samples += pcm.length;
          } finally {
            calloc.free(data);
          }
          value = result();
        case 'finish':
          if (args['turn'] != token || stream < 0) {
            throw StateError('Stale speech turn.');
          }
          try {
            check(api!.stop(model, stream));
            value = result(finalizing: true)['text'];
          } finally {
            closeStream();
          }
        case 'cancel':
          if (args['turn'] == token) closeStream();
          value = true;
        case 'unload':
          closeStream();
          if (model >= 0) api!.free(model);
          model = -1;
          directory = null;
          value = true;
        default:
          throw StateError('Unknown Moonshine operation.');
      }
      reply.send([request[0], true, value]);
    } catch (error) {
      reply.send([request[0], false, error.toString()]);
    }
  }
}
