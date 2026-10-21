import 'dotenv/config';
import {strict as assert} from 'node:assert';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {sha256} from '../packages/contracts/src';
const base=process.env.APP_ORIGIN??'http://localhost:3000';
let token='',cookie='';
const checks:string[]=[];
async function request(route:string,body?:unknown,admin=false,raw?:string){
 const response=await fetch(`${base}/api/v1/${route}`,{method:body===undefined&&raw===undefined?'GET':'POST',headers:{'Content-Type':'application/json',Origin:base,...(admin?{Cookie:cookie}:token?{Authorization:`Bearer ${token}`}:{ }),...(raw?{'X-Payload-SHA256':sha256(raw)}:{})},body:raw??(body===undefined?undefined:JSON.stringify(body))});
 return {status:response.status,data:await response.json(),cookie:response.headers.get('set-cookie')};
}
function check(name:string,ok:unknown){assert.ok(ok,name);checks.push(name);console.log(`PASS ${name}`);}
async function main(){
 const admin=await request('auth/login',{email:'admin@fieldassist.demo',password:process.env.SEED_ADMIN_PASSWORD,audience:'web'});
 check('Admin session',admin.status===200);cookie=admin.cookie!.split(';')[0];
 const engineer=await request('auth/login',{email:'fibre@fieldassist.demo',password:process.env.SEED_ENGINEER_PASSWORD,audience:'mobile'});
 check('Engineer session',engineer.status===200);token=engineer.data.token;
 try{
  const provision=await request('devices/provision',{deviceId:randomUUID(),platform:'android',appVersion:'location-api-test',osVersion:'Synthetic API test',model:'Synthetic location verification'});
  check('Provisioned location test',provision.status===200);
  const p=provision.data,t=p.template,now=new Date().toISOString();
  const payload={clientReportId:randomUUID(),submissionAttemptId:randomUUID(),revision:1,templateId:t.templateId,versionId:t.versionId,schemaHash:t.schemaHash,entitlementId:p.entitlementId,values:{installation_outcome:'partial',work_performed:'Synthetic location verification only. No actual field visit.',cable_installed:{amount:12,unit:'m'},connectivity_test:'not_tested',exception_reason:'Synthetic verification, follow-up needed.'},confirmedAt:now,originatingTimezone:'UTC',location:{latitude:12.9716,longitude:77.5946,accuracyMeters:12.5,capturedAt:now,isMocked:true}};
  const raw=JSON.stringify(payload);
  const first=await request('submissions',undefined,false,raw);
  if(first.status!==201)throw new Error(`Location acceptance failed: ${first.status} ${JSON.stringify(first.data.error)}`);
  check('Located report accepted',first.status===201);
  const retry=await request('submissions',undefined,false,raw);
  check('Retry returns same receipt',retry.status===200&&retry.data.receipt.id===first.data.receipt.id);
  const detail=await request(`admin/submissions/${first.data.receipt.reportId}`,undefined,true);
  check('Detail retains exact captured position and time',JSON.stringify(detail.data.location)===JSON.stringify(payload.location)||['latitude','longitude','accuracyMeters','capturedAt','isMocked'].every(key=>detail.data.location?.[key]===payload.location[key as keyof typeof payload.location]));
  const dashboard=await request('admin/dashboard',undefined,true);
  check('Dashboard exposes captured location',dashboard.data.recent.some((r:any)=>r.id===detail.data.id&&r.location?.latitude===12.9716));
  const list=await request('admin/submissions?limit=100',undefined,true);
  check('Submissions list exposes location',list.data.items.some((r:any)=>r.id===detail.data.id&&r.location?.longitude===77.5946));
  for(const bad of [{latitude:91},{accuracyMeters:-1},{capturedAt:new Date(Date.now()-600000).toISOString()}]){
   const invalid={...payload,clientReportId:randomUUID(),submissionAttemptId:randomUUID(),location:{...payload.location,...bad}};
   check(`Rejects invalid location ${Object.keys(bad)[0]}`,(await request('submissions',undefined,false,JSON.stringify(invalid))).status===422);
  }
  const {location:_,...legacy}=payload;
  legacy.clientReportId=randomUUID();legacy.submissionAttemptId=randomUUID();
  const older=await request('submissions',undefined,false,JSON.stringify(legacy));
  check('Existing frozen queues without location still upload',older.status===201);
  writeFileSync('docs/evidence/location-api.json',JSON.stringify({checkedAt:new Date().toISOString(),checks,reportId:detail.data.id,clientReportId:payload.clientReportId,location:payload.location,scope:'Synthetic HTTP verification; not physical GPS.'},null,2)+'\n');
 }finally{
  await request('auth/logout',{},false);await request('auth/logout',{},true);
 }
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
