import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {parseEnv} from 'node:util';
import {db} from '../packages/database';

const root='/Users/Mohammed/Desktop/chatm',origin='http://127.0.0.1:3002';
async function main(){
 if(!['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname))throw Error('Local databases only.');
 const source=await db.workOrder.findUniqueOrThrow({where:{id:'80000000-0000-4000-8006-000000000001'}});
 assert.ok(source.site.startsWith('Fictional demo property'));
 const jobId=randomUUID(),email=`check-${randomUUID()}@fieldassist.demo`;
 let token:string|undefined;
 try{
  const appointment=new Date();appointment.setUTCDate(appointment.getUTCDate()+1);appointment.setUTCHours(9,0,0,0);
  const end=new Date(appointment.getTime()+2*3600000);
  await db.workOrder.create({data:{id:jobId,organizationId:source.organizationId,title:'Synthetic connector check · FTTP follow-up',site:'Fictional connector check property · Bristol',assigneeId:source.assigneeId,typeId:source.typeId,createdBy:source.createdBy,status:'follow_up',responseStatus:'accepted',dueAt:appointment}});
  await db.customerJobStatus.create({data:{workOrderId:jobId,organizationId:source.organizationId,customerEmail:email,updatedBy:source.createdBy,appointmentStartAt:appointment,appointmentEndAt:end,appointmentTimezone:'Europe/London',activationStatus:'blocked',activationNote:'Civils work must finish before the provider can confirm broadband activation.'}});
  const login=await fetch(origin+'/api/v1/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'closure@fieldassist.demo',password:'123456',audience:'mobile'})});
  assert.equal(login.status,200);token=(await login.json()).token;
  const submitted=await fetch(origin+'/api/v1/visit-summaries',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify({clientSummaryId:randomUUID(),clientReportId:randomUUID(),workOrderId:jobId,confirmedAt:new Date().toISOString(),values:{actual_work:'Surveyed the fibre route. Found the duct blocked 13.5 metres from the chamber. Left the site safe.',claimed_outcome:'blocked',serving_asset:'CBT-SYN-CHECK',optical_rx_dbm:null,operational_test:'not_tested',next_action:'Civils team must clear the blocked duct before installation can finish.'},sources:{actual_work:{sourceType:'text',sourceSpan:'Synthetic connector test narrative.'}}})});
  assert.equal(submitted.status,201);
  console.log('Created a temporary synthetic booked follow-up and submitted an actual engineer summary through the normal API.');
  const env={...process.env};
  for(const f of ['.env.local','.env.nango.local','.env.field-assist.local'])Object.assign(env,parseEnv(readFileSync(`${root}/apps/web/${f}`,'utf8')));
  env.FIELD_ASSIST_TEST_CUSTOMER_EMAIL=email;
  env.FIELD_ASSIST_EXPECTED_VISIT_CLOCK=new Intl.DateTimeFormat('en-GB',{hour:'2-digit',minute:'2-digit',timeZone:'Europe/London'}).format(appointment);
  const child=spawn(process.execPath,['--import','../../packages/db/node_modules/tsx/dist/loader.mjs','scripts/smoke-field-assist.ts'],{cwd:root+'/apps/web',env,stdio:'inherit'});
  const code=await new Promise<number|null>((resolve,reject)=>{child.once('error',reject);child.once('exit',resolve);});
  assert.equal(code,0,'The actual Chatm customer conversation checks failed.');
 }finally{
  if(token)await fetch(origin+'/api/v1/auth/logout',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:'{}'}).catch(()=>{});
  await db.visitSummary.deleteMany({where:{workOrderId:jobId}});
  await db.customerJobStatus.deleteMany({where:{workOrderId:jobId}});
  await db.auditEvent.deleteMany({where:{organizationId:source.organizationId,entityId:jobId}});
  await db.workOrder.deleteMany({where:{id:jobId}});
  console.log('Removed the temporary connector job; the original S1 job and submissions were preserved.');
 }
}
main().finally(()=>db.$disconnect());
