import 'dotenv/config';
import {readFileSync,writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {strict as assert} from 'node:assert';
import {isDeepStrictEqual} from 'node:util';
import {db} from '../packages/database';
import {templateSchema,schemaBytes,sha256,type TemplateSchema} from '../packages/contracts/src';
const base=process.env.APP_ORIGIN??'http://localhost:3000';
const templateId='40000000-0000-4000-8000-000000000001';
let cookie='',token='';
const checks:string[]=[];
function check(name:string,value:unknown){assert.ok(value,name);checks.push(name);console.log(`PASS ${name}`);}
async function request(route:string,method='GET',body?:unknown,admin=false,revision?:number,raw?:string){
 const response=await fetch(`${base}/api/v1/${route}`,{method,headers:{'Content-Type':'application/json',Origin:base,...(admin?{Cookie:cookie}:{Authorization:`Bearer ${token}`}),...(revision?{'If-Match':String(revision)}:{}),...(raw?{'X-Payload-SHA256':sha256(raw)}:{})},body:raw??(body===undefined?undefined:JSON.stringify(body))});
 return {status:response.status,data:await response.json(),cookie:response.headers.get('set-cookie')};
}
async function main(){
 const login=await request('auth/login','POST',{email:'admin@fieldassist.demo',password:process.env.SEED_ADMIN_PASSWORD,audience:'web'},true);
 check('Administrator test session',login.status===200);cookie=login.cookie!.split(';')[0];
 try{
  const draft=await request(`admin/templates/${templateId}/draft`,'GET',undefined,true);
  check('Read current draft',draft.status===200);
  const published=await db.templateVersion.findUniqueOrThrow({where:{id:draft.data.template.currentPublishedVersionId}});
  const current=templateSchema.parse(draft.data.schema);
  const fixture=templateSchema.parse(JSON.parse(readFileSync('fixtures/templates/fibre-cable-label.json','utf8')));
  const desired=fixture.fields.filter(f=>f.scan);
  if(desired.some(f=>!current.fields.some(v=>v.scan?.target===f.scan?.target))){
   check('No unrelated unpublished draft changes',schemaBytes(current)===schemaBytes(templateSchema.parse(published.schema)));
   const missing=desired.filter(f=>!current.fields.some(v=>v.scan?.target===f.scan?.target));
   check('New IDs do not reuse existing fields',missing.every(f=>!current.fields.some(v=>v.id===f.id)));
   const section=fixture.sections.find(s=>s.id==='cable_identification')!;
   const next=templateSchema.parse({...current,sections:current.sections.some(s=>s.id===section.id)?current.sections:[section,...current.sections.map(s=>({...s,order:s.order+1}))],fields:[...missing,...current.fields].map((f,order)=>({...f,order}))});
   writeFileSync('docs/evidence/cable-template-before.json',JSON.stringify({versionId:published.id,versionNumber:published.versionNumber,schema:current},null,2)+'\n');
   const saved=await request(`admin/templates/${templateId}/draft`,'PUT',next,true,draft.data.revision);
   check('Save versioned scan draft',saved.status===200);
   const version=await request(`admin/templates/${templateId}/publish`,'POST',{expectedRevision:saved.data.revision},true);
   check('Publish immutable cable-label form',version.status===200||version.status===201);
  }
  const engineer=await request('auth/login','POST',{email:'fibre@fieldassist.demo',password:process.env.SEED_ENGINEER_PASSWORD,audience:'mobile'});
  check('Engineer test session',engineer.status===200);token=engineer.data.token;
  const provision=await request('devices/provision','POST',{deviceId:randomUUID(),platform:'android',appVersion:'camera-ocr-api-test',osVersion:'Synthetic verification',model:'Synthetic OCR verification'});
  check('Provision latest form with eight scan mappings',provision.status===200&&provision.data.template.fields.filter((f:any)=>f.scan).length===8);
  const form=provision.data.template as TemplateSchema&{versionId:string;schemaHash:string;versionNumber:number};
  const recognized:Record<string,unknown>={cable_id:'CBL-2026-0042',drum_id:'DR-0017',manufacturer:'DEMO CABLE WORKS',batch:'B2409-08',specification:'24F SM G.652D',fibre_count:24,declared_length:{amount:1000,unit:'m'},manufactured_date:'2026-09-18'};
  const values={installation_outcome:'partial',work_performed:'Synthetic cable-label OCR verification only. No actual field visit.',cable_installed:{amount:12,unit:'m'},connectivity_test:'not_tested',exception_reason:'Synthetic demo verification.',...Object.fromEntries(form.fields.filter(f=>f.scan).map(f=>[f.id,recognized[f.scan!.target]]))};
  const now=new Date().toISOString();
  const payload={clientReportId:randomUUID(),submissionAttemptId:randomUUID(),revision:1,templateId:form.templateId,versionId:form.versionId,schemaHash:form.schemaHash,entitlementId:provision.data.entitlementId,values,confirmedAt:now,originatingTimezone:'UTC',location:{latitude:12.9716,longitude:77.5946,accuracyMeters:15,capturedAt:now,isMocked:true}};
  const raw=JSON.stringify(payload);
  const accepted=await request('submissions','POST',undefined,false,undefined,raw);
  check('Reviewed label values accepted',accepted.status===201);
  const retry=await request('submissions','POST',undefined,false,undefined,raw);
  check('Original snapshot retry keeps one receipt',retry.status===200&&retry.data.receipt.id===accepted.data.receipt.id);
  const detail=await request(`admin/submissions/${accepted.data.receipt.reportId}`,'GET',undefined,true);
  check('Dashboard detail retains all eight typed label values',form.fields.filter(f=>f.scan).every(f=>isDeepStrictEqual(detail.data.values[f.id],recognized[f.scan!.target])));
  check('Printed length stays separate from installed length',detail.data.values.cable_installed.amount===12&&detail.data.values[form.fields.find(f=>f.scan?.target==='declared_length')!.id].amount===1000);
  const result={checks,templateVersion:form.versionNumber,reportId:detail.data.id,reportUrl:`${base}/submissions/${detail.data.id}`,scope:'Synthetic values and report, no actual physical camera or field visit'};
  writeFileSync('docs/evidence/cable-scan-api.json',JSON.stringify(result,null,2)+'\n');
 }finally{
  if(token)await request('auth/logout','POST',{});
  if(cookie)await request('auth/logout','POST',{},true);
 }
}
main().finally(()=>db.$disconnect());
