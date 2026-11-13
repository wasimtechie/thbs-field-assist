#!/usr/bin/env python3
"""Local, synthetic TTS measurements. Never downloads or uploads engineer audio.

Run each model in a fresh process. RTF = generation seconds / audio seconds;
firstChunkMs measures PCM availability, not speaker/network/end-to-end latency.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
MODELS = {
    'vibevoice': ('mlx-community/VibeVoice-Realtime-0.5B-4bit', 'en-Emma_woman'),
    'ming': ('mlx-community/Ming-3.0-tts-0.5B-bf16', 'UK_Charlotte'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('model', choices=[*MODELS, 'kokoro'])
    parser.add_argument('--rounds', type=int, default=2)
    parser.add_argument('--limit', type=int, default=5)
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--ddpm-steps', type=int, default=5)
    parser.add_argument('--cfg-scale', type=float, default=1.5)
    parser.add_argument('--tag', default='')
    parser.add_argument('--no-stream', action='store_true')
    args = parser.parse_args()
    target = ROOT / '.local/voice-lab'
    target.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault('HF_HOME', str(target / 'huggingface'))
    import numpy as np
    import soundfile as sf
    prompts = json.loads((ROOT / 'fixtures/voice/demo-prompts.json').read_text())[:args.limit]
    revision, voice, model_path, mx = None, '0', ROOT / '.local/model-assets/kokoro', None
    if args.model != 'kokoro':
        from huggingface_hub import HfApi, snapshot_download
        model_id, voice = MODELS[args.model]
        pin = target / f'{args.model}-source.json'
        revision = json.loads(pin.read_text())['revision'] if pin.exists() else HfApi().model_info(model_id).sha
        print(f'Downloading pinned {model_id}@{revision}', flush=True)
        model_path = Path(snapshot_download(model_id, revision=revision))
        metadata = {'model':model_id, 'revision':revision, 'localPath':str(model_path), 'voice':voice}
        (target / f'{args.model}-source.json').write_text(json.dumps(metadata, indent=2)+'\n')
        if args.prepare_only:
            return
        import mlx.core as mx
        from mlx_audio.tts.utils import load_model
        started = time.perf_counter()
        engine = load_model(str(model_path))
        mx.synchronize()
        load_ms = (time.perf_counter()-started)*1000
    else:
        import sherpa_onnx
        model_id = 'kokoro-int8-en-v0_19'
        started = time.perf_counter()
        engine = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                    model=str(model_path/'model.onnx'), voices=str(model_path/'voices.bin'),
                    tokens=str(model_path/'tokens.txt'), data_dir=str(model_path/'espeak-ng-data')),
                num_threads=2, provider='cpu'), max_num_sentences=1))
        load_ms = (time.perf_counter()-started)*1000
    output = target / 'results' / (args.tag or args.model)
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for round_id in range(args.rounds):
        for prompt in prompts:
            started = time.perf_counter()
            chunks, first_ms, rate = [], None, 0
            if mx is not None:
                mx.random.seed(42 + round_id)
                params = dict(text=prompt['text'], voice=voice, verbose=False)
                if args.model == 'vibevoice':
                    params.update(stream=not args.no_stream, streaming_interval=.24, ddpm_steps=args.ddpm_steps, cfg_scale=args.cfg_scale, max_tokens=300)
                else:
                    params.update(max_tokens=450)
                for result in engine.generate(**params):
                    mx.eval(result.audio)
                    pcm = np.array(result.audio, dtype=np.float32).reshape(-1)
                    if not len(pcm):
                        continue
                    if first_ms is None:
                        first_ms = (time.perf_counter()-started)*1000
                    chunks.append(pcm)
                    rate = result.sample_rate
            else:
                result = engine.generate(prompt['text'], sid=0, speed=1)
                chunks = [np.array(result.samples, dtype=np.float32)]
                rate = result.sample_rate
                first_ms = (time.perf_counter()-started)*1000
            elapsed = time.perf_counter()-started
            pcm = np.concatenate(chunks) if chunks else np.zeros(0, dtype=np.float32)
            if not len(pcm) or not np.isfinite(pcm).all() or not rate:
                raise RuntimeError('Synthesis returned invalid or empty PCM.')
            duration = len(pcm)/rate
            name = f'{prompt["id"]}-{round_id+1}.wav'
            sf.write(output/name, pcm, rate, subtype='PCM_16')
            row = dict(promptId=prompt['id'], text=prompt['text'], round=round_id+1,
                firstChunkMs=round(first_ms,1), generationMs=round(elapsed*1000,1), audioSeconds=round(duration,3),
                realTimeFactor=round(elapsed/duration,3), sampleRate=rate,
                peakRssMB=round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/1024/1024,1),
                peakMlxMB=round(mx.get_peak_memory()/1024/1024,1) if mx else None,
                audioFile=name, audioSha256=hashlib.sha256((output/name).read_bytes()).hexdigest())
            records.append(row)
            print(json.dumps(row), flush=True)
            (output/'metrics.json').write_text(json.dumps(dict(model=model_id, revision=revision, voice=voice,
                machine=platform.platform(),
                chip=subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),
                memoryGB=int(subprocess.check_output(['sysctl','-n','hw.memsize'],text=True))/1024**3,
                loadMs=round(load_ms,1),
                settings={'ddpmSteps':args.ddpm_steps,'cfgScale':args.cfg_scale,'stream':not args.no_stream} if args.model == 'vibevoice' else {},
                runtimeCommit=subprocess.check_output(['git','-C',str(target/'mlx-audio'),'rev-parse','HEAD'],text=True).strip(),
                firstChunkDefinition='Time to PCM from generate(); excludes model load, network and speaker playback. Kokoro/Ming yield complete utterances.',
                records=records), indent=2)+'\n')


if __name__ == '__main__':
    main()
