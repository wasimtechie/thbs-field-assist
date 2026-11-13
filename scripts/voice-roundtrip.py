#!/usr/bin/env python3
"""Synthetic TTS -> the app's pinned Whistle ASR. This is NOT human-speech WER."""
import ctypes as C
import json
import math
from pathlib import Path
import re
import time

ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT/'.local/voice-lab'


def distance(a, b):
    row = list(range(len(b)+1))
    for i, x in enumerate(a, 1):
        nxt = [i]
        for j, y in enumerate(b, 1):
            nxt.append(min(nxt[-1]+1, row[j]+1, row[j-1]+(x != y)))
        row = nxt
    return row[-1]


def main():
    import numpy as np
    import soundfile as sf
    from scipy.signal import resample_poly
    lib = C.CDLL(str(LAB/'libfield_voice.dylib'))
    lib.fa_load.argtypes = [C.c_void_p, C.c_uint64]
    lib.fa_load.restype = C.c_int
    lib.fa_last_error.restype = C.c_char_p
    lib.fa_transcribe.argtypes = [C.c_void_p, C.c_int, C.c_char_p, C.c_void_p, C.c_int]
    buffers = []
    for file in ['needle3.cact', 'whistle.cact']:
        blob = (ROOT/'.local/model-assets'/file).read_bytes()
        buf = C.create_string_buffer(blob)
        buffers.append(buf)
        if lib.fa_load(buf, len(blob)) < 0:
            raise RuntimeError(lib.fa_last_error().decode())
    rows = []
    for metrics_file in sorted((LAB/'results').glob('*/metrics.json')):
        metrics = json.loads(metrics_file.read_text())
        for row in metrics['records']:
            if row['round'] != 1:
                continue
            samples, rate = sf.read(metrics_file.parent/row['audioFile'], dtype='float32')
            factor = math.gcd(rate, 16000)
            pcm = np.ascontiguousarray(resample_poly(samples, 16000//factor, rate//factor), dtype='float32')
            result = C.create_string_buffer(16384)
            started = time.perf_counter()
            code = lib.fa_transcribe(pcm.ctypes.data, len(pcm), b'en', result, len(result))
            elapsed = (time.perf_counter()-started)*1000
            if code < 0:
                raise RuntimeError(lib.fa_last_error().decode())
            text = json.loads(result.value.decode())['text']
            expected = re.findall(r"\w+", row['text'].lower())
            actual = re.findall(r"\w+", text.lower())
            item = dict(model=metrics['model'], promptId=row['promptId'], expected=row['text'], recognized=text,
                recognitionMs=round(elapsed,1), syntheticWordErrorRate=round(distance(expected, actual)/max(1,len(expected)),3))
            rows.append(item)
            print(json.dumps(item), flush=True)
            (LAB/'results/roundtrip.json').write_text(json.dumps({'scope':'Synthetic generated audio through the app model on this Mac. Not measured engineer speech, accent or noise performance.', 'records':rows},indent=2)+'\n')


if __name__ == '__main__':
    main()
