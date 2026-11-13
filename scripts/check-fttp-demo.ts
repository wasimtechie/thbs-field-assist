import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
import {sha256,FTTP_TEMPLATE_ID} from '../packages/contracts/src';
const origin=process.env.APP_ORIGIN??'http://localhost:3002',base=origin+'/api/v1/';
const run=randomUUID(),email=`fttp-check-${run}@fieldassist.demo`,password=randomUUID();
const typeId='30000000-0000-4000-8000-000000000005',org='10000000-0000-4000-8000-000000000001';
let userId='';const jobIds:string[]=[],reportIds:string[]=[];
async function request(path:string,body?:unknown,token?:string,cookie?:string){const response=await fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',Origin:origin,...(token?{Authorization:`Bearer ${token}`}:{Cookie:cookie??''})},...(body?{body:JSON.stringify(body)}:{})});return {status:response.status,data:await response.json(),cookie:response.headers.get('set-cookie')?.split(';')[0]};}
async function main(){
 assert.ok(process.env.NODE_ENV!=='production'&&['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname)&&['localhost','127.0.0.1'].includes(new URL(origin).hostname),'Only a local development database and API may be used for verification');
 const user=await db.user.create({data:{organizationId:org,email,name:'Synthetic FTTP API check',role:'ENGINEER',passwordHash:await hash(password)}});userId=user.id;
 await db.engineerAssignment.create({data:{userId,typeId,revision:1}});
 const admin=await request('auth/login',{email:'admin@thbs.com',password:'123456',audience:'web'});assert.equal(admin.status,200);
 const login=await request('auth/login',{email,password,audience:'mobile'});assert.equal(login.status,200);const token=login.data.token;
 const provision=await request('devices/provision',{deviceId:randomUUID(),platform:'ios',appVersion:'fttp-api-check',osVersion:'synthetic API check'},token);assert.equal(provision.status,200);assert.equal(provision.data.template.templateId,FTTP_TEMPLATE_ID);
 const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6nCgAAAAASUVORK5CYII=','base64');
 const evidence=(stages:string[])=>stages.map(stage=>({id:randomUUID(),stage,caption:'Synthetic API verification image',mimeType:'image/png',data:bytes.toString('base64'),sha256:sha256(bytes),capturedAt:new Date().toISOString(),synthetic:true}));
 const values={installation_outcome:'completed',access_confirmed:true,route_agreed:true,site_checks:true,work_performed:'SYNTHETIC API verification',cable_id:'DEMO-101',csp_reference:'DEMO-CSP-101',cable_installed:{amount:12,unit:'m'},ont_serial:'DEMO-ONT-101',optical_reading:-22.4,connectivity_test:'passed',tester_reference:'DEMO-TEST-101',customer_handover:true,site_tidy:true};
 for(const blocked of [false,true]){
 const job=await db.workOrder.create({data:{organizationId:org,assigneeId:userId,typeId,createdBy:admin.data.user.id,title:'Synthetic FTTP API check',site:'Fictional test site',priority:'normal',dueAt:new Date(),responseStatus:'accepted'}});jobIds.push(job.id);
 const t=provision.data.template,payload={clientReportId:randomUUID(),submissionAttemptId:randomUUID(),revision:1,templateId:t.templateId,versionId:t.versionId,schemaHash:t.schemaHash,entitlementId:provision.data.entitlementId,values:blocked?{installation_outcome:'blocked',work_performed:'SYNTHETIC API verification',connectivity_test:'not_tested',exception_reason:'Duct blocked',next_team:'civils',next_action:'Coordinate clearance and return access'}:values,evidence:evidence(blocked?['blocker']:['before','installation','test']),confirmedAt:new Date().toISOString(),originatingTimezone:'Europe/London',workOrderId:job.id,workOrderAssignmentRevision:1};
 async function submit(value:unknown){const raw=JSON.stringify(value),response=await fetch(base+'submissions',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','X-Payload-SHA256':sha256(raw)},body:raw});return {status:response.status,data:await response.json()};}
 const incomplete=await submit({...payload,evidence:[]});assert.equal(incomplete.status,422,JSON.stringify(incomplete.data));
 const sent=await submit(payload);assert.equal(sent.status,201,JSON.stringify(sent.data));const receipt=sent.data.receipt;reportIds.push(receipt.reportId);
 const retry=await submit(payload);assert.equal(retry.status,200);assert.equal(retry.data.receipt.id,receipt.id);
 const stored=await db.report.findUniqueOrThrow({where:{id:receipt.reportId}});assert.equal((stored.evidence as any[]).length,payload.evidence.length);assert.equal(stored.demo,true);
 if(blocked){const rejected=await request(`admin/submissions/${stored.id}/review`,{decision:'approved',note:''},undefined,admin.cookie);assert.equal(rejected.status,422);}
 const reviewed=await request(`admin/submissions/${stored.id}/review`,{decision:blocked?'follow_up':'approved',note:blocked?'Civils coordination: clear obstruction and arrange return access.':'Synthetic verification passed.'},undefined,admin.cookie);assert.equal(reviewed.status,200,JSON.stringify(reviewed.data));
 assert.equal((await db.workOrder.findUniqueOrThrow({where:{id:job.id}})).status,blocked?'follow_up':'completed');
 console.log(blocked?'PASS: blocked handover, evidence retained, approval refused, follow-up assigned.':'PASS: complete installation, evidence retained, duplicate retry uses original receipt, supervisor approval.');
 }
}
main().finally(async()=>{
 try {
  // Accepted reports and reviews are immutable. Retain labelled verification
  // records, revoke the temporary session and disable its synthetic account.
  if(userId){await db.session.updateMany({where:{userId},data:{revokedAt:new Date()}});await db.user.update({where:{id:userId},data:{disabledAt:new Date()}});}
 } finally {await db.$disconnect();}
}).catch(error=>{console.error(error);process.exitCode=1});
