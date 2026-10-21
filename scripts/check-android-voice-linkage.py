#!/usr/bin/env python3
"""Reject a voice library/APK whose math symbols have no declared libm dependency.

This checks the real ELF dependency contract; device inference remains a separate
acceptance check. It never loads an account database or captures audio.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('input', type=Path)
parser.add_argument('--readelf', type=Path)
parser.add_argument('--report', type=Path)
args = parser.parse_args()
if args.readelf is None:
    roots = [Path(os.environ.get('ANDROID_HOME', '/opt/homebrew/share/android-commandlinetools')),
             Path('/opt/homebrew/share/android-commandlinetools'),
             Path.home() / 'Library/Android/sdk']
    candidates = [p for root in roots for p in root.glob(
        'ndk/28.2.13676358/toolchains/llvm/prebuilt/*/bin/llvm-readelf')]
    if not candidates:
        raise SystemExit('Pass --readelf for the installed Android NDK llvm-readelf.')
    args.readelf = candidates[0]

with tempfile.TemporaryDirectory() as directory:
    if args.input.suffix == '.apk':
        library = Path(directory) / 'libfield_voice.so'
        with zipfile.ZipFile(args.input) as archive:
            library.write_bytes(archive.read('lib/arm64-v8a/libfield_voice.so'))
    else:
        library = args.input
    dynamic = subprocess.check_output([str(args.readelf), '-dW', str(library)], text=True)
    symbols = subprocess.check_output([str(args.readelf), '--dyn-syms', '--wide', str(library)], text=True)
    needed = re.findall(r'Shared library: \[([^\]]+)\]', dynamic)
    undefined = {m.group(1).split('@')[0] for line in symbols.splitlines()
                 if (m := re.search(r'\bUND\s+(\S+)', line))}
    math_symbols = sorted(undefined & {
        'exp', 'expf', 'exp2f', 'log', 'logf', 'log10', 'log10f', 'pow', 'powf',
        'sqrt', 'sqrtf', 'sinf', 'sin', 'cos', 'cosf', 'tanh', 'tanhf',
        'ceil', 'ceilf', 'floor', 'floorf', 'fmod', 'fmodf', 'hypot', 'hypotf',
    })
    passed = not math_symbols or 'libm.so' in needed
    report = {'input': args.input.name, 'neededLibraries': needed,
              'undefinedMathSymbols': math_symbols, 'mathDependencyDeclared': passed,
              'scope': 'ELF dependency inspection; not microphone or end-to-end inference acceptance.'}
    output = json.dumps(report, indent=2) + '\n'
    if args.report:
        args.report.write_text(output)
    print(output, end='')
    raise SystemExit(0 if passed else 1)
