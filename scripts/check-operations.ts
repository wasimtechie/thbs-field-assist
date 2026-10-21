import 'dotenv/config';
import {strict as assert} from 'node:assert';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {db} from '../packages/database';
import {sha256} from '../packages/contracts/src';
const base=process.env.APP_ORIGIN??'http://localhost:3000';
let cookie='',token='',otherToken='';const checks:string[]=[];
function check(name:string,ok:unknown){assert.ok(ok,name);checks.push(name);console.log(`PASS ${name}`);}
async function request(path:string,method='GET',body?:unknown,as:'admin'|'engineer'|'other'='admin',raw?:string){
 const response=await fetch(`${base}/api/v1/${path}`,{method,headers:{'Content-Type':'application/json',Origin:base,...(as==='admin'?{Cookie:cookie}:{Authorization:`Bearer ${as==='other'?otherToken:token}`}),...(raw?{'X-Payload-SHA256':sha256(raw)}:{})},body:raw??(body===undefined?undefined:JSON.stringify(body))});
 return {status:response.status,data:await response.json(),cookie:response.headers.get('set-cookie')};
}
async function main(){
 try{
  let r=await request('auth/login','POST',{email:'admin@fieldassist.demo',password:process.env.SEED_ADMIN_PASSWORD,audience:'web'});check('Admin session',r.status===200);cookie=r.cookie!.split(';')[0];
  if(process.argv.includes('--filters-only')){
   r=await request('admin/work-orders?status=completed&overdue=true');check('Completed and overdue filters intersect to an empty result',r.status===200&&r.data.total===0&&r.data.items.length===0);
   r=await request('admin/work-orders?status=assigned&overdue=true&limit=100');check('Assigned overdue filter returns only overdue assigned work',r.status===200&&r.data.items.every((j:any)=>j.status==='assigned'&&new Date(j.dueAt)<new Date()));
   r=await request('admin/work-orders?search=NONEXISTENT-SYNTHETIC-SEARCH-99999');check('Unmatched search returns an empty filtered result',r.status===200&&r.data.total===0);
   r=await request('admin/work-orders?status=not-a-status');check('Unsupported status rejected',r.status===400);
   writeFileSync('docs/evidence/operations-filter-api.json',JSON.stringify({checks,scope:'Read-only filter regression checks against the local API'},null,2)+'\n');return;
  }
  r=await request('auth/login','POST',{email:'fibre@fieldassist.demo',password:process.env.SEED_ENGINEER_PASSWORD,audience:'mobile'});check('Engineer session',r.status===200);token=r.data.token;const engineerId=r.data.user.id;
  r=await request('auth/login','POST',{email:'repair@fieldassist.demo',password:process.env.SEED_ENGINEER_PASSWORD,audience:'mobile'});check('Other engineer session',r.status===200);otherToken=r.data.token;const otherId=r.data.user.id;
  const data={title:'Demo · Cable evidence and supervisor handoff',site:'Synthetic Orion hub · Bengaluru',assetReference:'CBL-2026-0042',instructions:'Synthetic demo only. Read the cable label and record the actual work outcome. This is not a field visit.',assigneeId:engineerId,priority:'urgent',dueAt:new Date(Date.now()-3600000).toISOString()};
  r=await request('admin/work-orders','POST',data,'engineer');check('Engineer cannot assign work',r.status===403);
  r=await request('admin/work-orders','POST',{...data,assigneeId:randomUUID()});check('Unavailable assignee rejected',r.status===422);
  r=await request('admin/work-orders','POST',data);check('Assign real stored work order',r.status===201);const job=r.data;
  r=await request(`admin/work-orders/${job.id}`,'PATCH',{...data,expectedRevision:99999});check('Stale assignment edit rejected',r.status===409);
  r=await request(`admin/work-orders/${job.id}`,'PATCH',{...data,expectedRevision:job.revision,instructions:data.instructions+' Verify the printed length separately.'});check('Revision-checked assignment edit',r.status===200);
  r=await request('mobile/operations','GET',undefined,'engineer');check('Assigned brief available to its engineer',r.data.workOrders.some((j:any)=>j.id===job.id));
  r=await request('mobile/operations','GET',undefined,'other');check('Another engineer cannot download the brief',!r.data.workOrders.some((j:any)=>j.id===job.id));
  const provision=await request('devices/provision','POST',{deviceId:randomUUID(),platform:'ios',appVersion:'operations-api-test',osVersion:'Synthetic verification',model:'Synthetic operations integration'},'engineer');check('Provision assigned form',provision.status===200);
  const form=provision.data.template;
  const values={installation_outcome:'partial',work_performed:'Synthetic operations verification: twelve metres installed, follow-up required.',cable_installed:{amount:12,unit:'m'},connectivity_test:'not_tested',exception_reason:'Synthetic connection pending.',label_cable_id:'CBL-2026-0042',label_manufacturer:'DEMO CABLE WORKS'};
  function payload(workOrderId=job.id){const now=new Date().toISOString();return {clientReportId:randomUUID(),submissionAttemptId:randomUUID(),revision:1,templateId:form.templateId,versionId:form.versionId,schemaHash:form.schemaHash,entitlementId:provision.data.entitlementId,values,confirmedAt:now,originatingTimezone:'UTC',location:{latitude:12.9716,longitude:77.5946,accuracyMeters:12,capturedAt:now,isMocked:true},workOrderId};}
  const wrong=await request('admin/work-orders','POST',{...data,title:'Demo · Repair team assignment',assigneeId:otherId});
  r=await request('submissions','POST',undefined,'engineer',JSON.stringify(payload(wrong.data.id)));check('Cannot submit another engineer’s work order',r.status===403&&r.data.error.code==='WORK_ORDER_UNAVAILABLE');
  const first=JSON.stringify(payload());r=await request('submissions','POST',undefined,'engineer',first);check('Linked report accepted',r.status===201);const receipt=r.data.receipt;
  r=await request('submissions','POST',undefined,'engineer',first);check('Frozen retry has stable receipt',r.status===200&&r.data.receipt.id===receipt.id);
  r=await request('mobile/operations','GET',undefined,'engineer');check('Received report waits for supervisor',r.data.workOrders.find((j:any)=>j.id===job.id).status==='submitted');
  r=await request(`admin/work-orders/${job.id}`,'PATCH',{...data,expectedRevision:2});check('Submitted assignment cannot be silently changed',r.status===409);
  r=await request(`admin/submissions/${receipt.reportId}/review`,'POST',{decision:'approved',note:''},'engineer');check('Engineer cannot approve own report',r.status===403);
  r=await request(`admin/submissions/${receipt.reportId}/review`,'POST',{decision:'follow_up',note:'   '});check('Follow-up requires instructions',r.status===422);
  const follow={decision:'follow_up',note:'Synthetic review: record the connectivity result on the next visit.'};
  r=await request(`admin/submissions/${receipt.reportId}/review`,'POST',follow);check('Supervisor records follow-up',r.status===200);const decision=r.data;
  r=await request(`admin/submissions/${receipt.reportId}/review`,'POST',follow);check('Same decision retry is idempotent',r.status===200&&r.data.reviewedAt===decision.reviewedAt);
  r=await request(`admin/submissions/${receipt.reportId}/review`,'POST',{decision:'approved',note:''});check('Conflicting review does not overwrite history',r.status===409);
  r=await request('submissions','POST',undefined,'engineer',first);check('Late upload retry does not reset follow-up status',r.status===200&&(await db.workOrder.findUniqueOrThrow({where:{id:job.id}})).status==='follow_up');
  r=await request('mobile/operations','GET',undefined,'engineer');check('Engineer receives follow-up and reviewer note',r.data.workOrders.some((j:any)=>j.id===job.id&&j.status==='follow_up'&&j.reviewNote===follow.note)&&r.data.feedback.some((f:any)=>f.reportId===receipt.reportId));
  r=await request('mobile/operations','GET',undefined,'other');check('Review feedback is scoped to the engineer',!r.data.feedback.some((f:any)=>f.reportId===receipt.reportId));
  const next=payload();next.values={...values,installation_outcome:'completed',connectivity_test:'passed',ont_serial:'DEMO-ONT-0042',optical_reading:-18.5,work_performed:'Synthetic follow-up verification only. No actual field work.'};delete (next.values as any).exception_reason;
  r=await request('submissions','POST',undefined,'engineer',JSON.stringify(next));if(r.status!==201)console.log('Synthetic follow-up validation:',JSON.stringify(r.data));check('Follow-up creates a separate report',r.status===201);const nextReceipt=r.data.receipt;
  r=await request(`admin/submissions/${nextReceipt.reportId}/review`,'POST',{decision:'approved',note:'Synthetic demo verification complete.'});check('Explicit approval completes the linked demo job',r.status===200&&(await db.workOrder.findUniqueOrThrow({where:{id:job.id}})).status==='completed');
  const original=await request(`admin/submissions/${receipt.reportId}`);check('Original report and receipt remain unchanged',original.data.values.installation_outcome==='partial'&&original.data.receipt.id===receipt.id&&original.data.review.decision==='follow_up');
  const future=await request('admin/work-orders','POST',{...data,title:'Demo · Next scheduled visit for this cable',priority:'normal',dueAt:new Date(Date.now()+86400000).toISOString()});check('Next scheduled visit can reuse the asset reference',future.status===201);
  r=await request(`admin/asset-history?asset=${encodeURIComponent(data.assetReference)}`);check('Asset history connects separate visits and their evidence',r.status===200&&r.data.history.some((j:any)=>j.id===job.id)&&r.data.history.some((j:any)=>j.id===future.data.id));
  r=await request('admin/reviews?status=approved&limit=100');check('Reviewed report leaves pending inbox',r.data.items.some((v:any)=>v.id===nextReceipt.reportId));
  r=await request('admin/operations/summary');check('Operations KPIs use actual jobs and decisions',r.data.counts.completed>=1&&r.data.total>=3&&r.data.workload.some((e:any)=>e.id===engineerId)&&r.data.trend.length===7);
  let immutable=false;try{await db.reportReview.update({where:{reportId:receipt.reportId},data:{note:'Should not change'}});}catch{immutable=true;}check('Database enforces immutable review decisions',immutable);
  writeFileSync('docs/evidence/operations-api.json',JSON.stringify({checks,jobId:job.id,followUpReportId:receipt.reportId,approvedReportId:nextReceipt.reportId,scheduledJobId:future.data.id,scope:'Synthetic HTTP verification against the real local database; no physical visit or camera/network claim'},null,2)+'\n');
 }finally{
  if(token)await request('auth/logout','POST',{},'engineer');if(otherToken)await request('auth/logout','POST',{},'other');if(cookie)await request('auth/logout','POST',{});
 }
}
main().finally(()=>db.$disconnect());
