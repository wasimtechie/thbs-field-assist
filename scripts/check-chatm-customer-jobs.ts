import assert from 'node:assert/strict';
import {randomUUID,randomBytes} from 'node:crypto';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
import {sha256} from '@field-assist/contracts';

const origin='http://127.0.0.1:3002',orgs:string[]=[],users:string[]=[],jobs:string[]=[],types:string[]=[];
async function request(path:string,body?:unknown,auth?:string,method=body?'POST':'GET') {
  const r=await fetch(`${origin}/api/v1/${path}`,{method,redirect:'error',headers:{Origin:'http://localhost:3002','Content-Type':'application/json',...(auth?.startsWith('Bearer ')?{Authorization:auth}:auth?{Cookie:auth}:{})},...(body?{body:JSON.stringify(body)}:{})});
  return {status:r.status,data:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]};
}
async function main(){
  if(!['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname))throw Error('Local verification only.');
  const password=randomUUID(),passwordHash=await hash(password);
  const org=await db.organization.create({data:{name:'Synthetic Chatm connector verification'}});orgs.push(org.id);
  const other=await db.organization.create({data:{name:'Synthetic isolated Chatm verification'}});orgs.push(other.id);
  async function user(role:string){const u=await db.user.create({data:{email:`${randomUUID()}@fieldassist.demo`,name:'Synthetic connector check',role,organizationId:org.id,passwordHash}});users.push(u.id);return u;}
  const admin=await user('ADMIN'),engineer=await user('ENGINEER');
  const type=await db.engineerType.create({data:{organizationId:org.id,slug:'synthetic-chatm-check',name:'Synthetic connector checks'}});types.push(type.id);
  for(let i=0;i<3;i++){
    const job=await db.workOrder.create({data:{organizationId:i===2?other.id:org.id,title:`Synthetic connector job ${i}`,site:'Fictional connector test site',assigneeId:engineer.id,typeId:type.id,createdBy:admin.id,dueAt:new Date('2026-10-26T12:00:00Z')}});jobs.push(job.id);
    await db.customerJobStatus.create({data:{workOrderId:job.id,organizationId:i===2?other.id:org.id,customerEmail:i===1?'another@fieldassist.demo':'customer@fieldassist.demo',updatedBy:admin.id}});
  }
  const key='fa_chatm_'+randomBytes(32).toString('base64url');
  const connection=await db.chatmConnectionKey.create({data:{organizationId:org.id,label:'Synthetic test only',tokenHash:sha256(key)}});
  const path='integrations/chatm/customers/customer%40fieldassist.demo/jobs';
  assert.equal((await request(path)).status,401);
  assert.equal((await request(path,undefined,'Bearer fa_chatm_'+'x'.repeat(43))).status,401);
  const got=await request(path,undefined,`Bearer ${key}`);assert.equal(got.status,200);assert.equal(got.data.jobs.length,1);
  assert.equal(got.data.jobs[0].reference,jobs[0]);assert.equal(got.data.jobs[0].appointment,null);
  assert.equal(got.data.jobs[0].activation.status,'not_confirmed');assert.equal(got.data.jobs[0].latestVisit,null);
  assert.ok(!JSON.stringify(got.data).includes('dueAt'));
  assert.equal((await request(path,{},`Bearer ${key}`,'PUT')).status,404);
  assert.equal((await request(path+'?email=another%40fieldassist.demo',undefined,`Bearer ${key}`)).status,404);
  assert.equal((await request('admin/visit-summaries',undefined,`Bearer ${key}`)).status,401);
  const mobile=await request('auth/login',{email:engineer.email,password,audience:'mobile'});assert.equal(mobile.status,200);
  const summary={clientSummaryId:randomUUID(),clientReportId:randomUUID(),workOrderId:jobs[0],confirmedAt:new Date().toISOString(),
    values:{actual_work:'Synthetic ONT installed and service tested.',claimed_outcome:'completed',serving_asset:'CBT-SYN-10',optical_rx_dbm:-18.2,operational_test:'passed',next_action:'Provider activation remains unconfirmed.'},sources:{actual_work:{sourceType:'speech',sourceSpan:'Synthetic test speech; never return this source transcript.'}}};
  const sent=await request('visit-summaries',summary,`Bearer ${mobile.data.token}`);assert.equal(sent.status,201);
  const after=await request(path,undefined,`Bearer ${key}`);assert.equal(after.data.jobs[0].latestVisit.receiptId,sent.data.id);
  assert.equal(after.data.jobs[0].activation.status,'not_confirmed');assert.equal(after.data.jobs[0].status,'assigned');
  for(const forbidden of ['sourceSpan','passwordHash','tokenHash','userId','dueAt'])assert.ok(!JSON.stringify(after.data).includes(forbidden));
  const web=await request('auth/login',{email:admin.email,password,audience:'web'});assert.equal(web.status,200);
  const update={expectedRevision:1,customerEmail:'customer@fieldassist.demo',appointmentStartAt:'2026-10-26T09:00:00Z',appointmentEndAt:'2026-10-26T11:00:00Z',appointmentTimezone:'Europe/London',activationStatus:'scheduled',activationAt:'2026-10-27T10:00:00Z',activationNote:'Synthetic provider-confirmed test time.'};
  assert.equal((await request(`admin/work-orders/${jobs[0]}/customer-status`,update,web.cookie,'PUT')).status,200);
  assert.equal((await request(`admin/work-orders/${jobs[0]}/customer-status`,update,web.cookie,'PUT')).status,409);
  const confirmed=await request(path,undefined,`Bearer ${key}`);assert.equal(confirmed.data.jobs[0].activation.at,'2026-10-27T10:00:00.000Z');
  assert.equal(confirmed.data.jobs[0].appointment.startAt,'2026-10-26T09:00:00.000Z');
  assert.match(confirmed.data.jobs[0].appointment.displayWindow,/09:00.*11:00.*Europe\/London/);
  assert.match(confirmed.data.jobs[0].activation.displayAt,/10:00.*Europe\/London/);
  assert.equal((await request(`admin/work-orders/${jobs[2]}/customer-status`,update,web.cookie,'PUT')).status,404);
  await db.chatmConnectionKey.update({where:{id:connection.id},data:{revokedAt:new Date()}});
  assert.equal((await request(path,undefined,`Bearer ${key}`)).status,401);
  console.log('PASS: real submit → live customer job lookup, confirmed visit/activation, no inferred activation, read-only scope, customer/org isolation, stale revision and revoked-key rejection.');
}
main().finally(async()=>{
  await db.customerJobStatus.deleteMany({where:{organizationId:{in:orgs}}});
  await db.visitSummary.deleteMany({where:{organizationId:{in:orgs}}});
  await db.workOrder.deleteMany({where:{id:{in:jobs}}});
  await db.chatmConnectionKey.deleteMany({where:{organizationId:{in:orgs}}});
  await db.auditEvent.deleteMany({where:{organizationId:{in:orgs}}});
  await db.session.deleteMany({where:{userId:{in:users}}});
  await db.user.deleteMany({where:{id:{in:users}}});
  await db.engineerType.deleteMany({where:{id:{in:types}}});
  await db.organization.deleteMany({where:{id:{in:orgs}}});await db.$disconnect();
});
