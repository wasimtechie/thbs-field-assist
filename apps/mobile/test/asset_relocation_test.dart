import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:field_assist/core/networking/api_client.dart';
import 'package:field_assist/features/templates/asset_installer.dart';

void main() {
  test(
    'sandbox relocation preserves verified assets; corrupt bytes stay rejected',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'field-assets-relocation-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final original = Directory('${temp.path}/old-container');
      final moved = Directory('${temp.path}/new-container');
      final bytes = [1, 2, 3, 4];
      final manifest = <String, dynamic>{
        'packageVersion': 'test-package',
        'assets': [
          {
            'relativePath': 'model.bin',
            'bytes': 4,
            'sha256': sha256.convert(bytes).toString(),
          },
        ],
      };
      final oldPath = AssetInstaller.packageDirectory(manifest, original.path);
      await Directory(oldPath).create(recursive: true);
      await File('$oldPath/model.bin').writeAsBytes(bytes);
      await original.rename(moved.path);
      final installer = AssetInstaller(ApiClient());
      expect(await installer.verifyInstalled(manifest, oldPath), isFalse);
      final currentPath = AssetInstaller.packageDirectory(manifest, moved.path);
      expect(await installer.verifyInstalled(manifest, currentPath), isTrue);
      await File('$currentPath/model.bin').writeAsBytes([4, 3, 2, 1]);
      expect(await installer.verifyInstalled(manifest, currentPath), isFalse);
      expect(
        () => AssetInstaller.packageDirectory(
          <String, dynamic>{...manifest, 'packageVersion': '../escape'},
          moved.path,
        ),
        throwsFormatException,
      );
    },
  );
}
