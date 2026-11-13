#!/usr/bin/env python3
"""Private demo TTS for approved generic questions only. No raw speech endpoint.

Default loopback. For phone rehearsal use --host 0.0.0.0 on a trusted LAN.
VOICE_DEMO_TOKEN is required. Cache keys include model revision, settings, voice
and exact question text. A cache hit is always labelled separately from live TTS.
"""
import argparse
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import threading
import time

ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT/'.local/voice-lab'
os.environ.setdefault('HF_HOME',str(LAB/'huggingface'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--model', choices=['vibevoice', 'ming'], default='vibevoice')
    parser.add_argument('--ddpm-steps', type=int, default=5)
    parser.add_argument('--cfg-scale', type=float, default=1.5)
    parser.add_argument('--prepare-pack', action='store_true')
    args = parser.parse_args()
    token = os.environ.get('VOICE_DEMO_TOKEN', '')
    if not token and not args.prepare_pack:
        raise SystemExit('Set a private VOICE_DEMO_TOKEN before starting the LAN voice demo.')
    import mlx.core as mx
    import numpy as np
    import soundfile as sf
    from mlx_audio.tts.utils import load_model
    source = json.loads((LAB/f'{args.model}-source.json').read_text())
    prompts = json.loads((LAB/'question-prompts.json').read_text())['prompts']
    allowed = {hashlib.sha256(p['text'].encode()).hexdigest():p for p in prompts}
    settings = dict(model=source['model'], revision=source['revision'], voice=source['voice'],
        ddpmSteps=args.ddpm_steps, cfgScale=args.cfg_scale)
    identity = hashlib.sha256(json.dumps(settings, sort_keys=True).encode()).hexdigest()[:16]
    cache = LAB/'question-cache'/identity
    cache.mkdir(parents=True, exist_ok=True)
    lock = threading.Lock()
    engine = load_model(source['localPath'])
    print(json.dumps({'ready':True, 'model':source['model'], 'questions':len(allowed), 'cacheId':identity}), flush=True)

    def render(key):
        destination = cache/f'{key}.wav'
        if destination.exists():
            return destination.read_bytes(), 'cache', 0
        started = time.perf_counter()
        mx.random.seed(42)
        max_tokens=min(350,max(90,len(allowed[key]['text'].split())*4+45))
        params = dict(text=allowed[key]['text'], voice=source['voice'], verbose=False, max_tokens=max_tokens)
        if args.model == 'vibevoice':
            params.update(stream=False, ddpm_steps=args.ddpm_steps, cfg_scale=args.cfg_scale)
        chunks, rate = [], 0
        for result in engine.generate(**params):
            mx.eval(result.audio)
            pcm = np.array(result.audio, dtype=np.float32).reshape(-1)
            if len(pcm):
                chunks.append(pcm); rate=result.sample_rate
        pcm=np.concatenate(chunks) if chunks else np.zeros(0,dtype=np.float32)
        if not len(pcm) or not np.isfinite(pcm).all() or len(pcm)/rate > min(46,max(15,len(allowed[key]['text'].split())*.8+5)) or args.model == 'vibevoice' and len(pcm)/rate >= max_tokens/7.5-.2:
            raise RuntimeError('Question generation failed validation.')
        output=io.BytesIO(); sf.write(output,pcm,rate,format='WAV',subtype='PCM_16')
        data=output.getvalue()
        temporary=destination.with_suffix('.part'); temporary.write_bytes(data); temporary.replace(destination)
        elapsed=round((time.perf_counter()-started)*1000,1)
        (cache/f'{key}.json').write_text(json.dumps({'prompt':allowed[key], **settings, 'generationMs':elapsed,
            'audioSeconds':len(pcm)/rate, 'sha256':hashlib.sha256(data).hexdigest()},indent=2)+'\n')
        return data, 'generated', elapsed

    if args.prepare_pack:
        pack=ROOT/'apps/mobile/assets/voice_questions'; pack.mkdir(parents=True,exist_ok=True)
        index={'model':source['model'], 'revision':source['revision'], 'voice':source['voice'],
            'settings':{**settings,'stream':False,'seed':42},
            'runtimeCommit':'7cc680b2bea1e8ef34b1a78ee4ff389953aebe40',
            'disclosure':'Pre-generated model speech. Recognition and question selection run on the phone.', 'prompts':{}}
        for key,p in allowed.items():
            data,origin,elapsed=render(key)
            name=f'{key}.wav'; (pack/name).write_bytes(data)
            index['prompts'][key]={'file':name,'sha256':hashlib.sha256(data).hexdigest(),'fieldId':p['fieldId'],'text':p['text']}
            (pack/'index.json').write_text(json.dumps(index,indent=2)+'\n')
            print(json.dumps({'fieldId':p['fieldId'],'source':origin,'generationMs':elapsed}),flush=True)
        return

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_): pass  # Never log bearer headers or request bodies.
        def do_GET(self):
            if self.path != '/health': return self.send_error(404)
            data=json.dumps({'ready':True,'model':source['model'],'voice':source['voice'],'genericQuestionsOnly':True}).encode()
            self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        def do_POST(self):
            if self.path != '/speech': return self.send_error(404)
            if not hmac.compare_digest(self.headers.get('Authorization',''),f'Bearer {token}'):
                return self.send_error(401)
            if self.headers.get('Origin'): return self.send_error(403)
            try: length=int(self.headers.get('Content-Length','0'))
            except ValueError: return self.send_error(400)
            if not 0 < length <= 256: return self.send_error(400)
            try:
                body=json.loads(self.rfile.read(length))
                if set(body) != {'promptSha256'} or body['promptSha256'] not in allowed: return self.send_error(422)
                key=body['promptSha256']
                if not lock.acquire(blocking=False): return self.send_error(503)
                try: data,origin,elapsed=render(key)
                finally: lock.release()
                self.send_response(200)
                for name,value in {'Content-Type':'audio/wav','Content-Length':str(len(data)),
                    'X-Prompt-SHA256':key,'X-Audio-SHA256':hashlib.sha256(data).hexdigest(),
                    'X-Voice-Model':source['model'],'X-Voice-Source':origin,'X-Generation-Ms':str(elapsed),
                    'Cache-Control':'no-store'}.items(): self.send_header(name,value)
                self.end_headers(); self.wfile.write(data)
            except (ValueError,TypeError,KeyError): self.send_error(400)
            except (BrokenPipeError,ConnectionResetError): pass
            except Exception: self.send_error(503)
    server=ThreadingHTTPServer((args.host,args.port),Handler)
    server.serve_forever()


if __name__ == '__main__': main()
