#!/usr/bin/env python3
"""Check the private synthetic-question service, never an engineer recording."""
import hashlib
import io
import json
from pathlib import Path
import time
import urllib.error
import urllib.request
import wave

ROOT=Path(__file__).resolve().parent.parent
TOKEN=json.loads((ROOT/'.local/voice-demo-secret.json').read_text())['token']
ORIGIN='http://127.0.0.1:8765'


def request(body, *, authorized=True, origin=None):
    headers={'Content-Type':'application/json'}
    if authorized: headers['Authorization']='Bearer '+TOKEN
    if origin: headers['Origin']=origin
    req=urllib.request.Request(ORIGIN+'/speech',json.dumps(body).encode(),headers)
    try:
        response=urllib.request.urlopen(req,timeout=30)
        return response.status,response.headers,response.read()
    except urllib.error.HTTPError as e: return e.code,e.headers,e.read()


def main():
    health=json.load(urllib.request.urlopen(ORIGIN+'/health',timeout=5))
    assert health['ready'] and health['genericQuestionsOnly']
    index=json.loads((ROOT/'apps/mobile/assets/voice_questions/index.json').read_text())
    key,entry=next(iter(index['prompts'].items()))
    assert request({'promptSha256':key},authorized=False)[0]==401
    assert request({'text':'Arbitrary text is not a supported input.'})[0]==422
    assert request({'promptSha256':'0'*64})[0]==422
    assert request({'promptSha256':key},origin='https://unrelated.example')[0]==403
    started=time.perf_counter();status,headers,data=request({'promptSha256':key});elapsed=(time.perf_counter()-started)*1000
    assert status==200 and headers['X-Prompt-SHA256']==key
    assert hashlib.sha256(data).hexdigest()==headers['X-Audio-SHA256']==entry['sha256']
    assert headers['X-Voice-Source']=='cache'
    with wave.open(io.BytesIO(data)) as audio:
        assert audio.getnchannels()==1 and audio.getsampwidth()==2 and audio.getnframes()>0
    again=request({'promptSha256':key})
    assert again[0]==200 and again[2]==data
    result={'passed':True,'scope':'Authenticated, allowlisted generic-question service; cached bytes match the phone pack. Not end-to-end live model latency.',
        'model':health['model'],'cachedRequestMs':round(elapsed,2),'questions':len(index['prompts'])}
    (ROOT/'.local/voice-lab/service-check.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__': main()
