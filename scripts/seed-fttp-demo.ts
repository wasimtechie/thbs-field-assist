import {readFileSync} from 'node:fs';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
import {templateSchema,schemaHash,schemaBytes} from '../packages/contracts/src';
const org='10000000-0000-4000-8000-000000000001',actor='20000000-0000-4000-8000-000000000001';
const schema=templateSchema.parse(JSON.parse(readFileSync('fixtures/templates/fttp-demo.json','utf8')));
async function main(){
 if(process.env.NODE_ENV==='production'||!['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname))throw Error('FTTP demo seeding requires a local development database.');
 const passwordHash=await hash('123456');
 await db.$transaction(async tx=>{
 await tx.engineerType.upsert({where:{id:schema.engineerTypeId},update:{},create:{id:schema.engineerTypeId,organizationId:org,slug:'fttp-demo',name:'FTTP installation · demo',description:'Synthetic UK service-delivery demonstration; procedures require customer validation.'}});
 const versionId='50000000-0000-4000-8000-000000000005';
 await tx.template.upsert({where:{id:schema.templateId},update:{},create:{id:schema.templateId,organizationId:org,typeId:schema.engineerTypeId,name:schema.title,currentPublishedVersionId:versionId}});
 await tx.templateDraft.upsert({where:{templateId:schema.templateId},update:{},create:{templateId:schema.templateId,schema,updatedBy:actor}});
 await tx.templateVersion.upsert({where:{id:versionId},update:{},create:{id:versionId,templateId:schema.templateId,organizationId:org,versionNumber:1,schema,canonicalSchema:schemaBytes(schema),schemaHash:schemaHash(schema),publishedBy:actor}});
 await tx.engineerType.update({where:{id:schema.engineerTypeId},data:{defaultTemplateId:schema.templateId}});
 const user=await tx.user.upsert({where:{email:'fttp@fieldassist.demo'},update:{},create:{organizationId:org,email:'fttp@fieldassist.demo',name:'Alex · FTTP demo',role:'ENGINEER',passwordHash,department:'Field Engineering',jobTitle:'FTTP demonstration engineer',baseLocation:'Bristol · synthetic workspace'}});
 if(!await tx.engineerAssignment.findFirst({where:{userId:user.id,validTo:null}}))await tx.engineerAssignment.create({data:{userId:user.id,typeId:schema.engineerTypeId,revision:1}});
 for(const [i,title,instructions] of [
 [1,'FTTP-101 · New fibre installation','SYNTHETIC DEMO · No live customer or network.\nAppointment: 09:00–13:00, demo date.\nAccess: Customer contact confirmed; side gate available.\nRoute: Overhead entry to external CSP; agree final internal route on arrival.\nAsset references: DEMO-CBT-017 / port 4; DEMO-CSP-101.\nPrevious visit: Synthetic survey identified a suitable entry point; no live survey performed.\nEquipment: ONT, fibre lead, label scanner, approved test instrument and usual site equipment.\nComplete arrival checks, installation, tests and customer handover. Attach before, installation and test evidence.'],
 [2,'FTTP-102 · Duct obstruction follow-up','SYNTHETIC DEMO · No live customer or network.\nAppointment: 13:00–17:00, demo date.\nAccess: Driveway available; arrange customer access for return visit.\nAsset references: DEMO-DUCT-102 / DEMO-CSP-102.\nPrevious visit: Synthetic survey notes a suspected duct obstruction.\nEquipment: Approved inspection equipment and standard site kit.\nIf work cannot proceed, choose Unable to complete. Record obstruction, attach blocker evidence, select Civils coordination and give a clear next action. Do not mark the installation complete.']
 ] as const){const id=`80000000-0000-4000-8005-${String(i).padStart(12,'0')}`;await tx.workOrder.upsert({where:{id},update:{},create:{id,organizationId:org,assigneeId:user.id,typeId:schema.engineerTypeId,createdBy:actor,title,site:`Demo property ${i} · Bristol, UK (fictional)`,instructions,assetReference:`DEMO-CSP-10${i}`,priority:i===1?'high':'normal',dueAt:new Date(Date.now()+i*3600000),responseStatus:'accepted',respondedAt:new Date()}});}
 });
 console.log('FTTP demo ready. Engineer: fttp@fieldassist.demo / 123456. Supervisor: admin@thbs.com / 123456. Existing accounts, drafts and jobs preserved.');
}
main().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>db.$disconnect());
