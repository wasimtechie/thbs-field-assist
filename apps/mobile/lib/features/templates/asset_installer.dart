import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import '../../core/contracts.dart';
import '../../core/networking/api_client.dart';

class PackageProgress {
  const PackageProgress(this.component, this.done, this.total);
  final String component;
  final int done, total;
}

class AssetInstaller {
  AssetInstaller(this.api);
  final ApiClient api;

  /// First-launch demo setup uses exactly the same hashed model manifest as
  /// online provisioning. The APK's payload contains no online access token.
  Future<String> installBundled(
    Json snapshot,
    void Function(PackageProgress) progress, {
    AssetBundle? bundle,
    String? supportDirectory,
  }) async {
    final manifest = snapshot['manifest'] as Json;
    final directory = Directory(
      supportDirectory == null
          ? await installedDirectory(manifest)
          : packageDirectory(manifest, supportDirectory),
    );
    if (await verifyInstalled(manifest, directory.path)) return directory.path;
    final payload = _BundledVoiceReader(snapshot, bundle ?? rootBundle);
    final assets = (manifest['assets'] as List).cast<Json>();
    for (var i = 0; i < assets.length; i++) {
      final asset = assets[i], relative = asset['relativePath'] as String;
      if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
        throw const FormatException('Invalid asset path');
      }
      final range = (snapshot['files'] as Json)[relative] as Json;
      final offset = range['offset'] as int, bytes = range['bytes'] as int;
      if (offset < 0 ||
          bytes != asset['bytes'] ||
          offset + bytes > payload.length) {
        throw const FormatException('Invalid bundled asset range');
      }
      final file = File(p.join(directory.path, relative));
      if (!await _verified(file, bytes, asset['sha256'] as String)) {
        await file.parent.create(recursive: true);
        final partial = File('${file.path}.bundled-part'),
            sink = File('${file.path}.bundled-part').openWrite();
        for (var start = 0; start < bytes; start += 1048576) {
          final count = (bytes - start).clamp(0, 1048576);
          await payload.copyTo(sink, offset + start, count);
          await sink.flush();
        }
        await sink.close();
        if (!await _verified(partial, bytes, asset['sha256'] as String)) {
          throw StateError('Offline model integrity check failed.');
        }
        await partial.rename(file.path);
      }
      progress(
        PackageProgress(asset['purpose'] as String, i + 1, assets.length),
      );
    }
    return directory.path;
  }

  /// iOS can relocate the sandbox when updating an app. Persisted absolute
  /// directories cannot be used as the authority for installed package paths.
  static String packageDirectory(Json manifest, String supportDirectory) {
    final version = manifest['packageVersion'] as String;
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(version)) {
      throw const FormatException('Invalid package identity');
    }
    final contentId = sha256
        .convert(utf8.encode(jsonEncode(manifest['assets'] as List)))
        .toString()
        .substring(0, 12);
    return p.join(supportDirectory, 'voice', '$version-$contentId');
  }

  static Future<String> installedDirectory(Json manifest) async =>
      packageDirectory(manifest, (await getApplicationSupportDirectory()).path);

  Future<String> install(
    Json manifest,
    void Function(PackageProgress) progress,
  ) async {
    final assets = manifest['assets'] as List? ?? [];
    final purposes =
        (manifest['requiredPurposes'] as List? ??
                [
                  'whistle',
                  'needle3',
                  'kokoro',
                  'voices',
                  'phonemizer',
                  'tokenizer',
                ])
            .cast<String>();
    if (assets.isEmpty ||
        !purposes.every(
          (p) => assets.any((a) => (a as Json)['purpose'] == p),
        )) {
      throw StateError(
        'The server has no complete voice package. Ask the setup operator to provision the model assets. You can continue with manual forms.',
      );
    }
    final directory = Directory(await installedDirectory(manifest));
    await directory.create(recursive: true);
    var done = 0;
    for (final raw in assets) {
      final asset = raw as Json;
      final relative = asset['relativePath'] as String;
      if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
        throw const FormatException('Invalid asset path');
      }
      final file = File(p.join(directory.path, relative));
      await file.parent.create(recursive: true);
      final bytes = asset['bytes'] as int, expected = asset['sha256'] as String;
      if (!await _verified(file, bytes, expected)) {
        final partial = File('${file.path}.part');
        var offset = await partial.exists() ? await partial.length() : 0;
        if (offset > bytes) {
          await partial.delete();
          offset = 0;
        }
        final source = Uri.parse(asset['source'] as String);
        final base = Uri.parse(api.dio.options.baseUrl);
        final uri = source.hasScheme ? source : base.resolve(source.toString());
        if (uri.origin != base.origin) {
          throw const FormatException(
            'Model downloads must use the configured authorized API origin',
          );
        }
        final response = await api.dio.get<ResponseBody>(
          uri.toString(),
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'Authorization': 'Bearer ${api.token}',
              if (offset > 0) 'Range': 'bytes=$offset-',
            },
          ),
        );
        final append = response.statusCode == 206 && offset > 0;
        final sink = partial.openWrite(
          mode: append ? FileMode.append : FileMode.write,
        );
        await sink.addStream(response.data!.stream);
        await sink.close();
        if (!await _verified(partial, bytes, expected)) {
          throw StateError(
            'A voice asset failed its integrity check. Partial data is retained for online repair.',
          );
        }
        await partial.rename(file.path);
      }
      done++;
      progress(
        PackageProgress(asset['purpose'] as String, done, assets.length),
      );
    }
    return directory.path;
  }

  Future<bool> _verified(File file, int bytes, String expected) async {
    if (!await file.exists() || await file.length() != bytes) return false;
    return (await sha256.bind(file.openRead()).first).toString() == expected;
  }

  Future<bool> verifyInstalled(Json manifest, String directory) async {
    for (final raw in manifest['assets'] as List? ?? []) {
      final a = raw as Json;
      final relative = a['relativePath'] as String;
      if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
        return false;
      }
      if (!await _verified(
        File(p.join(directory, relative)),
        a['bytes'] as int,
        a['sha256'] as String,
      )) {
        return false;
      }
    }
    return (manifest['assets'] as List? ?? []).isNotEmpty;
  }
}

/// APK model chunks keep first-launch memory bounded. Legacy demo packages can
/// still be restored; new packages never allocate the complete model payload.
class _BundledVoiceReader {
  _BundledVoiceReader(this.snapshot, this.bundle);
  final Json snapshot;
  final AssetBundle bundle;
  ByteData? _data;
  int _chunkIndex = -1;
  int get length => snapshot['voiceBytes'] as int;

  Future<void> copyTo(IOSink sink, int offset, int count) async {
    final chunks = snapshot['voiceChunks'] as List?;
    if (chunks == null) {
      _data ??= await bundle.load('assets/offline_demo/voice.bin');
      if (_data!.lengthInBytes != length) {
        throw StateError('Incomplete offline voice package.');
      }
      sink.add(_data!.buffer.asUint8List(_data!.offsetInBytes + offset, count));
      return;
    }
    while (count > 0) {
      final index = chunks.indexWhere((raw) {
        final chunk = raw as Json;
        return offset >= chunk['offset'] &&
            offset < (chunk['offset'] as int) + (chunk['bytes'] as int);
      });
      if (index < 0) {
        throw const FormatException('Incomplete offline chunk range.');
      }
      final chunk = chunks[index] as Json;
      final file = chunk['file'] as String;
      if (!RegExp(r'^voice-\d{3}\.bin$').hasMatch(file) ||
          (chunk['bytes'] as int) > 16 * 1024 * 1024) {
        throw const FormatException('Invalid offline model chunk.');
      }
      if (_chunkIndex != index) {
        _data = null;
        final data = await bundle.load('assets/offline_demo/$file');
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        if (data.lengthInBytes != chunk['bytes'] ||
            sha256.convert(bytes).toString() != chunk['sha256']) {
          throw StateError('Offline model chunk integrity failure.');
        }
        _data = data;
        _chunkIndex = index;
      }
      final within = offset - (chunk['offset'] as int);
      final take = count.clamp(0, _data!.lengthInBytes - within);
      sink.add(_data!.buffer.asUint8List(_data!.offsetInBytes + within, take));
      await sink.flush();
      offset += take;
      count -= take;
    }
  }
}
