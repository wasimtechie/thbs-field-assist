import assert from 'node:assert/strict';
import {chromium,expect} from '@playwright/test';
import {randomUUID} from 'node:crypto';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
const origin=process.env.APP_ORIGIN??'http://localhost:3002',base=origin+'/api/v1/';
const users:string[]=[],orgs:string[]=[],jobs:string[]=[],summaries:string[]=[];
async function req(path:string,body?:unknown,token?:string,cookie?:string){const r=await fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',Origin:origin,...(token?{Authorization:`Bearer ${token}`}:{Cookie:cookie??''})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]};}
async function main(){
 assert.ok(process.env.NODE_ENV!=='production'&&['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname)&&['localhost','127.0.0.1'].includes(new URL(origin).hostname));
 const org=await db.organization.create({data:{name:'Synthetic visit summary API test'}});orgs.push(org.id);
 const password=randomUUID();
 async function user(role:string,orgId=org.id){const u=await db.user.create({data:{organizationId:orgId,email:`summary-check-${randomUUID()}@fieldassist.demo`,passwordHash:await hash(password),name:'Synthetic summary API test',role}});users.push(u.id);return u;}
 const engineer=await user('ENGINEER'),other=await user('ENGINEER'),admin=await user('ADMIN');
 const login=await req('auth/login',{email:engineer.email,password,audience:'mobile'});assert.equal(login.status,200);const token=login.data.token;
 const loginOther=await req('auth/login',{email:other.email,password,audience:'mobile'});assert.equal(loginOther.status,200);
 const web=await req('auth/login',{email:admin.email,password,audience:'web'});assert.equal(web.status,200);
 const job=await db.workOrder.create({data:{organizationId:org.id,assigneeId:engineer.id,typeId:'30000000-0000-4000-8000-000000000006',createdBy:admin.id,title:'Synthetic visit summary check',site:'Fictional API test location',dueAt:new Date()}});jobs.push(job.id);
 const raw='Installed ONT. Optical receive 18.2 dBm, no no sorry optical receive -18.19 dBm; service test passed.';
 const corrected='Installed ONT. Optical receive -18.19 dBm; service test passed.';
 const payload={clientSummaryId:randomUUID(),clientReportId:randomUUID(),workOrderId:job.id,confirmedAt:new Date().toISOString(),values:{actual_work:corrected,claimed_outcome:'completed',serving_asset:'CBT-SYN-10',optical_rx_dbm:-18.19,operational_test:'passed',next_action:'No further work'},sources:{actual_work:{sourceType:'speech',sourceSpan:raw,rawTranscript:raw,interpretedSpan:corrected},optical_rx_dbm:{sourceType:'speech',sourceSpan:'optical receive -18.19 dBm',fieldId:'optical_rx_dbm',value:-18.19,verificationStatus:'candidate',derivedFrom:'actual_work',derivedSummary:raw,rawTranscript:raw,interpretedSpan:'optical receive -18.19 dBm',speechRepairs:[{discarded:'Optical receive 18.2 dBm',cue:'no no sorry',replacement:'optical receive -18.19 dBm'}]}}};
 assert.equal((await req('visit-summaries',payload)).status,401);
 assert.equal((await req('visit-summaries',payload,undefined,web.cookie)).status,403);
 assert.equal((await req('visit-summaries',payload,loginOther.data.token)).status,404);
 assert.equal((await req('visit-summaries',{...payload,values:{...payload.values,claimed_outcome:'blocked',next_action:null}},token)).status,422);
 const sent=await req('visit-summaries',payload,token);assert.equal(sent.status,201,JSON.stringify(sent.data));summaries.push(sent.data.id);assert.equal(sent.data.operationalClosureApproved,false);
 const again=await req('visit-summaries',payload,token);assert.equal(again.data.id,sent.data.id);
 assert.equal((await req('visit-summaries',{...payload,values:{...payload.values,optical_rx_dbm:-12}},token)).status,409);
 assert.equal(await db.visitSummary.count({where:{organizationId:org.id}}),1);
 const list=await req('admin/visit-summaries',undefined,undefined,web.cookie);assert.equal(list.status,200);assert.equal(list.data.items[0].id,sent.data.id);
 const detail=await req(`admin/visit-summaries/${sent.data.id}`,undefined,undefined,web.cookie);assert.equal(detail.status,200);assert.deepEqual(detail.data.values,payload.values);assert.deepEqual(detail.data.sources,payload.sources);
 assert.equal((await req(`admin/visit-summaries/${sent.data.id}`,undefined,loginOther.data.token)).status,404);
 assert.equal((await req('admin/visit-summaries',undefined,loginOther.data.token)).data.items.length,0);
 const otherOrg=await db.organization.create({data:{name:'Synthetic isolation test'}});orgs.push(otherOrg.id);const stranger=await user('ADMIN',otherOrg.id);
 const strangerWeb=await req('auth/login',{email:stranger.email,password,audience:'web'});assert.equal(strangerWeb.status,200);
 assert.equal((await req(`admin/visit-summaries/${sent.data.id}`,undefined,undefined,strangerWeb.cookie)).status,404);
 assert.equal((await db.workOrder.findUniqueOrThrow({where:{id:job.id}})).status,'assigned');
 assert.equal(await db.report.count({where:{organizationId:org.id}}),0);
 const browser=await chromium.launch({channel:'chrome',headless:true});
 try {
  const context=await browser.newContext({viewport:{width:1440,height:1040}});
  await context.addCookies([{name:'fa_session',value:web.cookie!.slice('fa_session='.length),url:origin}]);
  const page=await context.newPage();
  await page.goto(origin+'/submissions?view=visits');
  await expect(page.getByRole('heading',{name:'Visit summaries',exact:true})).toBeVisible();
  await expect(page.getByRole('link',{name:job.title,exact:true})).toBeVisible();
  await page.screenshot({path:'.local/visit-summary-dashboard.png',fullPage:true});
  await page.getByRole('link',{name:job.title,exact:true}).click();
  await expect(page.getByText('Submission receipt',{exact:true})).toBeVisible();
  await expect(page.getByText('-18.19',{exact:true})).toBeVisible();
  await expect(page.getByText(sent.data.id,{exact:true})).toBeVisible();
  await page.screenshot({path:'.local/visit-summary-detail.png',fullPage:true});
 } finally {await browser.close();}
 console.log('PASS: corrected reading and raw speech provenance retained, authenticated summary submit, validation, stable retry receipt, conflict rejection, dashboard list/detail, engineer and organization isolation, and unchanged operational closure.');
}
main().finally(async()=>{
 await db.visitSummary.deleteMany({where:{id:{in:summaries}}});
 await db.workOrder.deleteMany({where:{id:{in:jobs}}});
 await db.auditEvent.deleteMany({where:{organizationId:{in:orgs}}});
 await db.session.deleteMany({where:{userId:{in:users}}});
 await db.user.deleteMany({where:{id:{in:users}}});
 await db.organization.deleteMany({where:{id:{in:orgs}}});await db.$disconnect();
});
