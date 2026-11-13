#!/usr/bin/env python3
"""Run the isolated native STT comparison; preserve Android radio settings."""
import argparse
import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / '.local/phonon-ab'
OUT = LAB / 'results'
ADB = Path(os.environ.get('ANDROID_HOME', Path.home() / 'Library/Android/sdk')) / 'platform-tools/adb'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('platform', choices=['ios-simulator', 'android-emulator'])
    parser.add_argument('--phase', choices=['bulk', 'paced', 'focused'], default='bulk')
    parser.add_argument('--device', default=None)
    parser.add_argument('--models', nargs='+', default=None)
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    models = args.models or (['moonshine', 'phonon', 'phonon-plain'] if args.phase == 'bulk' else ['moonshine', 'phonon-plain'])
    before = {}
    device = args.device or ('booted' if args.platform == 'ios-simulator' else 'emulator-5554')
    adb = [str(ADB), '-s', device]

    def android(*cmd):
        return subprocess.check_output(adb + ['shell'] + list(cmd), text=True, timeout=30).strip()

    meta = {'platform': args.platform, 'phase': args.phase, 'models': models,
            'synthetic': True, 'physicalDevice': False,
            'networkUse': 'Runner loads only filesystem models and PCM; has no HTTP/socket client or model fetch path.',
            'latencyScope': 'Bulk: complete-audio compute. Paced: fixture-known endpoint plus 1800 ms S1 pause (450 ms for focused short answers); excludes microphone, natural VAD, extraction, TTS and audio playback.',
            'iosPhononRuntime': 'EXPERIMENTAL simulator-only CPU port. Original pinned macOS ARM64 C kernels, LC_BUILD_VERSION changed to iOS Simulator, ad-hoc signed. Not a vendor-supported iPhone runtime.' if args.platform == 'ios-simulator' else None,
            'phononThreads': 2, 'moonshineThreads': 'Published runtime default, same production load options.',
            'startedUtc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
    metadata_path = OUT / f'{args.platform}-{args.phase}-metadata.json'
    try:
        if args.platform == 'android-emulator':
            for key in ['airplane_mode_on', 'wifi_on', 'mobile_data']:
                before[key] = android('settings', 'get', 'global', key)
            meta['radioSettingsBefore'] = before.copy()
            android('cmd', 'connectivity', 'airplane-mode', 'enable')
            android('svc', 'wifi', 'disable')
            android('svc', 'data', 'disable')
            meta['radioSettingsDuring'] = {k: android('settings', 'get', 'global', k) for k in before}
            meta['androidDevice'] = {k: android('getprop', k) for k in ['ro.product.model', 'ro.build.version.sdk', 'ro.product.cpu.abi']}
        metadata_path.write_text(json.dumps(meta, indent=2) + '\n')
        for model in models:
            assert model in ['moonshine', 'phonon', 'phonon-plain']
            if args.platform == 'ios-simulator':
                cmd = ['xcrun', 'simctl', 'spawn', device, str(LAB / 'bin/benchmark-ios-simulator'),
                       str(LAB / 'run'), str(LAB / 'run/lib-ios-experimental')]
            else:
                cmd = adb + ['shell', 'env', 'LD_LIBRARY_PATH=/data/local/tmp/field-stt-ab/lib',
                             '/data/local/tmp/field-stt-ab/benchmark', '/data/local/tmp/field-stt-ab',
                             '/data/local/tmp/field-stt-ab/lib']
            cmd += [model, '2' if args.phase == 'bulk' else '1', '2']
            if args.phase != 'bulk':
                cmd += ['s1-' if args.phase == 'paced' else 'rx-18-v', 'paced']
            stem = f'{args.platform}-{args.phase}-{model}'
            print(json.dumps({'starting': stem}), flush=True)
            with (OUT / (stem + '.jsonl')).open('w') as out, (OUT / (stem + '.stderr')).open('w') as err:
                subprocess.run(cmd, stdout=out, stderr=err, check=True, timeout=1200)
            records = [json.loads(l) for l in (OUT / (stem + '.jsonl')).read_text().splitlines() if l.startswith('{')]
            assert any(r.get('event') == 'result' for r in records), 'Runner produced no recognition results'
            print(json.dumps({'completed': stem, 'recognitions': sum(r.get('event') == 'result' for r in records)}), flush=True)
        meta['completed'] = True
    finally:
        if args.platform == 'android-emulator' and before:
            if before.get('airplane_mode_on') in ['0', '1']:
                android('cmd', 'connectivity', 'airplane-mode', 'enable' if before['airplane_mode_on'] == '1' else 'disable')
            if before.get('wifi_on') in ['0', '1']:
                android('svc', 'wifi', 'enable' if before['wifi_on'] == '1' else 'disable')
            if before.get('mobile_data') in ['0', '1']:
                android('svc', 'data', 'enable' if before['mobile_data'] == '1' else 'disable')
            meta['radioSettingsAfter'] = {k: android('settings', 'get', 'global', k) for k in before}
        meta['finishedUtc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
        metadata_path.write_text(json.dumps(meta, indent=2) + '\n')


if __name__ == '__main__':
    main()
