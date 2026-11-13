#!/usr/bin/env python3
"""Create synthetic speech/noise fixtures. No microphone or network is used."""
import json
import math
from pathlib import Path


def main():
    import numpy as np
    import sherpa_onnx
    from scipy.signal import resample_poly
    root = Path(__file__).resolve().parent.parent
    target = root / '.local/moonshine-tests/audio'
    target.mkdir(parents=True, exist_ok=True)
    model = root / '.local/model-assets/kokoro'
    engine = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
        model=sherpa_onnx.OfflineTtsModelConfig(
            kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                model=str(model / 'model.onnx'), voices=str(model / 'voices.bin'),
                tokens=str(model / 'tokens.txt'), data_dir=str(model / 'espeak-ng-data')),
            num_threads=2, provider='cpu'), max_num_sentences=1, silence_scale=.2))
    summary = ('I installed the O N T in the living room. I used the existing duct for the fibre route. '
               'The optical receive reading was minus eighteen point two d B M. '
               'The service test passed. The job is fully completed. I showed the customer the equipment.')
    cases = [
        ('s1-summary', summary, {'claimed_outcome': 'completed', 'optical_rx_dbm': -18.2, 'operational_test': 'passed'}, False),
        ('s1-summary-noisy', summary, {'claimed_outcome': 'completed', 'optical_rx_dbm': -18.2, 'operational_test': 'passed'}, True),
        ('s1-sentence-pauses', [
            'I installed the O N T in the living room.',
            'I used the existing duct for the fibre route.',
            'The optical receive reading was minus eighteen point two d B M.',
            'The service test passed.',
            'The job is fully completed.',
            'I showed the customer the equipment.',
        ], {'claimed_outcome': 'completed', 'optical_rx_dbm': -18.2, 'operational_test': 'passed'}, False),
        ('additional-delayed', 'The service test passed. The job is fully completed. No further work required.',
         {'claimed_outcome': 'completed', 'operational_test': 'passed', 'next_action': 'present'}, False),
        ('reading-fragment', 'The reading was minus eighteen point two d B M. The service test passed. The job is fully completed.',
         {'claimed_outcome': 'completed', 'optical_rx_dbm': -18.2, 'operational_test': 'passed'}, False),
        ('paraphrased', 'I finished all the work. Connectivity checks were successful. We need a return visit tomorrow.',
         {'claimed_outcome': 'completed', 'operational_test': 'passed', 'next_action': 'present'}, False),
        ('negative', 'I have not completed the job. The service test did not pass.',
         {'claimed_outcome': None, 'operational_test': None}, True),
        ('asset', 'C B T dash S Y N dash one zero.', {'serving_asset': 'CBT-SYN-10'}, False),
        ('noise-only', '', {}, True),
    ]
    records = []
    for name, text, expected, noisy in cases:
        if text:
            parts = text if isinstance(text, list) else [text]
            clips = []
            for part in parts:
                speech = engine.generate(part, sid=9, speed=1.05)
                factor = math.gcd(speech.sample_rate, 16000)
                clip = resample_poly(np.asarray(speech.samples, dtype=np.float32),
                                     16000 // factor, speech.sample_rate // factor)
                if clips:
                    clips.append(np.zeros(19200, dtype=np.float32))
                clips.append(clip)
            audio = np.concatenate(clips)
            leading = 72000 if name == 'additional-delayed' else 9600
            samples = np.pad(audio, (leading, 48000))
            speech_end = leading + len(audio)
        else:
            samples = np.zeros(16000 * 9, dtype=np.float32)
            speech_end = 0
        if noisy:
            rng = np.random.default_rng(42)
            t = np.arange(len(samples), dtype=np.float32) / 16000
            samples = samples + .007 * np.sin(2 * np.pi * 100 * t) + rng.uniform(-.006, .006, len(samples))
        pcm = np.asarray(np.clip(samples, -1, 1) * 32767, dtype='<i2')
        (target / f'{name}.pcm').write_bytes(pcm.tobytes())
        records.append({'id': name, 'text': ' '.join(text) if isinstance(text, list) else text, 'file': f'{name}.pcm',
                        'speechEndSamples': speech_end, 'expected': expected,
                        'narrative': name != 'asset', 'syntheticNoise': noisy,
                        'sentencePauseSeconds': 1.2 if isinstance(text, list) else None,
                        'initialSilenceSeconds': 4.5 if name == 'additional-delayed' else .6})
        print(json.dumps({'fixture': name, 'seconds': round(len(pcm) / 16000, 2)}), flush=True)
    (target / 'index.json').write_text(json.dumps(records, indent=2) + '\n')


if __name__ == '__main__':
    main()
