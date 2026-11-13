import {readFileSync} from 'node:fs';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
import {templateSchema,schemaHash,schemaBytes} from '../packages/contracts/src';
const schema=templateSchema.parse(JSON.parse(readFileSync('fixtures/templates/closure-mvp.json','utf8')));
const org='10000000-0000-4000-8000-000000000001',actor='20000000-0000-4000-8000-000000000001';
async function main(){
 if(process.env.NODE_ENV==='production'||!['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname))throw Error('Use a local development database for synthetic demo seeding.');
 const passwordHash=await hash('123456');
 await db.$transaction(async tx=>{
  await tx.engineerType.upsert({where:{id:schema.engineerTypeId},update:{},create:{id:schema.engineerTypeId,organizationId:org,slug:'closure-mvp',name:'FTTP closure assistant · synthetic MVP',description:'Five versioned question banks; proposed rules require customer validation.'}});
  const policyVersion=schema.closurePolicy!.version;const versionId=policyVersion===1?'50000000-0000-4000-8000-000000000006':`50000000-0000-4000-8006-${String(policyVersion).padStart(12,'0')}`;
  const existing=await tx.templateVersion.findUnique({where:{id:versionId}});if(existing&&existing.schemaHash!==schemaHash(schema))throw Error('Published policy differs. Create a new version; never overwrite it.');
  const priorTemplate=await tx.template.findUnique({where:{id:schema.templateId}});
  const priorPublished=priorTemplate?.currentPublishedVersionId?await tx.templateVersion.findUnique({where:{id:priorTemplate.currentPublishedVersionId}}):null;
  await tx.template.upsert({where:{id:schema.templateId},update:{},create:{id:schema.templateId,organizationId:org,typeId:schema.engineerTypeId,name:schema.title,currentPublishedVersionId:versionId}});
  await tx.templateDraft.upsert({where:{templateId:schema.templateId},update:{},create:{templateId:schema.templateId,schema,updatedBy:actor}});
  await tx.templateVersion.upsert({where:{id:versionId},update:{},create:{id:versionId,templateId:schema.templateId,organizationId:org,versionNumber:policyVersion,schema,canonicalSchema:schemaBytes(schema),schemaHash:schemaHash(schema),publishedBy:actor}});
  const draft=await tx.templateDraft.findUniqueOrThrow({where:{templateId:schema.templateId}});
  if(priorPublished&&schemaHash(templateSchema.parse(draft.schema))===priorPublished.schemaHash&&priorPublished.schemaHash!==schemaHash(schema))await tx.templateDraft.update({where:{templateId:schema.templateId},data:{schema,revision:{increment:1},updatedBy:actor}});
  await tx.template.update({where:{id:schema.templateId},data:{currentPublishedVersionId:versionId}});
  await tx.templateVersion.updateMany({where:{templateId:schema.templateId,versionNumber:{lt:policyVersion},disabledAt:null},data:{disabledAt:new Date()}});
  await tx.engineerType.update({where:{id:schema.engineerTypeId},data:{defaultTemplateId:schema.templateId}});
  const user=await tx.user.upsert({where:{email:'closure@fieldassist.demo'},update:{},create:{organizationId:org,email:'closure@fieldassist.demo',name:'Alex · Closure MVP',role:'ENGINEER',passwordHash,department:'Field Engineering',jobTitle:'Synthetic closure demonstration',baseLocation:'Bristol · fictional sites'}});
  if(!await tx.engineerAssignment.findFirst({where:{userId:user.id,validTo:null}}))await tx.engineerAssignment.create({data:{userId:user.id,typeId:schema.engineerTypeId,revision:1}});
  const jobs=[
   ['S1','final_provision','Standard FTTP provision','Existing serving terminal and apparently usable route. Verify identity, permission, equipment, optical result and operational status. Do not infer a pass from the optical number.'],
   ['S2','final_provision','Blocked underground duct','Record the obstruction section, measured location, safe site handover and named civils dependency. A blocked visit does not mean the customer service is live.'],
   ['S3','final_provision','Missing / incorrect CBT','Compare expected and observed asset records. Record not found explicitly when appropriate. An alternative terminal requires explicit authorisation.'],
   ['S4','final_provision','ONT fitted · service inactive','Distinguish an incomplete external connection, optical failure and provider activation failure. Preserve partial work and a named technical referral.'],
   ['S5','survey','Remote build · survey stage','Close only the assigned survey stage. Record route, consent dependencies and a downstream owner. Construction and final service remain separate work orders.'],
   ['S5','civils','Remote build · civils stage','Review design, permissions, reinstatement, as-built evidence and downstream acceptance. Civils completion does not mean fibre is tested or customer service is live.'],
   ['S5','network_acceptance','Remote build · network readiness','Verify prior stage acceptance, terminal mapping, test/as-built evidence and accepted handoff. Network readiness is separate from final provision.'],
  ];
  for(const [index,[scenario,workStage,title,instructions]] of jobs.entries())await tx.workOrder.upsert({where:{id:`80000000-0000-4000-8006-${String(index+1).padStart(12,'0')}`},update:{},create:{id:`80000000-0000-4000-8006-${String(index+1).padStart(12,'0')}`,organizationId:org,assigneeId:user.id,typeId:schema.engineerTypeId,createdBy:actor,title:`${scenario} · ${title}`,site:`Fictional demo property ${index+1} · Bristol, UK`,assetReference:`DEMO-CLOSURE-${index+1}`,instructions:`SYNTHETIC DEMO. No live customer, network, measurements or approved working procedure.\n${instructions}`,closureContext:{scenario,workStage},priority:'normal',dueAt:new Date(Date.now()+86400000),responseStatus:'accepted',respondedAt:new Date()}});
 });
 console.log('Closure MVP prepared: closure@fieldassist.demo / 123456. Seven assignments cover five scenarios and three remote-build stages. Existing accounts and jobs preserved.');
}
main().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>db.$disconnect());
