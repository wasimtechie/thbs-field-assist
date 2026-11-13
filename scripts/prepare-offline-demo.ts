import {readFileSync,writeFileSync,existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {randomUUID} from 'node:crypto';
async function main(){
const root=process.cwd(),config=JSON.parse(readFileSync('.local/mobile-demo-config.json','utf8'));
if(config.DEMO_AUTO_LOGIN!==true||!config.DEMO_ENGINEER_EMAIL?.endsWith('@fieldassist.demo'))throw Error('Explicit synthetic demo configuration required');
const base='http://127.0.0.1:3002/api/v1/';
async function req(route:string,body?:unknown,token?:string){const r=await fetch(base+route,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},...(body?{body:JSON.stringify(body)}:{})});if(!r.ok)throw Error(`${route}: ${r.status}`);return r.json();}
const login=await req('auth/login',{email:config.DEMO_ENGINEER_EMAIL,password:config.DEMO_ENGINEER_PASSWORD,audience:'mobile'});
const deviceFile='.local/offline-demo-fixture-device.txt';const deviceId=existsSync(deviceFile)?readFileSync(deviceFile,'utf8').trim():randomUUID();writeFileSync(deviceFile,deviceId+'\n');
const provision=await req('devices/provision',{deviceId,platform:'android',appVersion:'offline-demo-package',osVersion:'Synthetic bundled demo fixture',model:'Bundled offline demo fixture',nonExpiringDemo:true},login.token);
const claims=JSON.parse(Buffer.from(provision.entitlement.split('.')[1],'base64url').toString());
if(claims.offlineAccess!=='non-expiring-synthetic-demo'||claims.expiresAt!==null||Object.hasOwn(claims,'exp'))throw Error('The backend must explicitly authorise non-expiring synthetic demo access');
const operations=await req('mobile/operations',undefined,login.token);
const isSyntheticJob=(j:any)=>/^S[1-5] · /.test(j.title)&&(j.site.startsWith('Fictional demo property')||(
  j.id==='80000000-0000-4000-8015-000000000001'&&
  j.title==='S1 · 15-field voice test'&&
  j.site==='Fictional voice test property · Bristol, UK'&&
  j.instructions.startsWith('SYNTHETIC DEMO ONLY.')
));
if(!operations.workOrders.length||operations.workOrders.some((j:any)=>!isSyntheticJob(j)))throw Error('Only synthetic closure demo jobs may be bundled');
const manifest=provision.manifest.assets;
// No online session token or signing key is included. Retain the server's normal
// signed entitlement scoped to this synthetic fixture device and account.
const staged=path.join(root,'.local/offline-demo-provisioned-snapshot.json');
writeFileSync(staged,JSON.stringify({formatVersion:2,synthetic:true,deviceId,user:provision.user,template:provision.template,entitlement:provision.entitlement,serverTime:provision.serverTime,operations,manifest},null,2)+'\n',{mode:0o600});
execFileSync('python3',[path.join(root,'scripts/repack-offline-voice.py'),staged],{stdio:'inherit'});
console.log(JSON.stringify({synthetic:true,jobs:operations.workOrders.length,entitlementExpires:JSON.parse(Buffer.from(provision.entitlement.split('.')[1],'base64url').toString()).expiresAt}));

}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
