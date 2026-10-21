import 'dotenv/config';
import {strict as assert} from 'node:assert';
import {randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync} from 'node:fs';
import {sha256} from '../packages/contracts/src';
const base=process.env.APP_ORIGIN??'http://localhost:3000';const evidence:string[]=[];
async function request(route:string,options:{method?:string;body?:unknown;raw?:string;token?:string;cookie?:string;headers?:Record<string,string>}={}){const response=await fetch(`${base}/api/v1/${route}`,{method:options.method??'GET',headers:{'Content-Type':'application/json','Origin':base,...(options.token?{Authorization:`Bearer ${options.token}`} :{}),...(options.cookie?{Cookie:options.cookie}:{}),...options.headers},body:options.raw??(options.body===undefined?undefined:JSON.stringify(options.body))});let data:any;try{data=await response.json();}catch{data=null;}return {status:response.status,data,cookie:response.headers.get('set-cookie')};}
function check(name:string,condition:unknown){assert.ok(condition,name);evidence.push(`PASS ${name}`);console.log(`PASS ${name}`);}
async function main(){
 check('PostgreSQL readiness',(await request('health')).status===200);
 const admin=await request('auth/login',{method:'POST',body:{email:'admin@fieldassist.demo',password:process.env.SEED_ADMIN_PASSWORD,audience:'web'}});check('Admin cookie session',admin.status===200&&admin.cookie?.includes('HttpOnly')&&!admin.data.token);const cookie=admin.cookie!.split(';')[0];
 const login=await request('auth/login',{method:'POST',body:{email:'fibre@fieldassist.demo',password:process.env.SEED_ENGINEER_PASSWORD,audience:'mobile'}});check('Engineer bearer session',login.status===200&&!!login.data.token&&!login.cookie);const token=login.data.token;
 check('Engineer cannot list admin templates',(await request('admin/templates',{token})).status===403);
 check('Anonymous admin request denied',(await request('admin/engineers')).status===401);
 check('Malformed resource identifier rejected',(await request('admin/templates/not-a-uuid/draft',{token})).status===400);
 const badOrigin=await fetch(`${base}/api/v1/admin/templates`,{method:'POST',headers:{Cookie:cookie,Origin:'https://untrusted.invalid','Content-Type':'application/json'},body:'{}'});check('CSRF origin rejected',badOrigin.status===403);
 const library=await request('admin/templates?limit=100',{cookie});check('Four published seeded templates',library.data.items.filter((t:any)=>t.id.startsWith('40000000-')).length===4);
 const deviceId=randomUUID();const provision=await request('devices/provision',{method:'POST',token,body:{deviceId,platform:'ios',appVersion:'api-test',osVersion:'API contract test; no physical OS',model:'Synthetic API verification device'}});check('Provisioned signed offline entitlement',provision.status===200&&provision.data.entitlement.split('.').length===3);const p=provision.data,t=p.template;
 check('Unassigned form unavailable',(await request('templates/40000000-0000-4000-8000-000000000002/versions/50000000-0000-4000-8000-000000000002',{token})).status===404);
 const make=(overrides:any={})=>({clientReportId:randomUUID(),submissionAttemptId:randomUUID(),revision:1,templateId:t.templateId,versionId:t.versionId,schemaHash:t.schemaHash,entitlementId:p.entitlementId,values:{installation_outcome:'partial',work_performed:'Synthetic API test: installed twelve metres; second visit needed.',cable_installed:{amount:12,unit:'m'},connectivity_test:'not_tested',exception_reason:'Synthetic test: follow-up connection required.'},confirmedAt:new Date().toISOString(),originatingTimezone:'Asia/Kolkata',...overrides});
 const send=async(payload:any)=>{const raw=JSON.stringify(payload);return request('submissions',{method:'POST',token,raw,headers:{'X-Payload-SHA256':sha256(raw)}});};
 const payload=make();const first=await send(payload);check('Actual report accepted',first.status===201&&!!first.data.receipt.id);const retry=await send(payload);check('Lost-response retry returns stable receipt',retry.status===200&&retry.data.receipt.id===first.data.receipt.id);
 check('Consumed attempt cannot change payload',(await send({...payload,revision:2})).status===409);
 check('New attempt cannot duplicate client report',(await send({...payload,submissionAttemptId:randomUUID()})).status===409);
 const wrong=await request('submissions',{method:'POST',token,raw:JSON.stringify(make()),headers:{'X-Payload-SHA256':'0'.repeat(64)}});check('Raw byte hash recomputed',wrong.status===400);
 const hidden=make();hidden.values.ont_serial='hidden-serial';check('Populated hidden field rejected',(await send(hidden)).status===422);
 const invalid=make();delete invalid.values.work_performed;check('Missing required field rejected',(await send(invalid)).status===422);
 const cancelled=make();const raw=JSON.stringify(cancelled);const fence=await request(`submission-attempts/${cancelled.submissionAttemptId}/cancel`,{method:'POST',token,body:{clientReportId:cancelled.clientReportId,payloadHash:sha256(raw)}});check('Unaccepted attempt cancellation fenced',fence.data.status==='cancelled');check('Late cancelled upload rejected',(await send(cancelled)).status===409);
 const racing=make();const racingRaw=JSON.stringify(racing);const [upload,cancel]=await Promise.all([send(racing),request(`submission-attempts/${racing.submissionAttemptId}/cancel`,{method:'POST',token,body:{clientReportId:racing.clientReportId,payloadHash:sha256(racingRaw)}})]);check('Cancellation/upload race has a single winning result',upload.status===201&&cancel.data.status==='accepted'||upload.status===409&&cancel.data.status==='cancelled');
 const draft=await request(`admin/templates/${t.templateId}/draft`,{cookie});const priorRevision=draft.data.revision;const schema=draft.data.schema;const updated=structuredClone(schema);updated.title=schema.title;
 const saved=await request(`admin/templates/${t.templateId}/draft`,{method:'PUT',cookie,body:updated,headers:{'If-Match':String(priorRevision)}});check('Draft saved in PostgreSQL',saved.status===200&&saved.data.revision===priorRevision+1);
 check('Stale save rejected',(await request(`admin/templates/${t.templateId}/draft`,{method:'PUT',cookie,body:updated,headers:{'If-Match':String(priorRevision)}})).status===409);
 check('Stale publication rejected',(await request(`admin/templates/${t.templateId}/publish`,{method:'POST',cookie,body:{expectedRevision:priorRevision}})).status===409);
 const published=await request(`admin/templates/${t.templateId}/publish`,{method:'POST',cookie,body:{expectedRevision:saved.data.revision}});check('Immutable version published',published.status===201&&published.data.id!==t.versionId);
 const historical=await request(`templates/${t.templateId}/versions/${t.versionId}`,{token});check('Old pinned version remains unchanged',historical.status===200&&historical.data.schemaHash===t.schemaHash);
 check('Authorized older-version report accepted',(await send(make())).status===201);
 const detail=await request(`admin/submissions/${first.data.receipt.reportId}`,{cookie});check('Historical submission uses original labels/version',detail.status===200&&detail.data.version.id===t.versionId&&detail.data.version.schema.title===t.title);
 const other=await request('auth/login',{method:'POST',body:{email:'repair@fieldassist.demo',password:process.env.SEED_ENGINEER_PASSWORD,audience:'mobile'}});const privateStatus=await request(`submissions/status/${payload.clientReportId}`,{token:other.data.token});check('Other engineer cannot read receipt',privateStatus.data.status==='unaccepted'&&!privateStatus.data.receipt);
 const type=await request('admin/engineer-types?limit=100',{cookie});const fibreType=type.data.items.find((x:any)=>x.id===t.engineerTypeId);check('Active assigned type cannot archive',(await request(`admin/engineer-types/${fibreType.id}`,{method:'PATCH',cookie,body:{expectedRevision:fibreType.revision,archived:true}})).status===409);
 const devices=await request('admin/devices?limit=100',{cookie});const device=devices.data.items.find((d:any)=>d.id===deviceId);check('Device state is last-reported and not fake ready',!!device.lastSeenAt&&device.readiness.voiceReady===false);
 await request('devices/heartbeat',{method:'POST',token,body:{deviceId,readiness:{voiceReady:false,manualReady:false,components:{kind:'API test only; not a physical device'}},packageVersion:'not device-verified',schemaVersion:`${t.versionNumber}`}});
 writeFileSync('docs/evidence/api-smoke.txt',`${new Date().toISOString()}\n${evidence.join('\n')}\n${evidence.length} checks passed. Synthetic API verification; no physical-device inference.\n`);
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
