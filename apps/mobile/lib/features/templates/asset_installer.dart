import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
