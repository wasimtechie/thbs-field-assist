#!/usr/bin/env python3
"""Stage pinned, verified Moonshine Small Streaming weights and native runtimes.

All downloads happen at build time. The application uses local files only.
Upstream model CRC32C metadata is pinned from the SDK source, then every staged
file is locked by SHA-256 in the normal offline package manifest.
"""
import base64
import concurrent.futures
import hashlib
import json
import shutil
import tarfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SDK = '0.1.5'
REVISION = '234f60faa0eb388b01cdf7e60aca232af37aefda'
CDN = 'https://download.moonshine.ai/model/small-streaming-en/quantized_26_08_21/'
MIRROR_REVISION = '0bf2f2e5aff22e6fbba4300b00a4e00bbc4f8aae'
MIRROR = f'https://huggingface.co/moonshine-ai/moonshine-voice-assets/resolve/{MIRROR_REVISION}/model/small-streaming-en/quantized_26_08_21/'
MODELS = [
    ('adapter.ort', 2870368, 'XlWjTg=='),
    ('cross_kv.ort', 5356536, '5ySK8g=='),
    ('decoder_kv.ort', 81878600, 'Rn/VUA=='),
    ('encoder.ort', 44148576, '41D2jQ=='),
    ('frontend.model.ort', 26944, 'WW2/2g=='),
    ('frontend.weights.ort', 7769464, '9pROuQ=='),
    ('streaming_config.json', 512, 'dPbFiw=='),
    ('tokenizer.bin', 249974, 'B7s10Q=='),
]
RUNTIMES = [
    ('moonshine-voice-0.1.5.aar',
     'https://repo.maven.apache.org/maven2/ai/moonshine/moonshine-voice/0.1.5/moonshine-voice-0.1.5.aar',
     'ee2d95c21150683c743db8f3aef66281fd5408bcefc94be3ca1d2545ada1f571'),
    ('Moonshine.xcframework.zip',
     'https://github.com/moonshine-ai/moonshine-swift/releases/download/v0.1.5/Moonshine.xcframework.zip',
     '6bc7fb4b6d3a470a2ae2d681299975f3ba9d710753786d1cd7e8beabaad066e8'),
    ('moonshine-macos.tar.gz',
     'https://github.com/moonshine-ai/moonshine/releases/download/v0.1.5/moonshine-voice-macos-arm64.tar.gz',
     '51151f98eb1b20b8fc141bab361a1574dbfdbef8300b632ee6679e373112e0f6'),
]


def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            value.update(block)
    return value.hexdigest()


def crc32c(path):
    table = []
    for n in range(256):
        for _ in range(8):
            n = (n >> 1) ^ (0x82F63B78 if n & 1 else 0)
        table.append(n)
    value = 0xFFFFFFFF
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            for byte in block:
                value = table[(value ^ byte) & 255] ^ (value >> 8)
    return base64.b64encode((value ^ 0xFFFFFFFF).to_bytes(4, 'big')).decode()


def download(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return
    partial = path.with_name(path.name + '.download')
    with urllib.request.urlopen(url, timeout=180) as response, partial.open('wb') as stream:
        shutil.copyfileobj(response, stream)
    partial.replace(path)


def model(entry):
    name, size, crc = entry
    path = ROOT / '.local/model-assets/moonshine-small-streaming' / name
    # The official mirror preserves the exact CDN layout and checksums.
    download(MIRROR + name, path)
    if path.stat().st_size != size or crc32c(path) != crc:
        raise RuntimeError(f'Upstream Moonshine model verification failed: {name}')
    result = {'relativePath': str(path.relative_to(ROOT / '.local/model-assets')),
              'source': CDN + name, 'mirror': MIRROR + name,
              'bytes': size, 'sha256': sha(path), 'crc32c': crc}
    print(json.dumps({'verified': name, 'bytes': size}), flush=True)
    return result


def main():
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        models = list(executor.map(model, MODELS))
    runtime = ROOT / '.local/moonshine-runtime'
    native = ROOT / 'packages/field_voice/native/moonshine'
    for name, url, expected in RUNTIMES:
        path = runtime / name
        download(url, path)
        if sha(path) != expected:
            raise RuntimeError(f'Native runtime checksum mismatch: {name}')
    android = native / 'android/arm64-v8a'
    android.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(runtime / RUNTIMES[0][0]) as archive:
        # Android ELF imports are versioned (VERS_1.23.2 versus sherpa's
        # VERS_1.28.2). Keep both runtimes in separate dependency groups.
        # Same-length NUL-terminated dynstr replacement changes DT_NEEDED,
        # SONAME and the version-requirement filename without moving ELF bytes
        # or touching code/relocations/segment alignment. Real-device/emulator
        # inference tests must pass after this reproducible transformation.
        original = b'libonnxruntime.so\0'
        renamed = b'libmoon_ort123.so\0'
        if len(original) != len(renamed):
            raise RuntimeError('ELF dependency rename must preserve length')
        for source_name, target_name in [
            ('libmoonshine.so', 'libmoonshine.so'),
            ('libonnxruntime.so', 'libmoon_ort123.so'),
        ]:
            data = archive.read('jni/arm64-v8a/' + source_name)
            if data.count(original) != 1:
                raise RuntimeError(f'Unexpected ELF dependency string: {source_name}')
            (android / target_name).write_bytes(data.replace(original, renamed))
    with zipfile.ZipFile(runtime / RUNTIMES[1][0]) as archive:
        for entry in archive.infolist():
            if '..' in Path(entry.filename).parts or Path(entry.filename).is_absolute():
                raise RuntimeError('Unsafe runtime archive path')
        archive.extractall(native / 'apple')
    mac = runtime / 'mac'
    mac.mkdir(exist_ok=True)
    with tarfile.open(runtime / RUNTIMES[2][0]) as archive:
        for entry in archive.getmembers():
            if entry.isfile() and (entry.name.endswith('.dylib') or '.dylib.' in entry.name):
                with archive.extractfile(entry) as source, (mac / Path(entry.name).name).open('wb') as target:
                    shutil.copyfileobj(source, target)
    lock = {'sdkVersion': SDK, 'sourceRevision': REVISION,
            'mirrorRevision': MIRROR_REVISION,
            'model': 'Moonshine Small Streaming English (123M)',
            'modelArch': 4, 'headerVersion': 30000,
            'silero': 'Embedded in the pinned native Moonshine runtime; no network loading',
            'androidOnnxIsolation': {'upstream': 'libonnxruntime.so (1.23.2)',
                'packaged': 'libmoon_ort123.so', 'method': 'same-length ELF dynstr rename',
                'libraries': {p.name: sha(p) for p in android.glob('*.so')}},
            'models': models,
            'runtimes': [{'file': n, 'source': u, 'sha256': s} for n, u, s in RUNTIMES]}
    (ROOT / 'fixtures/voice/moonshine-sources.lock.json').write_text(json.dumps(lock, indent=2) + '\n')
    manifest_path = ROOT / 'fixtures/voice/asset-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['assets'] = [a for a in manifest['assets'] if a['purpose'] not in ['whistle', 'moonshine', 'visit-extractor']]
    for entry in models:
        digest = entry['sha256']
        manifest['assets'].append({
            'id': digest, 'purpose': 'moonshine', 'relativePath': entry['relativePath'],
            'sha256': digest, 'bytes': entry['bytes'], 'source': '/api/v1/assets/' + digest,
            'minimumAppVersion': '0.2.0', 'runtimeVersion': 'moonshine-voice-0.1.5',
            'licence': 'MIT; see docs/licenses/moonshine-LICENSE',
        })
    # eSpeak's native path buffer is bounded. Simulator data-container paths
    # are already long, so keep this package identity compact.
    manifest['packageVersion'] = 'fv-ndl-20261023'
    manifest['requiredPurposes'] = ['moonshine', 'needle3', 'kokoro', 'voices', 'phonemizer', 'tokenizer']
    for platform in manifest['platforms'].values():
        platform['runtime'] = 'moonshine:0.1.5 (Small Streaming + Silero); needle3; sherpa_onnx:1.13.8'
        platform['verified'] = False
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    for name, url in [
        ('moonshine-LICENSE', f'https://raw.githubusercontent.com/moonshine-ai/moonshine/{REVISION}/LICENSE'),
        ('silero-vad-LICENSE', 'https://raw.githubusercontent.com/snakers4/silero-vad/master/LICENSE'),
    ]:
        download(url, ROOT / 'docs/licenses' / name)
    print(json.dumps({'complete': True, 'modelBytes': sum(x['bytes'] for x in models),
                      'modelFiles': len(models), 'nativeSdk': SDK}), flush=True)


if __name__ == '__main__':
    main()
