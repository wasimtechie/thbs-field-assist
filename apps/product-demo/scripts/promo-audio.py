#!/usr/bin/env python3
"""Generate an original local score and synthetic voices; no microphone/network."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import wave

import numpy as np
from scipy.signal import resample_poly
from scipy.ndimage import uniform_filter1d
import sherpa_onnx

PROJECT = Path(__file__).resolve().parents[1]
ROOT = PROJECT.parents[1]
RATE = 48000
FPS = 30
SPEAKERS = {'bf_emma': 7, 'bm_george': 9, 'am_michael': 6}


def read_wav(path):
    with wave.open(str(path)) as wav:
        data = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').astype(np.float64) / 32768
        return data, wav.getframerate()


def write_wav(path, data, rate):
    data = np.asarray(data)
    channels = 1 if data.ndim == 1 else data.shape[1]
    with wave.open(str(path), 'wb') as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(2)
        wav.setframerate(rate)
        wav.writeframes((np.clip(data, -.999, .999) * 32767).astype('<i2').tobytes())


def display_chunks(text):
    words = text.split()
    chunks, part = [], []
    for word in words:
        part.append(word)
        if len(part) >= 7 or (len(part) >= 4 and word.endswith(('.', '?', '!'))):
            chunks.append(' '.join(part)); part = []
    if part:
        if chunks and len(part) <= 2: chunks[-1] += ' ' + ' '.join(part)
        else: chunks.append(' '.join(part))
    return chunks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', type=Path, default=ROOT / '.local/model-assets/kokoro')
    args = parser.parse_args()
    out = PROJECT / 'public/voice-promo'
    out.mkdir(parents=True, exist_ok=True)
    cache = PROJECT / 'out/voice-promo/audio-parts'
    cache.mkdir(parents=True, exist_ok=True)
    story = json.loads((PROJECT / 'src/voice-promo/story.json').read_text())
    tts = None
    scenes, captions, track, masks = [], [], [], []
    at = 0
    for scene in story:
        parts, line_meta = [], []
        cursor = .35
        for index, line in enumerate(scene['lines']):
            key = hashlib.sha256(json.dumps([line['text'], line['voice'], 1.04, 'kokoro-v019'], ensure_ascii=False).encode()).hexdigest()
            file = cache / f'{key}.wav'
            if not file.exists():
                if tts is None:
                    tts = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
                        model=sherpa_onnx.OfflineTtsModelConfig(
                            kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                                model=str(args.models / 'model.onnx'), voices=str(args.models / 'voices.bin'),
                                tokens=str(args.models / 'tokens.txt'), data_dir=str(args.models / 'espeak-ng-data')),
                            num_threads=2, provider='cpu', debug=False)))
                audio = tts.generate(line['text'], sid=SPEAKERS[line['voice']], speed=1.04)
                data = np.asarray(audio.samples, dtype=np.float64)
                active = np.flatnonzero(np.abs(data) > .0018)
                if len(active):
                    pad = int(audio.sample_rate * .12)
                    data = data[max(0, active[0]-pad):min(len(data), active[-1]+pad)]
                rms = math.sqrt(float(np.mean(data * data)) + 1e-12)
                data *= min(.12/rms, .88/max(float(np.max(np.abs(data))), .001))
                write_wav(file, data, audio.sample_rate)
            data, rate = read_wav(file)
            data = resample_poly(data, RATE, rate)
            seconds = len(data) / RATE
            parts.append((cursor, data))
            line_meta.append({**line, 'start': round(cursor, 4), 'seconds': round(seconds, 4), 'file': file.name})
            chunks = display_chunks(line.get('display', line['text']))
            total = sum(len(c.split()) for c in chunks)
            elapsed = 0
            for chunk in chunks:
                share = seconds * len(chunk.split()) / total
                captions.append({'from': round((at + cursor + elapsed)*FPS),
                                 'to': round((at + cursor + elapsed + share + .12)*FPS),
                                 'text': chunk, 'role': line.get('role', ''), 'scene': scene['id']})
                elapsed += share
            cursor += seconds + line.get('gapAfter', .35)
        duration = math.ceil(max(scene['minSeconds'], cursor + .65) / 2) * 2
        mono = np.zeros(int(duration * RATE))
        for start, data in parts:
            pos = round(start * RATE); mono[pos:pos+len(data)] += data
        meta = {'id': scene['id'], 'label': scene['label'], 'from': round(at*FPS),
                'durationInFrames': duration*FPS, 'seconds': duration, 'lines': line_meta}
        scenes.append(meta); track.append(mono)
        mask = np.zeros(len(mono))
        for start, data in parts:
            a, b = max(0, round((start-.12)*RATE)), min(len(mask),round((start+len(data)/RATE+.3)*RATE))
            mask[a:b] = 1
        masks.append(mask)
        print(f"Narration: {scene['id']} — {duration}s", flush=True)
        at += duration
    voice = np.concatenate(track)
    speech = np.concatenate(masks)
    n = len(voice)
    music = np.zeros((n, 2), dtype=np.float64)
    foley = np.zeros((n, 2), dtype=np.float64)
    events = []
    rng = np.random.default_rng(26026)

    def add(at_seconds, sound, gain=.02, pan=0, target=None):
        start = round(at_seconds*RATE)
        if start < 0 or start >= n: return
        sound = sound[:n-start]
        target = music if target is None else target
        target[start:start+len(sound), 0] += sound * gain * math.sqrt((1-pan)/2)
        target[start:start+len(sound), 1] += sound * gain * math.sqrt((1+pan)/2)

    def bell(note, seconds=.7):
        t = np.arange(round(seconds*RATE))/RATE
        hz = 440*2**((note-69)/12)
        env = (1-np.exp(-t*90))*np.exp(-t*5)
        return (np.sin(2*np.pi*hz*t)+.22*np.sin(2*np.pi*hz*2*t))*env

    def cue(kind, when, note=77, gain=.045):
        events.append({'seconds':round(when,4),'frame':round(when*FPS),'type':kind})
        if kind in ['next','portal','collage','title-sweep']:
            t=np.arange(round(.35*RATE))/RATE
            noise=rng.standard_normal(len(t))
            # A smooth, short airy sweep, not a sharp notification hiss.
            noise=uniform_filter1d(noise,size=7)
            add(when-.12,noise*np.sin(np.pi*t/.35)**2,.07,target=foley)
        add(when,bell(note,.45),gain,target=foley)
        if kind in ['reveal','review-ready','corrected','final']:
            add(when+.075,bell(note+7,.7),gain*.55,target=foley)

    # Original 120 BPM pulse, mallet melody and airy chord bed. No stock music.
    notes = [65, 72, 68, 75, 65, 70, 68, 72]
    for beat in range(int(at*2)):
        when = beat*.5
        scene = next(s for s in scenes if s['from']/FPS <= when < (s['from']+s['durationInFrames'])/FPS)
        gain = .070 if scene['id'] not in ['capture','followup','repair'] else .034
        if beat % 2 == 0: add(when, bell(notes[(beat//2)%8]), gain, -.25 if beat%4 else .25)
        if beat % 4 == 0:
            t=np.arange(round(.18*RATE))/RATE
            add(when, np.sin(2*np.pi*(95-30*t/.18)*t)*np.exp(-t*28), gain*.6)
    for scene in scenes[1:]:
        at_s=scene['from']/FPS
        cue('next',at_s,72,.032)
        cue('reveal',at_s+.22,77,.033)
    for scene in scenes:
        at_s=scene['from']/FPS
        t=np.arange(round(scene['seconds']*RATE))/RATE
        envelope=np.minimum(t/.4,1)*np.minimum((scene['seconds']-t)/.65,1)
        chord=[53,60,65,68] if scene['id'] not in ['integration','adapt','close'] else [56,63,68,72]
        pad=sum(np.sin(2*np.pi*(440*2**((note-69)/12))*t+.12*i) for i,note in enumerate(chord))/2
        add(at_s,pad*envelope,.016 if scene['id'] in ['capture','followup','repair'] else .024,pan=.12)
    lookup={s['id']:s for s in scenes}
    for fraction,note in [(.25,72),(.65,75),(.80,77),(.91,79)]:
        s=lookup['capture'];cue('field-pop',s['from']/FPS+fraction*s['seconds'],note,.034)
    for line in lookup['followup']['lines']:
        cue('dialogue-pop',lookup['followup']['from']/FPS+line['start'],75,.023)
    cue('review-ready',lookup['followup']['from']/FPS+5+(32+7.5)/24,77,.042)
    cue('correction',lookup['repair']['from']/FPS+2.2,72,.024)
    cue('corrected',lookup['repair']['from']/FPS+115/FPS,77,.042)
    cue('portal',lookup['reveal']['from']/FPS+2.2,80,.028)
    for i in range(4):cue('integration-node',lookup['integration']['from']/FPS+.4+i*.6,72+i*2,.030)
    for when in [.35,.75,1.25]:cue('reel-pop',lookup['adapt']['from']/FPS+when,77,.020)
    cue('collage',lookup['adapt']['from']/FPS+2.1,80,.032)
    cue('reveal',lookup['adapt']['from']/FPS+5,77,.038)
    for frame in [18,41,80,110]:cue('title-sweep',lookup['close']['from']/FPS+frame/(FPS*1.25),77,.026)
    cue('final',lookup['close']['from']/FPS+5.2,77,.034)
    # Two deliberate near-silent breaths at metric / closing entrances.
    for scene in scenes:
        if scene['id'] in ['speed','close']:
            a=round(scene['from']/FPS*RATE);music[max(0,a-int(.24*RATE)):a+int(.12*RATE)]*=.015
    speech=uniform_filter1d(speech,size=round(.18*RATE))
    music *= (1-.72*speech[:,None])
    foley *= (1-.35*speech[:,None])
    balances=[]
    for scene in scenes:
        a=round(scene['from']/FPS*RATE);b=a+round(scene['seconds']*RATE)
        active=speech[a:b]>.8
        if not np.any(active):continue
        vrms=math.sqrt(float(np.mean((voice[a:b][active]*.86)**2))+1e-12)
        mrms=math.sqrt(float(np.mean(music[a:b][active]**2))+1e-12)
        target_db=22 if scene['id'] in ['capture','followup','repair'] else 17
        music[a:b]*=min(2.5,max(.4,vrms/(10**(target_db/20))/mrms))
        actual=20*math.log10(vrms/(math.sqrt(float(np.mean(music[a:b][active]**2)))+1e-12))
        balances.append({'scene':scene['id'],'voiceAboveMusicDb':round(actual,1)})
    fade = np.minimum(np.arange(n)/(.3*RATE), 1)*np.minimum(np.arange(n)[::-1]/(.8*RATE), 1)
    mixed = (np.repeat(voice[:,None],2,axis=1)*.86+music+foley)*fade[:,None]
    raw = out / 'mix-raw.wav'; write_wav(raw,mixed,RATE)
    ffmpeg = next((PROJECT/'node_modules').glob('@remotion/compositor*/ffmpeg'))
    media_env = {**os.environ, 'DYLD_LIBRARY_PATH': str(ffmpeg.parent)}
    loudness = subprocess.run([str(ffmpeg),'-hide_banner','-nostats','-i',str(raw),'-af',
        'loudnorm=I=-14:TP=-1:LRA=9:print_format=json','-f','null','-'],capture_output=True,text=True,check=True,env=media_env)
    details=json.JSONDecoder().raw_decode(loudness.stderr[loudness.stderr.rfind('{'):])[0]
    af=('loudnorm=I=-14:TP=-1:LRA=9:'
        f"measured_I={details['input_i']}:measured_TP={details['input_tp']}:"
        f"measured_LRA={details['input_lra']}:measured_thresh={details['input_thresh']}:"
        f"offset={details['target_offset']}:linear=true:print_format=json")
    final=out/'mix.wav'
    subprocess.run([str(ffmpeg),'-y','-v','error','-i',str(raw),'-af',af,'-ar',str(RATE),str(final)],check=True,env=media_env)
    raw.unlink()
    for i,cue in enumerate(captions[:-1]): cue['to']=min(cue['to'],captions[i+1]['from'])
    result={'fps':FPS,'width':1920,'height':1080,'durationInFrames':round(at*FPS),
            'durationSeconds':at,'scenes':scenes,'captions':captions,
            'audioSource':'Local synthetic Kokoro voices; original procedural score and foley',
            'musicRevision':2,'soundEvents':events,'musicBalance':balances,
            'normalization':'Two-pass loudnorm −14 LUFS / −1 dBTP', 'preNormalization':details}
    (PROJECT/'src/voice-promo/timing.json').write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n')
    def timestamp(frame):
        ms=round(frame/FPS*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02},{ms%1000:03}'
    srt='\n\n'.join(f"{i+1}\n{timestamp(c['from'])} --> {timestamp(c['to'])}\n"+
         (f"{c['role']}: " if c['role'] else '')+c['text'] for i,c in enumerate(captions))+'\n'
    (PROJECT/'voice-promo/Field-Assist-Voice-Promo.srt').write_text(srt)
    print(f'Audio ready: {at:.1f}s, {len(captions)} caption cues.',flush=True)


if __name__ == '__main__': main()
