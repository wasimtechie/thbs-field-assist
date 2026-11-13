#!/usr/bin/env python3
"""Build isolated diagnostic runners from already verified local dependencies.

No Flutter assets, native app runtimes, signing settings or reports are changed.
The experimental iOS option changes COPIES of macOS kernels for the simulator;
it must never be used as an iPhone distribution runtime.
"""
import argparse
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / '.local/phonon-ab'
NATIVE = ROOT / 'packages/field_voice/native/moonshine'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['macos', 'android', 'ios-simulator'])
    parser.add_argument('--experimental-simulator-port', action='store_true')
    args = parser.parse_args()
    output = LAB / 'bin' / f'benchmark-{args.platform}'
    output.parent.mkdir(parents=True, exist_ok=True)
    flags = ['-std=c++17', '-O3', '-ffp-contract=off',
             str(ROOT / 'scripts/stt-ab/benchmark.cpp'),
             '-I', str(LAB / 'android-runtime/phonon2-android-arm64-v8a-0.2.11'),
             '-I', str(NATIVE / 'apple/Moonshine.xcframework/ios-arm64/Headers'),
             '-o', str(output)]
    if args.platform == 'android':
        sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
        compiler = sdk / 'ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android31-clang++'
        cmd = [str(compiler), *flags, '-static-libstdc++',
               '-Wl,-z,max-page-size=16384', '-ldl', '-lm']
    elif args.platform == 'ios-simulator':
        if not args.experimental_simulator_port:
            parser.error('Exact Phonon-2.5 has no qualified iPhone runtime here. '
                         'This diagnostic requires --experimental-simulator-port.')
        libraries = LAB / 'run/lib-ios-experimental'
        libraries.mkdir(parents=True, exist_ok=True)
        for name in ['enc', 'tdt']:
            original = LAB / f'wheel-inspection/fermion/_speech/_engine_phonon2_cpu/libphonon2_{name}-macos-arm64.dylib'
            target = libraries / name
            shutil.copyfile(original, target)
            subprocess.run(['xcrun', 'vtool', '-set-build-version', 'iossim', '18.0',
                            '27.0', '-replace', '-output', str(target), str(target)], check=True)
            subprocess.run(['codesign', '--force', '--sign', '-', str(target)], check=True)
        archive = NATIVE / 'apple/Moonshine.xcframework/ios-arm64_x86_64-simulator/libmoonshine.a'
        cmd = ['xcrun', '--sdk', 'iphonesimulator', 'clang++',
               '-target', 'arm64-apple-ios18.0-simulator', '-DFA_STATIC_MOONSHINE',
               *flags, f'-Wl,-force_load,{archive}']
        for framework in ['Foundation', 'Accelerate', 'CoreML', 'AVFoundation', 'AudioToolbox']:
            cmd += ['-framework', framework]
    else:
        cmd = ['clang++', *flags]
    subprocess.run(cmd, check=True, cwd=ROOT)
    if args.platform == 'ios-simulator':
        subprocess.run(['codesign', '--force', '--sign', '-', str(output)], check=True)
    print(output)


if __name__ == '__main__':
    main()
