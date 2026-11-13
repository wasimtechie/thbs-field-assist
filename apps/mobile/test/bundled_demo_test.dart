import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/contracts.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/authentication/demo_access.dart';
import 'package:field_assist/features/offline_access/entitlement.dart';
import 'package:field_assist/features/templates/asset_installer.dart';

class BytesBundle extends CachingAssetBundle {
  BytesBundle(this.bytes);
  final Uint8List bytes;
  int loads = 0;
  @override
  Future<ByteData> load(String key) async {
    expect(key, 'assets/offline_demo/voice.bin');
    loads++;
    return ByteData.sublistView(bytes);
  }
}

class ChunkBundle extends CachingAssetBundle {
  ChunkBundle(this.chunks);
  final Map<String, Uint8List> chunks;
  final loads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    expect(key, isNot(endsWith('voice.bin')));
    return ByteData.sublistView(chunks[key]!);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'chunked offline models cross chunk boundaries and reject corruption without HTTP',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'chunked-voice-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final a = Uint8List.fromList([1, 2, 3, 4]),
          b = Uint8List.fromList([5, 6, 7, 8]);
      final first = Uint8List.fromList([1, 2, 3]),
          second = Uint8List.fromList([4, 5, 6, 7, 8]);
      final manifest = <String, dynamic>{
        'packageVersion': 'chunk-test',
        'assets': [
          {
            'relativePath': 'a.bin',
            'bytes': 3,
            'sha256': sha256.convert(first).toString(),
            'purpose': 'moonshine',
          },
          {
            'relativePath': 'b.bin',
            'bytes': 5,
            'sha256': sha256.convert(second).toString(),
            'purpose': 'visit-extractor',
          },
        ],
      };
      final snapshot = <String, dynamic>{
        'formatVersion': 2,
        'manifest': manifest,
        'voiceBytes': 8,
        'files': {
          'a.bin': {'offset': 0, 'bytes': 3},
          'b.bin': {'offset': 3, 'bytes': 5},
        },
        'voiceChunks': [
          {
            'file': 'voice-000.bin',
            'offset': 0,
            'bytes': 4,
            'sha256': sha256.convert(a).toString(),
          },
          {
            'file': 'voice-001.bin',
            'offset': 4,
            'bytes': 4,
            'sha256': sha256.convert(b).toString(),
          },
        ],
      };
      final bundle = ChunkBundle({
        'assets/offline_demo/voice-000.bin': a,
        'assets/offline_demo/voice-001.bin': b,
      });
      final installer = AssetInstaller(
        ApiClient(baseUrl: 'https://unreachable.invalid/api/v1/'),
      );
      final installed = await installer.installBundled(
        snapshot,
        (_) {},
        bundle: bundle,
        supportDirectory: directory.path,
      );
      expect(await File('$installed/a.bin').readAsBytes(), first);
      expect(await File('$installed/b.bin').readAsBytes(), second);
      expect(
        bundle.loads,
        hasLength(2),
        reason: 'Small files share one bounded cached chunk.',
      );
      await File('$installed/b.bin').delete();
      bundle.chunks['assets/offline_demo/voice-001.bin'] = Uint8List.fromList([
        9,
        6,
        7,
        8,
      ]);
      await expectLater(
        installer.installBundled(
          snapshot,
          (_) {},
          bundle: bundle,
          supportDirectory: directory.path,
        ),
        throwsStateError,
      );
      expect(
        await File('$installed/b.bin').exists(),
        false,
        reason: 'Unverified bytes must never activate as a model.',
      );
    },
  );
  test('bundled startup stays gated to explicit debug synthetic demos', () {
    expect(const DemoAccess(bundled: true).offlinePackage, false);
    expect(
      const DemoAccess(
        requested: true,
        bundled: true,
        email: 'private@example.com',
        password: 'x',
      ).offlinePackage,
      false,
    );
    expect(
      const DemoAccess(
        requested: true,
        bundled: true,
        email: 'closure@fieldassist.demo',
        password: 'x',
      ).offlinePackage,
      true,
    );
    expect(DemoAccess.allowed(requested: true, debugBuild: false), false);
  });
  test(
    'the bundled form and device access verify with the existing public key; no online credential is packaged',
    () async {
      final snapshot =
          jsonDecode(
                File('assets/offline_demo/bootstrap.json').readAsStringSync(),
              )
              as Json;
      final config =
          jsonDecode(
                File('../../.local/mobile-demo-config.json').readAsStringSync(),
              )
              as Json;
      final form = FormDefinition.fromJson(snapshot['template'] as Json);
      form.verifyHash();
      final user = snapshot['user'] as Json;
      final lease = await OfflineLease.verify(
        snapshot['entitlement'] as String,
        jsonDecode(config['ENTITLEMENT_PUBLIC_JWK'] as String) as Json,
        keyId:
            config['ENTITLEMENT_KEY_ID'] as String? ?? 'field-assist-local-1',
        now: DateTime.parse(
          snapshot['serverTime'] as String,
        ).add(const Duration(minutes: 1)),
        userId: user['id'] as String,
        deviceId: snapshot['deviceId'] as String,
        nonExpiringDemoEmail: user['email'] as String,
      );
      expect(lease.allowedTemplates, contains(form.templateId));
      expect(lease.nonExpiringDemo, true);
      expect(lease.expiresAt, isNull);
      expect(user['email'], endsWith('@fieldassist.demo'));
      expect(snapshot.containsKey('token'), false);
      expect(snapshot.containsKey('password'), false);
      final jobs = (snapshot['operations'] as Json)['workOrders'] as List;
      expect(jobs, hasLength(8));
      expect(
        jobs.where((job) => job['title'] == 'S1 · 15-field voice test'),
        hasLength(1),
        reason: 'A fresh offline install must include the open S1 test visit.',
      );
    },
  );
  test(
    'bundled models install on a fresh directory without HTTP, verify hashes and repair corruption locally',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'offline-bundle-unit-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
          bundle = BytesBundle(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
      final manifest = <String, dynamic>{
        'packageVersion': 'unit',
        'assets': [
          {
            'relativePath': 'voice/model.bin',
            'bytes': 8,
            'sha256': sha256.convert(bytes).toString(),
            'purpose': 'whistle',
          },
        ],
      };
      final snapshot = <String, dynamic>{
        'manifest': manifest,
        'voiceBytes': 8,
        'files': {
          'voice/model.bin': {'offset': 0, 'bytes': 8},
        },
      };
      final installer = AssetInstaller(
        ApiClient(baseUrl: 'https://unreachable.invalid/api/v1/'),
      );
      final path = await installer.installBundled(
        snapshot,
        (_) {},
        bundle: bundle,
        supportDirectory: directory.path,
      );
      expect(await installer.verifyInstalled(manifest, path), true);
      expect(bundle.loads, 1);
      await installer.installBundled(
        snapshot,
        (_) {},
        bundle: bundle,
        supportDirectory: directory.path,
      );
      expect(bundle.loads, 1);
      await File('$path/voice/model.bin').writeAsBytes([0]);
      await installer.installBundled(
        snapshot,
        (_) {},
        bundle: bundle,
        supportDirectory: directory.path,
      );
      expect(bundle.loads, 2);
      expect(await installer.verifyInstalled(manifest, path), true);
    },
  );
  test('bundle path traversal and corrupted contents are rejected', () async {
    final directory = await Directory.systemTemp.createTemp(
      'offline-bundle-invalid-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final snapshot = <String, dynamic>{
      'manifest': {
        'packageVersion': 'unit',
        'assets': [
          {
            'relativePath': '../escape',
            'bytes': 1,
            'sha256': '0' * 64,
            'purpose': 'whistle',
          },
        ],
      },
      'voiceBytes': 1,
      'files': {
        '../escape': {'offset': 0, 'bytes': 1},
      },
    };
    final installer = AssetInstaller(
      ApiClient(baseUrl: 'https://unreachable.invalid/api/v1/'),
    );
    await expectLater(
      installer.installBundled(
        snapshot,
        (_) {},
        bundle: BytesBundle(Uint8List.fromList([1])),
        supportDirectory: directory.path,
      ),
      throwsFormatException,
    );
    snapshot['manifest']['assets'][0]['relativePath'] = 'model.bin';
    snapshot['files'] = {
      'model.bin': {'offset': 0, 'bytes': 1},
    };
    await expectLater(
      installer.installBundled(
        snapshot,
        (_) {},
        bundle: BytesBundle(Uint8List.fromList([1])),
        supportDirectory: directory.path,
      ),
      throwsStateError,
    );
  });
}
