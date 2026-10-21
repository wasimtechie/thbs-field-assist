#!/usr/bin/env python3
"""Fetch the pinned, MIT-licensed catalogue for both apps; never edits image pixels."""
from pathlib import Path
import urllib.request,hashlib,json,concurrent.futures
ROOT=Path(__file__).resolve().parents[1]
SHA='a2ab6d008876133ac16a5484bf29aef22d42e4a0'
STYLES=[('vibrent','Vibrant',27),('3d','3D',5),('bluey','Blue portraits',10),('memo','Soft 3D',35),('notion','Line art',15),('teams','Team portraits',9),('toon','Cartoon',10),('upstream','Sketches',22)]
web=ROOT/'apps/admin/public/avatars';mobile=ROOT/'apps/mobile/assets/avatars'
web.mkdir(parents=True,exist_ok=True);mobile.mkdir(parents=True,exist_ok=True)
names=[f'{key}_{i}.png' for key,_,n in STYLES for i in range(1,n+1)]
def fetch(name):
 file=web/name
 data=file.read_bytes() if file.exists() else urllib.request.urlopen(f'https://raw.githubusercontent.com/alohe/avatars/{SHA}/png/{name}',timeout=30).read()
 assert data.startswith(b'\x89PNG')
 file.write_bytes(data);(mobile/name).write_bytes(data)
 return dict(name=name,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:rows=list(pool.map(fetch,names))
license=urllib.request.urlopen(f'https://raw.githubusercontent.com/alohe/avatars/{SHA}/LICENCE',timeout=30).read()
for folder in (web,mobile):(folder/'LICENSE.txt').write_bytes(license)
(ROOT/'docs/evidence/avatar-assets.json').write_text(json.dumps(dict(source='https://github.com/alohe/avatars',commit=SHA,license='MIT',count=len(rows),styles=[dict(id=k,label=l,count=n) for k,l,n in STYLES],assets=rows),indent=2)+'\n')
print(f'Bundled {len(rows)} pinned avatars across {len(STYLES)} styles; {sum(r["bytes"] for r in rows):,} bytes per app, including unchanged existing choices.')
