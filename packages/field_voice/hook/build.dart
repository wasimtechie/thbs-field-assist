import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final os = input.config.code.targetOS,
        arch = input.config.code.targetArchitecture;
    final platform = os == OS.iOS
        ? (input.config.code.iOS.targetSdk == IOSSdk.iPhoneSimulator
              ? 'ios-sim-arm64'
              : 'ios-arm64')
        : os == OS.android
        ? 'android-arm64'
        : os == OS.macOS
        ? 'macos-arm64'
        : 'unsupported';
    final directory = 'native/$platform';
    final archive = File.fromUri(
      input.packageRoot.resolve('$directory/libneedle.a'),
    );
    final available = arch == Architecture.arm64 && await archive.exists();
    final builder = CBuilder.library(
      name: 'field_voice',
      assetName: 'field_voice_bindings_generated.dart',
      sources: ['src/field_voice.c'],
      includes: available ? [directory] : [],
      // The static inference archive uses libm. Android does not inherit math
      // symbols from Flutter's separately loaded libraries at dlopen time.
      libraries: available ? ['needle', if (os == OS.android) 'm'] : [],
      libraryDirectories: available ? [archive.parent.path] : [],
      defines: {if (available) 'FIELD_VOICE_HAS_NEEDLE': '1'},
      flags: os == OS.android
          ? ['-Wl,-z,max-page-size=16384', '-Wl,--no-undefined']
          : [],
      language: Language.cpp,
      cppLinkStdLib: os == OS.android ? 'c++_static' : 'c++',
    );
    if (available) output.dependencies.add(archive.uri);
    await builder.run(
      input: input,
      output: output,
      logger: Logger('field_voice'),
    );
  });
}
