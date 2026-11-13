import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
import {templateSchema,validateValues,isVisible,sha256,closureChecks} from '../packages/contracts/src';
const origin=process.env.APP_ORIGIN??'http://localhost:3002',base=origin+'/api/v1/';
const examples=JSON.parse(readFileSync('fixtures/closure-mvp/examples.json','utf8'));
let userId='';
async function request(path:string,body?:unknown,token?:string,cookie?:string){const r=await fetch(base+path,{method:body?'POST':'GET',headers:{'Content-Type':'application/json',Origin:origin,...(token?{Authorization:`Bearer ${token}`}:{Cookie:cookie??''})},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]};}
async function main(){
 assert.ok(process.env.NODE_ENV!=='production'&&['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname)&&['localhost','127.0.0.1'].includes(new URL(origin).hostname));
 const email=`closure-check-${randomUUID()}@fieldassist.demo`,password=randomUUID();
 const user=await db.user.create({data:{organizationId:'10000000-0000-4000-8000-000000000001',email,passwordHash:await hash(password),name:'Synthetic closure MVP API verification',role:'ENGINEER'}});userId=user.id;
 await db.engineerAssignment.create({data:{userId,typeId:'30000000-0000-4000-8000-000000000006',revision:1}});
 const admin=await request('auth/login',{email:'admin@thbs.com',password:'123456',audience:'web'});assert.equal(admin.status,200);
 const login=await request('auth/login',{email,password,audience:'mobile'});assert.equal(login.status,200);const token=login.data.token;
 const p=await request('devices/provision',{deviceId:randomUUID(),platform:'ios',appVersion:'closure-api-verification',osVersion:'synthetic integration check'},token);assert.equal(p.status,200);const t=p.data.template;const {versionId:_,versionNumber:__,schemaHash:___,...definition}=t;const schema=templateSchema.parse(definition);
 const bytes=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6nCgAAAAASUVORK5CYII=','base64');
 const evidence=['before','installation','test','blocker'].map(stage=>({id:randomUUID(),stage,caption:'SYNTHETIC CLOSURE API VERIFICATION',mimeType:'image/png',data:bytes.toString('base64'),sha256:sha256(bytes),capturedAt:new Date().toISOString(),synthetic:true}));
 async function submit(payload:unknown){const raw=JSON.stringify(payload),r=await fetch(base+'submissions',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','X-Payload-SHA256':sha256(raw)},body:raw});return {status:r.status,data:await r.json()};}
 for(const scenario of ['S1','S2','S3','S4','S5']){
  const validation=validateValues(schema,examples[scenario]);assert.ok(validation.valid,JSON.stringify(validation.errors));const values=validation.values;
  assert.deepEqual(closureChecks(schema,values,evidence).issues,[]);
  const job=await db.workOrder.create({data:{organizationId:user.organizationId,assigneeId:userId,typeId:schema.engineerTypeId,createdBy:admin.data.user.id,title:`Synthetic closure API verification ${scenario}`,site:'Fictional verification site',priority:'normal',dueAt:new Date(),responseStatus:'accepted',closureContext:{scenario,workStage:values.work_stage}}});
  const now=new Date().toISOString(),closureReview={policyId:'fttp-closure-mvp',policyVersion:schema.closurePolicy!.version,humanConfirmed:true,transcript:String(values.actual_work),transcriptHistory:['Engineer selected: Yes'],candidates:[{questionId:`${scenario}-Q04`,fieldId:'actual_work',evidenceId:null,value:values.actual_work,sourceSpan:values.actual_work,sourceType:'text',confidence:null,verificationStatus:'accepted',ambiguityReason:'Synthetic API test; engineer confirmation simulated by this test.'},{questionId:schema.closurePolicy!.banks.find(b=>b.id===scenario)!.questions.find(q=>q.fieldId==='identity_verified')!.questionId,fieldId:'identity_verified',evidenceId:null,value:values.identity_verified,sourceSpan:'Yes',sourceType:'manual',confidence:null,verificationStatus:'accepted',ambiguityReason:'Synthetic option selection; final human confirmation simulated by this test.'}],questionStates:Object.fromEntries(schema.closurePolicy!.banks.flatMap(b=>b.questions.map(q=>[q.questionId,b.id!==scenario?'NOT_SHOWN':isVisible(schema.fields.find(f=>f.id===q.fieldId)!,values,schema.fields)?'VERIFIED':'NOT_SHOWN']))),branchEvents:[],metrics:{startedAt:now,reviewedAt:now,elapsedMs:0,extractionMs:0,promptsShown:0,corrections:0}};
  const payload={clientReportId:randomUUID(),submissionAttemptId:randomUUID(),revision:1,templateId:t.templateId,versionId:t.versionId,schemaHash:t.schemaHash,entitlementId:p.data.entitlementId,values,evidence,closureReview,confirmedAt:now,originatingTimezone:'Europe/London',location:{latitude:51.4545,longitude:-2.5879,accuracyMeters:10,capturedAt:now,isMocked:true},workOrderId:job.id,workOrderAssignmentRevision:1};
  assert.equal((await submit({...payload,evidence:[]})).status,422);
  assert.equal((await submit({...payload,workOrderId:undefined})).status,422);
  assert.equal((await submit({...payload,closureReview:undefined})).status,422);
  assert.equal((await submit({...payload,closureReview:{...closureReview,candidates:[{...closureReview.candidates[0],sourceSpan:'Not present in the preserved narrative.'}]}})).status,422);
  assert.equal((await submit({...payload,closureReview:{...closureReview,candidates:[{...closureReview.candidates[1],sourceType:'touch'}]}})).status,422);
  if(scenario==='S2')assert.equal((await submit({...payload,values:{...values,claimed_outcome:'completed'}})).status,422);
  if(scenario==='S1'){const wrong=validateValues(schema,examples.S2).values;const rejected=await submit({...payload,values:wrong});assert.equal(rejected.status,422);assert.equal(rejected.data.error.code,'CLOSURE_CONTEXT_MISMATCH');}
  const sent=await submit(payload);assert.equal(sent.status,201,JSON.stringify(sent.data));const receipt=sent.data.receipt;
  const retry=await submit(payload);assert.equal(retry.status,200);assert.equal(retry.data.receipt.id,receipt.id);
  const stored=await db.report.findUniqueOrThrow({where:{id:receipt.reportId}});assert.deepEqual(stored.closureReview,closureReview);assert.equal(stored.demo,true);
  const completed=['completed','stage_completed','network_ready'].includes(String(values.claimed_outcome));
  if(!completed)assert.equal((await request(`admin/submissions/${stored.id}/review`,{decision:'approved',note:''},undefined,admin.cookie)).status,422);
  const decision=await request(`admin/submissions/${stored.id}/review`,{decision:completed?'approved':'follow_up',note:completed?'Synthetic stage-specific verification.':`Synthetic handoff: ${values.next_owner}; ${values.next_action}`},undefined,admin.cookie);assert.equal(decision.status,200,JSON.stringify(decision.data));
  assert.equal((await db.workOrder.findUniqueOrThrow({where:{id:job.id}})).status,completed?'completed':'follow_up');
  if(scenario==='S5')assert.notEqual((stored.values as any).service_live,true);
  console.log(`PASS ${scenario}: spoken/text and manual-option source trace, evidence, human-review requirement, context pinning, retry receipt and ${completed?'stage-specific approval':'follow-up enforcement'}.`);
 }
}
main().finally(async()=>{try{if(userId){await db.session.updateMany({where:{userId},data:{revokedAt:new Date()}});await db.user.update({where:{id:userId},data:{disabledAt:new Date()}});}}finally{await db.$disconnect();}}).catch(e=>{console.error(e);process.exitCode=1});
