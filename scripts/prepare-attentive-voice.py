#!/usr/bin/env python3
"""Build dry speech-only questions for the phone's selectable offline voices.

Uses the already verified local Kokoro package. No server, microphone input,
reference recording, soundtrack, music mixer or network access is used.
"""
import hashlib
import json
import shutil
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT / '.local/voice-lab'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    import numpy as np
    import sherpa_onnx
    import soundfile as sf

    exported = json.loads((LAB / 'question-prompts.json').read_text())
    profile = exported['speechProfile']
    sources = json.loads((ROOT / 'fixtures/voice/model-sources.lock.json').read_text())
    archive = sources['kokoroArchive']
    manifest = json.loads((ROOT / 'fixtures/voice/asset-manifest.json').read_text())
    assets = ROOT / '.local/model-assets'
    for asset in manifest['assets']:
        if asset['relativePath'].startswith('kokoro/'):
            path = assets / asset['relativePath']
            if path.stat().st_size != asset['bytes'] or sha(path) != asset['sha256']:
                raise RuntimeError(f"Local voice asset failed verification: {asset['relativePath']}")
    runtime = sherpa_onnx.__version__
    staging = LAB / f'attentive-pack-{time.time_ns()}'
    staging.mkdir()
    model = assets / 'kokoro'
    engine = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                model=str(model / 'model.onnx'), voices=str(model / 'voices.bin'),
                tokens=str(model / 'tokens.txt'), data_dir=str(model / 'espeak-ng-data')),
            num_threads=2, provider='cpu'), max_num_sentences=1, silence_scale=.2))
    voices = {}
    for selected in exported.get('speechProfiles', [profile]):
        settings = {**selected, 'runtime': runtime, 'backgroundAudio': False,
                    'modelSha256': sha(assets / 'kokoro/model.onnx'),
                    'voicesSha256': sha(assets / 'kokoro/voices.bin')}
        identity = hashlib.sha256(json.dumps(settings, sort_keys=True).encode()).hexdigest()
        cache = LAB / 'attentive-cache' / identity
        cache.mkdir(parents=True, exist_ok=True)
        entries = {}
        for prompt in exported['prompts']:
            if selected['voice'] != profile['voice'] and not prompt.get('allVoices'):
                continue
            key = hashlib.sha256(prompt['text'].encode()).hexdigest()
            wave = cache / f'{key}.wav'
            started = time.perf_counter()
            if not wave.exists():
                result = engine.generate(prompt['text'], sid=selected['speakerId'], speed=selected['speed'])
                pcm = np.asarray(result.samples, dtype=np.float32)
                if not len(pcm) or not np.isfinite(pcm).all() or result.sample_rate != 24000 or len(pcm) / result.sample_rate > 46:
                    raise RuntimeError(f"Invalid generated speech: {prompt['fieldId']}")
                sf.write(wave, pcm, result.sample_rate, subtype='PCM_16')
            pcm, rate = sf.read(wave, dtype='float32')
            if rate != 24000 or pcm.ndim != 1 or not len(pcm) or not np.isfinite(pcm).all():
                raise RuntimeError('Invalid cached voice recording')
            filename = f'{key}.wav' if selected['voice'] == profile['voice'] else f"{selected['voice']}-{key}.wav"
            shutil.copy2(wave, staging / filename)
            entries[key] = {'fieldId': prompt['fieldId'], 'text': prompt['text'],
                            'file': filename, 'sha256': sha(wave)}
            print(json.dumps({'fieldId': prompt['fieldId'], 'voice': selected['voice'],
                              'seconds': round(len(pcm) / rate, 2),
                              'generationMs': round((time.perf_counter() - started) * 1000, 1)}), flush=True)
        voices[selected['voice']] = {'model': selected['model'], 'voice': selected['voice'],
                                    'settings': settings, 'prompts': entries}
    index = {**voices[profile['voice']], 'formatVersion': 2, 'voices': voices,
             'revision': archive['sha256'], 'source': archive['source'], 'runtimeVersion': runtime,
             'disclosure': 'Speech-only offline Kokoro prompts. Speaker IDs and level processing match local fallback. No background audio is mixed.'}
    (staging / 'index.json').write_text(json.dumps(index, indent=2) + '\n')
    pack = ROOT / 'apps/mobile/assets/voice_questions'
    old = LAB / 'archived-voice-packs' / f'replaced-{time.time_ns()}'
    old.parent.mkdir(exist_ok=True)
    if pack.exists():
        pack.rename(old)
    try:
        staging.rename(pack)
    except Exception:
        if old.exists() and not pack.exists():
            old.rename(pack)
        raise
    print(json.dumps({'complete': True, 'recordings': sum(len(v['prompts']) for v in voices.values()),
                      'model': profile['model'], 'voice': profile['voice'],
                      'previousPackArchived': str(old.relative_to(ROOT))}), flush=True)


if __name__ == '__main__':
    main()
