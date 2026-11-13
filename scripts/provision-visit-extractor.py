#!/usr/bin/env python3
"""Bundle a pinned Qwen3-0.6B Q4 model; inference never downloads a model."""
import hashlib
import json
import shutil
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = 'unsloth/Qwen3-0.6B-GGUF'
REVISION = '50968a4468ef4233ed78cd7c3de230dd1d61a56b'
NAME = 'Qwen3-0.6B-Q4_K_M.gguf'
SIZE = 396705472
SHA = 'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a'


def main():
    source = f'https://huggingface.co/{REPO}/resolve/{REVISION}/{NAME}'
    target = ROOT / '.local/model-assets/visit-qwen3-0.6b-q4.gguf'
    if not target.exists():
        partial = target.with_suffix('.download')
        with urllib.request.urlopen(source, timeout=180) as inp, partial.open('wb') as out:
            shutil.copyfileobj(inp, out)
        partial.replace(target)
    digest = hashlib.sha256()
    with target.open('rb') as stream:
        for block in iter(lambda: stream.read(1048576), b''):
            digest.update(block)
    if target.stat().st_size != SIZE or digest.hexdigest() != SHA:
        raise RuntimeError('Qwen model integrity failure')
    manifest_path = ROOT / 'fixtures/voice/asset-manifest.json'
    manifest = json.loads(manifest_path.read_text())
    manifest['assets'] = [a for a in manifest['assets'] if a['purpose'] != 'visit-extractor']
    manifest['assets'].append({
        'id': SHA, 'purpose': 'visit-extractor', 'relativePath': target.name,
        'sha256': SHA, 'bytes': SIZE, 'source': '/api/v1/assets/' + SHA,
        'minimumAppVersion': '0.2.0', 'runtimeVersion': 'llamadart-0.16.0; llama.cpp-v0.7.0-2',
        'licence': 'Apache-2.0; see docs/licenses/Qwen3-LICENSE',
    })
    if 'visit-extractor' not in manifest['requiredPurposes']:
        manifest['requiredPurposes'].append('visit-extractor')
    for platform in manifest['platforms'].values():
        label = '; Qwen3-0.6B-Q4_K_M / llamadart-0.16.0 (CPU)'
        if label not in platform['runtime']:
            platform['runtime'] += label
        platform['verified'] = False
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    lock = {'repo': REPO, 'revision': REVISION, 'file': NAME, 'source': source,
            'relativePath': target.name, 'bytes': SIZE, 'sha256': SHA, 'licence': 'Apache-2.0',
            'runtimePackage': 'llamadart-0.16.0', 'nativeRuntime': 'llamadart-native-v0.7.0-2'}
    (ROOT / 'fixtures/voice/visit-extraction-sources.lock.json').write_text(json.dumps(lock, indent=2) + '\n')
    licence = ROOT / 'docs/licenses/Qwen3-LICENSE'
    if not licence.exists():
        url = 'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/23749fefcc72300e3a2ad315e1317431b06b590a/LICENSE'
        licence.write_bytes(urllib.request.urlopen(url).read())
    print(json.dumps({'verified': True, 'model': NAME, 'bytes': SIZE, 'sha256': SHA}))


if __name__ == '__main__':
    main()
