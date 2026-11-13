#!/usr/bin/env python3
"""Verify local/staged inputs and save reproducibility evidence after timing."""
import argparse
import hashlib
import json
import os
import platform
import subprocess
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / '.local/phonon-ab'


def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            value.update(block)
    return value.hexdigest()


def command(*args):
    return subprocess.check_output(args, text=True, timeout=60).strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--android-device', default='emulator-5554')
    args = parser.parse_args()
    lock = json.loads((ROOT / 'fixtures/voice/phonon-ab-sources.lock.json').read_text())
    for key in ['model', 'pythonRuntime', 'androidRuntime']:
        assert sha(LAB / lock[key]['file']) == lock[key]['sha256'], key
    assert sha(LAB / 'model/model.fermion') == lock['model']['containerSha256']
    tensor = json.loads((LAB / 'tensor-provenance.json').read_text())
    assert sha(LAB / 'run/phonon-tensors.bin') == tensor['preparedSha256']
    moonshine = json.loads((ROOT / 'fixtures/voice/moonshine-sources.lock.json').read_text())
    staged = {name: LAB / 'run' / name for name in ['phonon-tensors.bin', 'vocabulary.bin', 'cases.tsv']}
    for entry in moonshine['models']:
        name = Path(entry['relativePath']).name
        path = LAB / 'run/moonshine' / name
        assert sha(path) == entry['sha256'], name
        staged['moonshine/' + name] = path
    staged.update({'audio/' + p.name: p for p in (LAB / 'run/audio').glob('*.pcm')})
    staged['benchmark'] = LAB / 'bin/benchmark-android'
    staged.update({'lib/' + p.name: p for p in (LAB / 'lib-android').iterdir() if p.is_file()})
    hashes = {name: sha(path) for name, path in staged.items()}
    sdk = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk'))
    adb = str(sdk / 'platform-tools/adb')
    remote_root = '/data/local/tmp/field-stt-ab/'
    remote = command(adb, '-s', args.android_device, 'shell', 'sha256sum',
                     *[remote_root + name for name in staged])
    remote_hashes = {line.split()[1].removeprefix(remote_root): line.split()[0]
                     for line in remote.splitlines()}
    assert hashes == remote_hashes, 'Android staged inputs differ from local files'
    native = LAB / 'wheel-inspection/fermion/_speech/_engine_phonon2_cpu'
    ios = {}
    with zipfile.ZipFile(LAB / lock['pythonRuntime']['file']) as archive:
        for name in ['enc', 'tdt']:
            member = f'fermion/_speech/_engine_phonon2_cpu/libphonon2_{name}-macos-arm64.dylib'
            assert sha(native / Path(member).name) == hashlib.sha256(archive.read(member)).hexdigest()
    for name in ['enc', 'tdt']:
        original = native / f'libphonon2_{name}-macos-arm64.dylib'
        experimental = LAB / 'run/lib-ios-experimental' / name
        original_text = '\n'.join(command('xcrun', 'otool', '-s', '__TEXT', '__text', str(original)).splitlines()[2:])
        simulator_text = '\n'.join(command('xcrun', 'otool', '-s', '__TEXT', '__text', str(experimental)).splitlines()[2:])
        assert original_text == simulator_text, 'Simulator port changed kernel instructions'
        ios[name] = {'originalSha256': sha(original), 'simulatorPortSha256': sha(experimental),
                     'instructionSectionMatched': True,
                     'instructionDumpSha256': hashlib.sha256(original_text.encode()).hexdigest(),
                     'originalBuildVersion': command('xcrun', 'vtool', '-show-build', str(original)).splitlines()[1:],
                     'simulatorBuildVersion': command('xcrun', 'vtool', '-show-build', str(experimental)).splitlines()[1:]}
    with zipfile.ZipFile(LAB / 'android-runtime.zip') as archive:
        android_vendor = {n: hashlib.sha256(archive.read(n)).hexdigest()
                          for n in archive.namelist() if n.endswith('.so')}
    for name in ['enc', 'tdt']:
        for suffix in ['', '-base']:
            wanted = f'libphonon2_{name}-android-arm64-v8a{suffix}.so'
            vendor_hash = next(h for n, h in android_vendor.items() if Path(n).name == wanted)
            assert sha(LAB / 'lib-android' / (name + suffix)) == vendor_hash
    for name, expected in moonshine['androidOnnxIsolation']['libraries'].items():
        assert sha(LAB / 'lib-android' / ('moonshine' if name == 'libmoonshine.so' else name)) == expected
    sources = list((ROOT / 'scripts/stt-ab').glob('*'))
    sources += [ROOT / f'apps/mobile/lib/features/closure/{name}.dart' for name in
                ['compact_narrative', 'optical_reading', 'closure_speech']]
    sources += [ROOT / f'apps/mobile/lib/features/voice/{name}.dart' for name in
                ['asset_reference', 'spoken_numbers']]
    sources += [ROOT / 'fixtures/templates/closure-mvp.json']
    sources += [LAB / 'run/cases.json', LAB / 'model/config.json', LAB / 'model/packed_manifest.json']
    evidence = {
        'capturedUtc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'host': {'os': platform.platform(), 'cpu': command('sysctl', '-n', 'machdep.cpu.brand_string'),
                 'memoryBytes': int(command('sysctl', '-n', 'hw.memsize')),
                 'physicalCores': int(command('sysctl', '-n', 'hw.physicalcpu'))},
        'xcode': command('xcodebuild', '-version'),
        'pythonPackages': json.loads(command(str(LAB / '.venv/bin/python'), '-m', 'pip', 'list', '--format=json')),
        'audioSynthesisPackages': json.loads(command(str(ROOT / '.local/voice-lab/.venv/bin/python'), '-m', 'pip', 'list', '--format=json')),
        'androidEmulator': {'physicalPhone': False, 'cores': 2, 'memoryMb': 3072, 'abi': 'arm64-v8a', 'api': 37},
        'sourceLock': lock, 'tensorPreparation': tensor,
        'frontendParity': json.loads((LAB / 'frontend-parity.json').read_text()),
        'sourceSha256': {str(p.relative_to(ROOT)): sha(p) for p in sources if p.is_file()},
        'androidRemoteAllMatched': True, 'stagedSha256': hashes,
        'iosExperimentalKernels': ios, 'androidVendorLibraries': android_vendor,
        'runnerSha256': {p.name: sha(p) for p in (LAB / 'bin').glob('benchmark-*')},
    }
    (LAB / 'provenance.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'verifiedLocalAndRemoteFiles': len(staged), 'provenance': '.local/phonon-ab/provenance.json'}))


if __name__ == '__main__':
    main()
