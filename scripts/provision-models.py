#!/usr/bin/env python3
"""Acquire pinned public model assets. Does not certify physical-device support."""
import hashlib,json,pathlib,urllib.request,tarfile,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
STORE=ROOT/'.local/model-assets'; STORE.mkdir(parents=True,exist_ok=True)
PIN='93e88ede867e4311c39151285e74df513e4b835b'
KOKORO_URL='https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-en-v0_19.tar.bz2'
KOKORO_HASH='c9f0dd393615805b0bab050c340834d5e684e732aec91c0e860cd30e982c08bd'
locks=[]
def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 return h.hexdigest()
def download(url,destination,expected):
 destination.parent.mkdir(parents=True,exist_ok=True)
 if destination.exists() and digest(destination)==expected:return
 temp=destination.with_suffix(destination.suffix+'.part')
 print('Downloading',destination.name,flush=True)
 with urllib.request.urlopen(url,timeout=120) as response,temp.open('wb') as out:shutil.copyfileobj(response,out)
 if digest(temp)!=expected:raise RuntimeError('Integrity mismatch: '+destination.name)
 temp.replace(destination)
def hf(repo,revision,files):
 info=json.load(urllib.request.urlopen(f'https://huggingface.co/api/models/Cactus-Compute/{repo}/revision/{revision}?blobs=true'))
 for source,target in files:
  item=next(i for i in info['siblings'] if i['rfilename']==source)
  expected=item.get('lfs',{}).get('sha256')
  url=f'https://huggingface.co/Cactus-Compute/{repo}/resolve/{info["sha"]}/{source}'
  if not expected:
   data=urllib.request.urlopen(url).read();expected=hashlib.sha256(data).hexdigest();target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
  else:download(url,target,expected)
  locks.append(dict(source=url,sha256=expected,bytes=target.stat().st_size,localPath=str(target.relative_to(ROOT))))
hf('needle3',PIN,[('needle3.cact',STORE/'needle3.cact')]+[(f'{platform}/{file}',ROOT/f'packages/field_voice/native/{platform}/{file}') for platform in ['ios-arm64','ios-sim-arm64','android-arm64','macos-arm64'] for file in ['libneedle.a','needle.h']]+[('LICENSE',ROOT/'docs/licenses/needle-LICENSE')])
whistle=json.load(urllib.request.urlopen('https://huggingface.co/api/models/Cactus-Compute/whistle'))
hf('whistle',whistle['sha'],[('whistle.cact',STORE/'whistle.cact'),('LICENSE',ROOT/'docs/licenses/whistle-LICENSE')])
archive=ROOT/'.local/kokoro.tar.bz2';download(KOKORO_URL,archive,KOKORO_HASH)
kokoro=STORE/'kokoro'
if not kokoro.exists():
 temp=STORE/'kokoro.part';temp.mkdir(exist_ok=True)
 with tarfile.open(archive) as tar:
  for item in tar.getmembers():
   parts=pathlib.PurePosixPath(item.name).parts[1:]
   if not parts:continue
   if item.issym() or item.islnk() or '..' in parts:raise RuntimeError('Unsupported archive member')
   destination=temp.joinpath(*parts)
   if item.isdir():destination.mkdir(parents=True,exist_ok=True)
   elif item.isfile():
    destination.parent.mkdir(parents=True,exist_ok=True)
    with tar.extractfile(item) as src,destination.open('wb') as out:shutil.copyfileobj(src,out)
 temp.replace(kokoro)
model=next(kokoro.glob('*.onnx'))
if model.name!='model.onnx':shutil.copyfile(model,kokoro/'model.onnx');model.unlink()
if (kokoro/'LICENSE').exists():shutil.copyfile(kokoro/'LICENSE',ROOT/'docs/licenses/kokoro-LICENSE')
assets=[]
for file in sorted(STORE.rglob('*')):
 if not file.is_file():continue
 # Historical benchmarks may leave other models in the same developer cache.
 # Stage only the base package here; streaming STT is added by its own script.
 rel=str(file.relative_to(STORE))
 if rel not in ['needle3.cact','whistle.cact'] and not rel.startswith('kokoro/'):continue
 rel=str(file.relative_to(STORE));sha=digest(file);purpose='needle3' if rel=='needle3.cact' else 'whistle' if rel=='whistle.cact' else 'kokoro' if rel.endswith('.onnx') else 'voices' if rel.endswith('voices.bin') else 'tokenizer' if rel.endswith('tokens.txt') else 'phonemizer'
 licence='GPL-3.0; see docs/licenses/espeak-ng-COPYING' if rel.startswith('kokoro/espeak-ng-data/') else 'Apache-2.0; see docs/licenses'
 assets.append(dict(id=sha,purpose=purpose,relativePath=rel,sha256=sha,bytes=file.stat().st_size,source=f'/api/v1/assets/{sha}',minimumAppVersion='0.1.0',runtimeVersion='needle3-pinned' if purpose in ['needle3','whistle'] else 'sherpa_onnx-1.13.8',licence=licence))
manifest=dict(manifestVersion=1,packageVersion='field-voice-2026-10-15',ready=False,assets=assets,requiredPurposes=['whistle','needle3','kokoro','voices','phonemizer','tokenizer'],platforms={'ios-arm64':{'verified':False,'runtime':f'needle3:{PIN}; sherpa_onnx:1.13.8'},'android-arm64-v8a':{'verified':False,'runtime':f'needle3:{PIN}; sherpa_onnx:1.13.8'}})
(ROOT/'fixtures/voice/asset-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'fixtures/voice/model-sources.lock.json').write_text(json.dumps(dict(needleRevision=PIN,whistleRevision=whistle['sha'],kokoroArchive=dict(source=KOKORO_URL,sha256=KOKORO_HASH),artifacts=locks),indent=2)+'\n')
print(f'Acquired {len(assets)} assets; {sum(a["bytes"] for a in assets):,} bytes. Device verification is still pending.')
