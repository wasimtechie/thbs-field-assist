#!/usr/bin/env python3
"""Verify the delivered offline APK without displaying account configuration."""
import hashlib
import json
import sys
import zipfile
import base64
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    apk = Path(sys.argv[1])
    prefix = 'assets/flutter_assets/'
    with zipfile.ZipFile(apk) as archive:
        assert archive.testzip() is None, 'APK ZIP integrity failure'
        snapshot = json.loads(archive.read(prefix + 'assets/offline_demo/bootstrap.json'))
        assert snapshot['formatVersion'] == 2
        claims = json.loads(base64.urlsafe_b64decode(snapshot['entitlement'].split('.')[1] + '=='))
        non_expiring = claims.get('expiresAt') is None
        if non_expiring:
            assert claims.get('offlineAccess') == 'non-expiring-synthetic-demo'
            assert claims.get('demoAccount') == snapshot['user']['email'] == 'closure@fieldassist.demo'
            assert claims.get('organizationId') == snapshot['user']['organizationId'] == '10000000-0000-4000-8000-000000000001'
            assert claims.get('allowedTemplateIds') == ['40000000-0000-4000-8000-000000000006']
            assert 'expiresAt' in claims and 'exp' not in claims
        else:
            expires = datetime.fromisoformat(claims['expiresAt'].replace('Z', '+00:00'))
            assert expires > datetime.now(timezone.utc), 'Bundled demo access has expired; provision normally before building'
        manifest = snapshot['manifest']
        assert len(manifest['packageVersion']) <= 16, 'Keep the shared iOS phonemizer path bounded'
        purposes = {a['purpose'] for a in manifest['assets']}
        assert {'moonshine', 'needle3', 'kokoro'} <= purposes
        assert 'visit-extractor' not in purposes, 'Qwen must not be bundled in the small-model build'
        assert not any('qwen' in a['relativePath'].lower() or a['relativePath'].lower().endswith('.gguf') for a in manifest['assets']), 'Historical LLM cache must not be staged as model data'
        assert 'whistle' not in purposes
        cached, cached_index = None, -1
        chunks = snapshot['voiceChunks']
        verified_chunks = set()

        def chunk(index):
            nonlocal cached, cached_index
            if index != cached_index:
                item = chunks[index]
                cached = archive.read(prefix + 'assets/offline_demo/' + item['file'])
                assert len(cached) == item['bytes'] <= 16 * 1024 * 1024
                assert hashlib.sha256(cached).hexdigest() == item['sha256']
                cached_index = index
                verified_chunks.add(index)
            return cached

        total = 0
        for asset in manifest['assets']:
            item = snapshot['files'][asset['relativePath']]
            assert item['bytes'] == asset['bytes']
            at, remaining = item['offset'], item['bytes']
            digest = hashlib.sha256()
            while remaining:
                index = next(i for i, c in enumerate(chunks)
                             if c['offset'] <= at < c['offset'] + c['bytes'])
                data = chunk(index)
                offset = at - chunks[index]['offset']
                count = min(remaining, len(data) - offset)
                digest.update(memoryview(data)[offset:offset + count])
                at, remaining = at + count, remaining - count
            assert digest.hexdigest() == asset['sha256'], asset['relativePath']
            total += item['bytes']
        assert len(verified_chunks) == len(chunks)
        assert total == snapshot['voiceBytes']
        index = json.loads(archive.read(prefix + 'assets/voice_questions/index.json'))
        expected_index = json.loads((ROOT / 'apps/mobile/assets/voice_questions/index.json').read_text())
        assert index == expected_index, 'APK must contain the current voice prompt catalogue'
        assert index['formatVersion'] == 2
        assert set(index['voices']) == {'bm_george', 'bf_emma', 'am_michael', 'af_sarah'}
        assert index['prompts'] == index['voices'][index['voice']]['prompts']
        prompt_files = set()
        voice_counts = {}
        for voice, pack in index['voices'].items():
            prompts = pack['prompts']
            voice_counts[voice] = len(prompts)
            for prompt_hash, entry in prompts.items():
                assert hashlib.sha256(entry['text'].encode()).hexdigest() == prompt_hash
                data = archive.read(prefix + 'assets/voice_questions/' + entry['file'])
                assert hashlib.sha256(data).hexdigest() == entry['sha256']
                assert data[:4] == b'RIFF' and data[8:12] == b'WAVE'
                prompt_files.add(entry['file'])
        count = len(prompt_files)
        assert count == sum(voice_counts.values()), 'Each voice must have its own verified prompts'
        assert archive.read(prefix + 'assets/offline_demo/THIRD_PARTY_NOTICES.txt')
        kernel = archive.read(prefix + 'kernel_blob.bin')
        assert len(kernel) > 1048576, 'Compiled application kernel is missing'
        assert b'MOONSHINE_OFFLINE_NATIVE_PASSED' not in kernel, 'Do not deliver the integration test harness'
        native = [n for n in archive.namelist() if n.startswith('lib/') and n.endswith('.so')]
        assert all(n.startswith('lib/arm64-v8a/') for n in native)
        locked = json.loads((ROOT / 'fixtures/voice/moonshine-sources.lock.json').read_text())
        for name, expected in locked['androidOnnxIsolation']['libraries'].items():
            data = archive.read('lib/arm64-v8a/' + name)
            assert hashlib.sha256(data).hexdigest() == expected, name
            assert b'libmoon_ort123.so\0' in data
            assert b'libonnxruntime.so\0' not in data
        assert 'lib/arm64-v8a/libonnxruntime.so' in native
        assert not any('llama' in n.lower() or 'ggml' in n.lower() for n in native), 'Large-model native runtime must be removed'
        assert not any('qwen' in n.lower() or n.lower().endswith('.gguf') for n in archive.namelist())
        assert not any('vulkan' in n.lower() or 'vklayer' in n.lower() for n in native), 'Unused GPU backends must not be packaged'
    digest = hashlib.sha256()
    with apk.open('rb') as stream:
        for data in iter(lambda: stream.read(1048576), b''):
            digest.update(data)
    result = {'apk': apk.name, 'bytes': apk.stat().st_size,
              'sha256': digest.hexdigest(), 'modelFiles': len(manifest['assets']),
              'modelBytes': total, 'chunks': len(chunks), 'verifiedPrompts': count,
              'voicePrompts': voice_counts, 'offlineAccessExpiresAt': claims['expiresAt'],
              'nonExpiringSyntheticDemo': non_expiring,
              'nativeLibraries': len(native), 'arm64Only': True,
              'offlineModelIntegrityVerified': True, 'regularApplication': True}
    apk.with_suffix('.apk.sha256').write_text(digest.hexdigest() + '  ' + apk.name + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
