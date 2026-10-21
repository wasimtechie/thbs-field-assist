#!/usr/bin/env python3
"""Start local dashboard AI with a hidden, process-only API key (never saved)."""
import getpass,json,os,sys,urllib.request,urllib.error
from pathlib import Path
root=Path(__file__).resolve().parents[1]
os.chdir(root)
key=os.environ.get('OPENAI_API_KEY') or getpass.getpass('OpenAI API key (hidden; process memory only): ')
if not key.strip():raise SystemExit('An API key is required.')
model=os.environ.get('OPENAI_MODEL','gpt-4.1-mini-2025-04-14')
result={'model':model,'keySavedToDisk':False,'scope':'Synthetic connection probe only'}
request=urllib.request.Request('https://api.openai.com/v1/responses',data=json.dumps({'model':model,'input':'Reply exactly READY. This is a synthetic local application connection check.','store':False,'max_output_tokens':32}).encode(),headers={'Authorization':'Bearer '+key.strip(),'Content-Type':'application/json'})
try:
 with urllib.request.urlopen(request,timeout=30) as response:
  data=json.load(response);result.update(status=response.status,completed=data.get('status')=='completed',usage=data.get('usage',{}))
 print('OpenAI connection verified with a synthetic request.',flush=True)
except urllib.error.HTTPError as e:
 body=json.load(e);code=body.get('error',{}).get('code')
 result.update(status=e.code,completed=False,code=code if code in ['insufficient_quota','invalid_api_key','model_not_found','rate_limit_exceeded'] else 'provider_rejected')
 print('OpenAI connection check returned HTTP '+str(e.code)+'; application will show a clear service error.',flush=True)
except Exception:
 result.update(status=None,completed=False,code='connection_failed');print('OpenAI connection check unavailable; no credentials printed.',flush=True)
(root/'docs/evidence/ai-connection.json').write_text(json.dumps(result,indent=2)+'\n')
env=os.environ.copy();env['OPENAI_API_KEY']=key.strip();env['OPENAI_MODEL']=model
os.execvpe('npm',['npm','run','dev'],env)
