#!/usr/bin/env python3
"""Repack verified local models in bounded chunks without changing access.

Reuses the signed synthetic demo entitlement verbatim. This script cannot renew
or extend it. Pass a newly provisioned snapshot to package a normal renewal.
"""
import hashlib
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHUNK = 16 * 1024 * 1024


def main():
    target = ROOT / 'apps/mobile/assets/offline_demo'
    source = Path(sys.argv[1]) if len(sys.argv) > 1 else target / 'bootstrap.json'
    snapshot = json.loads(source.read_text())
    if snapshot.get('synthetic') is not True or not snapshot['user']['email'].endswith('@fieldassist.demo'):
        raise RuntimeError('Only the configured synthetic demo can be bundled')
    entitlement = snapshot['entitlement']
    manifest = snapshot['manifest'] if len(sys.argv) > 1 else json.loads((ROOT / 'fixtures/voice/asset-manifest.json').read_text())
    stage = ROOT / f'.local/offline-package-stage-{time.time_ns()}'
    stage.mkdir()
    files, chunks = {}, []
    offset, chunk_start = 0, 0
    buffer = bytearray()

    def flush():
        nonlocal chunk_start
        if not buffer:
            return
        name = f'voice-{len(chunks):03d}.bin'
        (stage / name).write_bytes(buffer)
        chunks.append({'file': name, 'offset': chunk_start, 'bytes': len(buffer),
                       'sha256': hashlib.sha256(buffer).hexdigest()})
        chunk_start += len(buffer)
        buffer.clear()

    for asset in manifest['assets']:
        relative = Path(asset['relativePath'])
        if relative.is_absolute() or '..' in relative.parts:
            raise RuntimeError('Unsafe model path')
        path = ROOT / '.local/model-assets' / relative
        digest, size = hashlib.sha256(), 0
        files[str(relative)] = {'offset': offset, 'bytes': asset['bytes']}
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1048576), b''):
                digest.update(block)
                size += len(block)
                offset += len(block)
                at = 0
                while at < len(block):
                    count = min(CHUNK - len(buffer), len(block) - at)
                    buffer.extend(block[at:at + count])
                    at += count
                    if len(buffer) == CHUNK:
                        flush()
        if size != asset['bytes'] or digest.hexdigest() != asset['sha256']:
            raise RuntimeError(f'Model integrity failure: {relative}')
    flush()
    snapshot.update(formatVersion=2, manifest=manifest, files=files,
                    voiceChunks=chunks, voiceBytes=offset)
    if snapshot['entitlement'] != entitlement:
        raise RuntimeError('Signed access must never change during repacking')
    (stage / 'bootstrap.json').write_text(json.dumps(snapshot, indent=2) + '\n')
    notices = []
    for path in sorted((ROOT / 'docs/licenses').iterdir()):
        if path.is_file():
            notices.append(path.name + '\n\n' + path.read_text())
    (stage / 'THIRD_PARTY_NOTICES.txt').write_text('\n\n'.join(notices))
    backup = ROOT / f'.local/offline-package-backup-{time.time_ns()}'
    if target.exists():
        target.rename(backup)
    stage.rename(target)
    print(json.dumps({'synthetic': True, 'formatVersion': 2,
                      'modelFiles': len(files), 'voiceBytes': offset,
                      'chunks': len(chunks), 'maximumChunkBytes': CHUNK,
                      'signedAccessPreserved': True}))


if __name__ == '__main__':
    main()
