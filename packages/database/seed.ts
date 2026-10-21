import {db} from './index';
import {hash} from '@node-rs/argon2';
import {readFileSync,readdirSync} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {seedThbsAccounts} from './thbs-demo-accounts';
import {schemaHash,schemaBytes,templateSchema} from '../contracts/src';
const organizationId='10000000-0000-4000-8000-000000000001';
const adminId='20000000-0000-4000-8000-000000000001';
const adminPassword=process.env.SEED_ADMIN_PASSWORD,engineerPassword=process.env.SEED_ENGINEER_PASSWORD;
if(!adminPassword||!engineerPassword)throw new Error('Run npm run setup before seeding.');
async function main(){
  await db.organization.upsert({where:{id:organizationId},update:{},create:{id:organizationId,name:'Field Assist · Demo workspace'}});
  const adminHash=await hash(adminPassword!);const engineerHash=await hash(engineerPassword!);
  await db.user.upsert({where:{email:'admin@fieldassist.demo'},update:{},create:{id:adminId,organizationId,email:'admin@fieldassist.demo',name:'Alex Morgan',passwordHash:adminHash,role:'ADMIN'}});
  const types=[['fibre','Fibre installation','Sam Taylor','Connect homes. Complete every detail.'],['repair','Fault repair','Jordan Ellis','Restore service with a clear record.'],['business','Business circuits','Casey Patel','Document business connections.'],['survey','Site survey','Riley Morgan','Capture what the next team needs.']];
  for(const [i,[slug,name,engineer,description]] of types.entries()){
    const n=String(i+1).padStart(12,'0');const typeId=`30000000-0000-4000-8000-${n}`;const userId=`20000000-0000-4000-8001-${n}`;
    const fixture=JSON.parse(readFileSync(path.resolve(`fixtures/templates/${slug==='fibre'?'fibre-cable-label':slug}.json`),'utf8'));const schema=templateSchema.parse(fixture);
    await db.$transaction(async tx=>{
      await tx.engineerType.upsert({where:{id:typeId},update:{},create:{id:typeId,organizationId,slug,name,description}});
      await tx.user.upsert({where:{email:`${slug}@fieldassist.demo`},update:{},create:{id:userId,organizationId,email:`${slug}@fieldassist.demo`,name:engineer,passwordHash:engineerHash,role:'ENGINEER'}});
      const assignment=await tx.engineerAssignment.findFirst({where:{userId}});
      if(!assignment)await tx.engineerAssignment.create({data:{userId,typeId,revision:1}});
      const existing=await tx.template.findUnique({where:{id:schema.templateId}});
      if(!existing){
        const versionId=`50000000-0000-4000-8000-${n}`;
        await tx.template.create({data:{id:schema.templateId,organizationId,typeId,name:schema.title,currentPublishedVersionId:versionId}});
        await tx.templateDraft.create({data:{templateId:schema.templateId,schema,updatedBy:adminId}});
        await tx.templateVersion.create({data:{id:versionId,templateId:schema.templateId,organizationId,versionNumber:1,schema,canonicalSchema:schemaBytes(schema),schemaHash:schemaHash(schema),publishedBy:adminId}});
        await tx.engineerType.update({where:{id:typeId},data:{defaultTemplateId:schema.templateId}});
      }
    });
  }
  await seedThbsAccounts();
  const demoEngineers=await db.user.findMany({where:{organizationId,role:'ENGINEER',disabledAt:null,removedAt:null}});
  for(const engineer of demoEngineers){
    const assignment=await db.engineerAssignment.findFirst({where:{userId:engineer.id,validTo:null},orderBy:{revision:'desc'}});if(!assignment)continue;
    for(let visit=0;visit<2;visit++){
      const h=createHash('sha256').update(`thbs-demo-job:${engineer.id}:${visit}`).digest('hex');
      const id=`${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-a${h.slice(17,20)}-${h.slice(20,32)}`;
      await db.workOrder.upsert({where:{id},update:{},create:{id,organizationId,assigneeId:engineer.id,typeId:assignment.typeId,createdBy:adminId,
        title:visit===0?'Demo · Site readiness and cable inspection':'Demo · Follow-on connection visit',site:'Synthetic demo site · Bengaluru',
        instructions:'Synthetic demonstration only. Capture the printed label, record the work outcome and confirm the report for supervisor review.',
        assetReference:`DEMO-${engineer.id.slice(-6)}`,priority:visit===0?'high':'normal',dueAt:new Date(Date.now()+(visit===0?-12:24)*3600000)}});
    }
  }
  console.log('Seed complete: demo accounts, published templates and two synthetic assignments per active engineer. Existing work preserved.');
}
main().finally(()=>db.$disconnect());
