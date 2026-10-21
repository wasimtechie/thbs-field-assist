import 'dotenv/config';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
const org='10000000-0000-4000-8000-000000000001';
async function main(){
 if(process.env.NODE_ENV==='production')throw new Error('Synthetic collaboration provisioning refuses production mode.');
 const administrator=await db.user.findUniqueOrThrow({where:{email:'admin@thbs.com'}}),passwordHash=await hash('123456');
 const staff:any={};for(const [email,name,role,department] of [['lead1@thbs.com','Demo Fibre & Survey Lead','TEAM_LEAD','Field Engineering'],['lead2@thbs.com','Demo Repair & Business Lead','TEAM_LEAD','Field Engineering'],['sales@thbs.com','Demo Sales Coordinator','SALES','Sales']]){
  const existing=await db.user.findUnique({where:{email}});if(existing&&existing.organizationId!==org)throw new Error('A requested demo address belongs to another organisation.');
  staff[email]=existing??await db.user.create({data:{organizationId:org,email,name,role,department,jobTitle:role==='SALES'?'Sales coordinator':'Team lead',passwordHash}});
 }
 const definitions=[['fibre','Fibre Delivery','Fibre Installation','lead1@thbs.com',['fibre1@thbs.com','fibre2@thbs.com']],['repair','Fault Response','Fault Repair','lead2@thbs.com',['repair1@thbs.com','repair2@thbs.com']],['business','Business Connections','Business Services','lead2@thbs.com',['business1@thbs.com','business2@thbs.com']],['survey','Site Planning','Site Survey','lead1@thbs.com',['site-survey@thbs.com']]] as const;
 let jobs=0;
 for(const [slug,name,department,leadEmail,engineers] of definitions){
  const existingTeam=await db.team.findFirst({where:{organizationId:org,name}});
  const team=existingTeam??await db.team.create({data:{organizationId:org,name,department,description:'Synthetic THBS demonstration squad.',leadId:staff[leadEmail].id}});
  await db.conversation.upsert({where:{teamId:team.id},create:{organizationId:org,teamId:team.id,kind:'team'},update:{}});
  if(!existingTeam){for(const email of [...engineers,leadEmail]){const u=await db.user.findUniqueOrThrow({where:{email}});if(!u.teamId)await db.user.update({where:{id:u.id},data:{teamId:team.id,revision:{increment:1}}});}}
  const clientName=`Demo · ${name==='Fibre Delivery'?'Orion Broadband':name==='Fault Response'?'City Network':name==='Business Connections'?'Nexus Business Park':'Future Sites'}`;
  const existingClient=await db.client.findFirst({where:{organizationId:org,name:clientName}});const client=existingClient??await db.client.create({data:{organizationId:org,name:clientName,contactName:'Synthetic demo contact',address:'Synthetic demonstration site · Bengaluru',notes:'Synthetic client for THBS showcase. No real customer contact details.',teamId:team.id,createdBy:staff['sales@thbs.com'].id}});
  for(const email of engineers){const u=await db.user.findUniqueOrThrow({where:{email}}),type=await db.engineerType.findFirstOrThrow({where:{organizationId:org,slug}}),title=`Demo · ${client.name.replace('Demo · ','')} site visit`;
   if(!await db.workOrder.findFirst({where:{organizationId:org,clientId:client.id,assigneeId:u.id,title}})){
    const job=await db.workOrder.create({data:{organizationId:org,clientId:client.id,teamId:team.id,assigneeId:u.id,typeId:type.id,title,site:client.address,instructions:'Synthetic THBS demo only. Review the brief, accept or decline with a reason, message your lead if needed, and capture your report.',assetReference:`DEMO-${slug.toUpperCase()}-${email.split('@')[0]}`,priority:'high',dueAt:new Date(Date.now()+48*3600000),createdBy:staff['sales@thbs.com'].id}});
    await db.notification.create({data:{organizationId:org,userId:u.id,kind:'job.assigned',resourceId:job.id,title:'New client visit assigned',body:`${client.name} · ${team.name}`,deliveryKey:`job:${job.id}:1`}});jobs++;
   }
  }
 }
 await db.auditEvent.create({data:{organizationId:org,actorId:administrator.id,action:'collaboration.demo_prepared',entityId:org,metadata:{newJobs:jobs,synthetic:true}}});
 console.log(`Collaboration demo ready: two team leads, one Sales account, four squads and clients, ${jobs} new pending visits. Existing credentials/details preserved. New demo passwords: 123456.`);
}
main().catch(e=>{console.error(e.message);process.exitCode=1;}).finally(()=>db.$disconnect());
