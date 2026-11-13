#!/usr/bin/env python3
"""Prepare lossless Phonon tensor records and synthetic, shared STT fixtures.

Run with the isolated fermion-research 0.2.15 environment. This never reads
microphone audio, account files or reports, and does not change the app bundle.
"""
import hashlib
import importlib.util
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LAB = ROOT / '.local/phonon-ab'
OUT = LAB / 'run'
TERMS = 'ONT,CBT,CSP,FTTP,fibre,fibre route,dBm,decibels,optical receive,optical receive reading,service test'


def tensors():
    import numpy as np
    import torch
    from fermion._speech.hotwords import build
    from fermion._speech.engine_phonon2_cpu import mel_filters
    source = LAB / 'model/model.fermion'
    expected = json.loads((LAB / 'model-release-config.json').read_text())['artifact']['container_sha256']
    assert hashlib.sha256(source.read_bytes()).hexdigest() == expected
    path = LAB / 'wheel-inspection/fermion/_speech/_engine_phonon2/fermion_container.py'
    spec = importlib.util.spec_from_file_location('phonon_records', path)
    fc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fc)
    records = []
    with source.open('rb') as f:
        h = json.loads(f.read(int.from_bytes(f.read(8), 'little')))
        for e in h['index']:
            blob = f.read(e['b'])
            assert len(blob) == e['b']
            name, shape, kind = e['n'], e['shape'], e['k']
            rows, cols = shape[0] if shape else 1, math.prod(shape[1:]) or 1
            if kind == 'five_value':
                records.append((name, 1, rows, cols, blob))
            elif kind.startswith('int'):
                raw = {}
                dense = fc._intn(blob, shape, int(kind[3:]), raw)
                if name.startswith(('decoder.', 'joint.')):
                    records.append((name + '.q', 2, rows, cols, raw['q'].tobytes()))
                    records.append((name + '.s', 4, rows, 1, raw['scale'].astype('<f2').tobytes()))
                else:
                    records.append((name, 3, rows, cols, dense.astype('<f4').tobytes()))
            elif kind == 'fp16':
                a = np.frombuffer(blob, dtype='<f2')
                records.append((name, 3, rows, cols, a.astype('<f4').tobytes()))
                if name.startswith(('decoder.', 'joint.')):
                    records.append((name + '.h', 4, rows, cols, blob))
            else:
                raise ValueError(kind)
        assert not f.read(1)
    inv = 1 / (10000.0 ** (torch.arange(0, 1024, 2, dtype=torch.float32) / 1024))
    window = np.pad(torch.hann_window(400, periodic=False).numpy(), (56, 56))
    for name, a in [('inv_freq', inv.numpy()), ('mel_filters', mel_filters()), ('window', window)]:
        records.append((name, 3, a.shape[0], math.prod(a.shape[1:]) or 1, a.astype('<f4').tobytes()))
    config = json.loads((LAB / 'model/config.json').read_text())
    vocabulary = config.get('vocabulary') or config['joint']['vocabulary']
    bias = build(TERMS.split(','), vocabulary, lam=2)
    for name, a in [('bias.table', bias.table), ('bias.toks', bias.toks), ('bias.col', bias.col), ('bias.depth', bias.depth)]:
        records.append((name, 5, a.shape[0], math.prod(a.shape[1:]) or 1, a.astype('<i4').tobytes()))
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / 'phonon-tensors.bin').open('wb') as f:
        f.write(b'STTAB001' + struct.pack('<I', len(records)))
        for name, kind, rows, cols, data in records:
            n = name.encode()
            f.write(struct.pack('<I', len(n)) + n + struct.pack('<IIIQ', kind, rows, cols, len(data)))
            f.write(bytes((-f.tell()) % 16))
            f.write(data)
    with (OUT / 'vocabulary.bin').open('wb') as f:
        f.write(struct.pack('<I', len(vocabulary)))
        for word in vocabulary:
            b = word.encode(); f.write(struct.pack('<I', len(b)) + b)
    p = OUT / 'phonon-tensors.bin'
    (LAB / 'tensor-provenance.json').write_text(json.dumps({
        'sourceContainerSha256': expected, 'preparedBytes': p.stat().st_size,
        'preparedSha256': hashlib.sha256(p.read_bytes()).hexdigest(),
        'conversion': 'Five-value blobs retained verbatim; original int6 decoder codes unpacked to int8 without requantization; vectors dequantized as the official CPU loader. Original weights unchanged.',
        'terms': TERMS.split(','), 'biasStrength': 2.0,
    }, indent=2) + '\n')
    print(json.dumps({'preparedRecords': len(records), 'bytes': p.stat().st_size}), flush=True)


def audio():
    import numpy as np
    import sherpa_onnx
    from scipy.signal import resample_poly
    source = ROOT / '.local/moonshine-tests/audio'
    records = json.loads((source / 'index.json').read_text())
    target = OUT / 'audio'; target.mkdir(parents=True, exist_ok=True)
    for row in records:
        (target / row['file']).write_bytes((source / row['file']).read_bytes())
        row.update(category='s1' if row['id'].startswith('s1-') else 'existing-regression', speaker=9)
    model = ROOT / '.local/model-assets/kokoro'
    tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(model=str(model / 'model.onnx'),
            voices=str(model / 'voices.bin'), tokens=str(model / 'tokens.txt'), data_dir=str(model / 'espeak-ng-data')),
        num_threads=2, provider='cpu'), max_num_sentences=1, silence_scale=.2))
    cases = [
        ('rx-08', 'Optical receive reading was minus eight point two d B M.', -8.2),
        ('rx-18', 'Optical receive reading was minus eighteen point two d B M.', -18.2),
        ('rx-28', 'Optical receive reading was minus twenty eight point two d B M.', -28.2),
        ('rx-178', 'The optical receive measurement was minus seventeen point eight d B M.', -17.8),
        ('rx-191', 'The optical receive reading was minus nineteen point one d B M.', -19.1),
        ('rx-005', 'Optical receive reading was minus zero point five d B M.', -.5),
        ('rx-3005', 'The optical receive reading was minus thirty point zero five d B M.', -30.05),
        ('rx-not-measured', 'I have not measured the optical receive power.', None),
        ('loss-db', 'The splice loss was zero point two d B.', None),
    ]
    for sid in [9, 0]:
        for name, text, reading in cases:
            speech = tts.generate(text, sid=sid, speed=1.05)
            factor = math.gcd(speech.sample_rate, 16000)
            a = resample_poly(np.asarray(speech.samples, dtype=np.float32), 16000 // factor, speech.sample_rate // factor)
            end = 9600 + len(a)
            a = np.pad(a, (9600, 16000))
            ident = f'{name}-v{sid}'; filename = ident + '.pcm'
            (target / filename).write_bytes(np.asarray(np.clip(a, -1, 1) * 32767, dtype='<i2').tobytes())
            records.append({'id': ident, 'text': text, 'file': filename, 'category': 'optical', 'speaker': sid,
                            'speechEndSamples': end, 'expected': {'optical_rx_dbm': reading},
                            'syntheticNoise': False, 'narrative': False})
    for sid in [9, 0]:
        for name, text in [
            ('field-terms', 'I checked the O N T, C B T and C S P. The P O N light is green and the L O S light is off. The F T T P service test passed.'),
            ('asset-spelled', 'The asset reference is C B T dash S Y N dash one zero.'),
        ]:
            speech = tts.generate(text, sid=sid, speed=1.05)
            factor = math.gcd(speech.sample_rate, 16000)
            a = resample_poly(np.asarray(speech.samples, dtype=np.float32), 16000 // factor, speech.sample_rate // factor)
            end = 9600 + len(a); a = np.pad(a, (9600, 16000)); ident = f'{name}-v{sid}'
            filename = ident + '.pcm'
            (target / filename).write_bytes(np.asarray(np.clip(a, -1, 1) * 32767, dtype='<i2').tobytes())
            expected = {'serving_asset': 'CBT-SYN-10'} if name == 'asset-spelled' else {'operational_test': 'passed'}
            records.append({'id': ident, 'text': text, 'file': filename, 'category': 'terms', 'speaker': sid,
                            'speechEndSamples': end, 'expected': expected, 'syntheticNoise': False, 'narrative': False})
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'cases.json').write_text(json.dumps({'synthetic': True, 'scope': 'Synthetic regression corpus, not real-engineer accuracy.', 'records': records}, indent=2) + '\n')
    (OUT / 'cases.tsv').write_text(''.join(f'{r["id"]}\t{r["file"]}\t{r["speechEndSamples"]}\n' for r in records))
    print(json.dumps({'syntheticCases': len(records)}), flush=True)


if __name__ == '__main__':
    import sys
    if '--audio-only' not in sys.argv: tensors()
    if '--tensors-only' not in sys.argv: audio()
