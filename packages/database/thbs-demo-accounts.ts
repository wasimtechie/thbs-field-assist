import {db} from './index';
import {hash} from '@node-rs/argon2';
import {sha256,type AccountRole} from '../contracts/src';
export const thbsAccounts:{email:string;name:string;role:AccountRole;slug?:string;code:string}[]=[
 {email:'fibre1@thbs.com',name:'Fibre Engineer 1',role:'ENGINEER',slug:'fibre',code:'DEMO-FIBRE01'},
 {email:'fibre2@thbs.com',name:'Fibre Engineer 2',role:'ENGINEER',slug:'fibre',code:'DEMO-FIBRE02'},
 {email:'repair1@thbs.com',name:'Fault Repair Engineer 1',role:'ENGINEER',slug:'repair',code:'DEMO-REPAIR01'},
 {email:'repair2@thbs.com',name:'Fault Repair Engineer 2',role:'ENGINEER',slug:'repair',code:'DEMO-REPAIR02'},
 {email:'business1@thbs.com',name:'Business Engineer 1',role:'ENGINEER',slug:'business',code:'DEMO-BUSINESS01'},
 {email:'business2@thbs.com',name:'Business Engineer 2',role:'ENGINEER',slug:'business',code:'DEMO-BUSINESS02'},
 {email:'site-survey@thbs.com',name:'Site Survey Engineer',role:'ENGINEER',slug:'survey',code:'DEMO-SURVEY01'},
 {email:'admin@thbs.com',name:'THBS Administrator',role:'ADMIN',code:'DEMO-ADMIN01'},
 {email:'waseem@thbs.com',name:'Waseem',role:'OPERATIONS_MANAGER',code:'DEMO-OPS01'},
 {email:'test@thbs.com',name:'Test Employee',role:'VIEWER',code:'DEMO-VIEW01'},
];
// This password is explicitly requested for these synthetic local demo accounts.
// Normal repeated seed runs preserve credentials/details edited in the dashboard.
export async function seedThbsAccounts({resetExisting=false}={}){
 const org='10000000-0000-4000-8000-000000000001',actor='20000000-0000-4000-8000-000000000001';
 if(resetExisting&&process.env.NODE_ENV==='production')throw new Error('Demo credential provisioning refuses production mode.');
 const passwordHash=await hash('123456');
 for(const item of thbsAccounts){
  await db.$transaction(async tx=>{
   const existing=await tx.user.findUnique({where:{email:item.email}});
   if(existing&&existing.organizationId!==org)throw new Error('A requested demo email belongs to another workspace.');
   if(existing&&!resetExisting)return;
   if(existing?.role==='ENGINEER'&&item.role!=='ENGINEER'){
    const replacement=await tx.user.findUniqueOrThrow({where:{email:item.email==='waseem@thbs.com'?'fibre1@thbs.com':'fibre2@thbs.com'}});
    await tx.workOrder.updateMany({where:{assigneeId:existing.id,status:{in:['assigned','follow_up','submitted']}},data:{assigneeId:replacement.id,revision:{increment:1}}});
   }
   const fields={name:item.name,role:item.role,passwordHash,employeeCode:existing?.employeeCode||item.code,department:item.role==='ENGINEER'?'Field Engineering':'IT / Operations',jobTitle:item.role==='ENGINEER'?'Demo field engineer':'Demo dashboard employee',disabledAt:null,removedAt:null};
   const user=existing?await tx.user.update({where:{id:existing.id},data:{...fields,revision:{increment:1}}}):await tx.user.create({data:{organizationId:org,email:item.email,...fields}});
   const latest=await tx.engineerAssignment.findFirst({where:{userId:user.id},orderBy:{revision:'desc'}});
   if(item.role==='ENGINEER'){
    const type=await tx.engineerType.findFirstOrThrow({where:{organizationId:org,slug:item.slug!,archivedAt:null}});
    if(latest?.validTo!==null||latest.typeId!==type.id){
     await tx.engineerAssignment.updateMany({where:{userId:user.id,validTo:null},data:{validTo:new Date()}});
     await tx.engineerAssignment.create({data:{userId:user.id,typeId:type.id,revision:(latest?.revision??0)+1}});
    }
   }else await tx.engineerAssignment.updateMany({where:{userId:user.id,validTo:null},data:{validTo:new Date()}});
   if(existing)await tx.session.updateMany({where:{userId:user.id,revokedAt:null},data:{revokedAt:new Date()}});
   await tx.auditEvent.create({data:{organizationId:org,actorId:actor,action:'account.demo_provisioned',entityId:user.id,metadata:{role:item.role,credentialReset:!!existing}}});
   await tx.loginAttempt.deleteMany({where:{key:sha256(item.email)}});
  },{isolationLevel:'Serializable'});
 }
}
