import {db} from '../../../../packages/database';
import {hash} from '@node-rs/argon2';
import {Prisma} from '@prisma/client';
import {accountCreateSchema,accountPatchSchema} from '@field-assist/contracts';
import {requirePermission,publicUser,type Context} from './auth';
import {parse,transaction,audit,pageParams} from './services';
import {ApiError,notFound} from './errors';
import {z} from 'zod';

async function accountDetails(u:any){const assignment=await db.engineerAssignment.findFirst({where:{userId:u.id,validTo:null},orderBy:{revision:'desc'}});return {...publicUser(u),team:u.teamId?await db.team.findUnique({where:{id:u.teamId}}):null,createdAt:u.createdAt,type:assignment?await db.engineerType.findUnique({where:{id:assignment.typeId}}):null};}
export async function listAccounts(ctx:Context,url:URL){
 requirePermission(ctx,'accounts.manage');const {limit,...pagination}=pageParams(url),kind=url.searchParams.get('kind'),status=url.searchParams.get('status')??'current',search=(url.searchParams.get('search')??'').trim().slice(0,180);
 if(kind&&!['engineer','employee'].includes(kind)||!['current','active','paused','removed','all'].includes(status))throw new ApiError(400,'INVALID_FILTER','Select an account kind and status.');
 const where:Prisma.UserWhereInput={organizationId:ctx.user.organizationId,...(kind?{role:kind==='engineer'?'ENGINEER':{not:'ENGINEER'}}:{}),...(status==='removed'?{removedAt:{not:null}}:status==='all'?{}:{removedAt:null,...(status==='active'?{disabledAt:null}:status==='paused'?{disabledAt:{not:null}}:{})}),...(search?{OR:['name','email','employeeCode','department'].map(key=>({[key]:{contains:search,mode:'insensitive'}}))}:{})};
 const [rows,total]=await Promise.all([db.user.findMany({where,...pagination,orderBy:[{createdAt:'desc'},{id:'desc'}]}),db.user.count({where})]);
 return {items:await Promise.all(rows.slice(0,limit).map(accountDetails)),total,nextCursor:rows.length>limit?rows[limit-1].id:null};
}
async function validateTeam(tx:Prisma.TransactionClient,org:string,teamId?:string|null){if(teamId&&!await tx.team.findFirst({where:{id:teamId,organizationId:org,archivedAt:null}}))throw new ApiError(422,'TEAM_UNAVAILABLE','Choose an active team in this organisation.');}
async function ensureUnique(tx:Prisma.TransactionClient,org:string,email?:string,code?:string,id?:string){
 if(email&&await tx.user.findFirst({where:{email,...(id?{id:{not:id}}:{})}}))throw new ApiError(409,'EMAIL_UNAVAILABLE','This email is already in use.');
 if(code&&await tx.user.findFirst({where:{organizationId:org,employeeCode:code,...(id?{id:{not:id}}:{})}}))throw new ApiError(409,'EMPLOYEE_CODE_UNAVAILABLE','This employee ID is already in use.');
}
async function setAssignment(tx:Prisma.TransactionClient,userId:string,org:string,role:string,typeId?:string){
 const latest=await tx.engineerAssignment.findFirst({where:{userId},orderBy:{revision:'desc'}});
 if(role!=='ENGINEER'){if(typeId)throw new ApiError(422,'INVALID_TYPE','IT employees use a dashboard role, not an engineer type.');await tx.engineerAssignment.updateMany({where:{userId,validTo:null},data:{validTo:new Date()}});return;}
 const target=typeId??(latest?.validTo===null?latest.typeId:undefined);
 if(!target)throw new ApiError(422,'TYPE_REQUIRED','Choose an engineer type.');
 const type=await tx.engineerType.findFirst({where:{id:target,organizationId:org,archivedAt:null}});if(!type)throw new ApiError(422,'TYPE_UNAVAILABLE','Select an active engineer type in this workspace.');
 if(latest?.validTo===null&&latest.typeId===target)return;
 await tx.engineerAssignment.updateMany({where:{userId,validTo:null},data:{validTo:new Date()}});
 await tx.engineerAssignment.create({data:{userId,typeId:target,revision:(latest?.revision??0)+1}});
}
export async function createAccount(ctx:Context,input:unknown){
 requirePermission(ctx,'accounts.manage');const data=parse(accountCreateSchema,input),passwordHash=await hash(data.initialPassword);
 return transaction(async tx=>{
  await ensureUnique(tx,ctx.user.organizationId,data.email,data.employeeCode);
  await validateTeam(tx,ctx.user.organizationId,data.teamId);
  const {typeId,initialPassword,...fields}=data;
  const user=await tx.user.create({data:{...fields,passwordHash,organizationId:ctx.user.organizationId}});
  await setAssignment(tx,user.id,user.organizationId,user.role,typeId);
  await audit(tx,ctx,'account.created',user.id,{role:user.role});return publicUser(user);
 });
}
export async function updateAccount(ctx:Context,id:string,input:unknown){
 requirePermission(ctx,'accounts.manage');const data=parse(accountPatchSchema,input),passwordHash=data.newPassword?await hash(data.newPassword):undefined;
 return transaction(async tx=>{
  const current=await tx.user.findFirst({where:{id,organizationId:ctx.user.organizationId}});if(!current)notFound();
  if(current.revision!==data.expectedRevision)throw new ApiError(409,'STALE_REVISION','This account changed. Reload before saving.');
  const role=data.role??current.role;
  const losingAdmin=current.role==='ADMIN'&&!current.disabledAt&&!current.removedAt&&(role!=='ADMIN'||data.status==='paused'||data.status==='removed');
  if(id===ctx.user.id&&(role!==current.role||data.status==='paused'||data.status==='removed'))throw new ApiError(409,'SELF_ACCESS_PROTECTED','You cannot pause, remove or change your own access level.');
  if(losingAdmin&&await tx.user.count({where:{organizationId:current.organizationId,role:'ADMIN',disabledAt:null,removedAt:null}})<=1)throw new ApiError(409,'LAST_ADMIN_PROTECTED','Keep at least one active administrator.');
  if(role!==current.role&&await tx.workOrder.count({where:{assigneeId:id,status:{in:['assigned','follow_up','submitted']}}}))throw new ApiError(409,'ACTIVE_JOBS','Reassign or finish this engineer’s open jobs before changing their account kind.');
  await ensureUnique(tx,current.organizationId,data.email,data.employeeCode,id);
  await validateTeam(tx,current.organizationId,data.teamId);
  if(role!==current.role&&!['ADMIN','OPERATIONS_MANAGER','TEAM_LEAD'].includes(role)&&await tx.team.count({where:{leadId:id,archivedAt:null}}))throw new ApiError(409,'TEAM_LEAD_IN_USE','Assign another lead to this person’s teams before changing their role.');
  const {expectedRevision,newPassword,typeId,status,...fields}=data;
  if(typeId||role!==current.role||status==='active'&&current.removedAt)await setAssignment(tx,id,current.organizationId,role,typeId);
  const changed=await tx.user.updateMany({where:{id,revision:expectedRevision},data:{...fields,passwordHash,...(status?{disabledAt:status==='active'?null:new Date(),removedAt:status==='removed'?new Date():status==='active'?null:current.removedAt}:{}),revision:{increment:1}}});
  if(!changed.count)throw new ApiError(409,'STALE_REVISION','This account changed. Reload before saving.');
  const credentialChange=!!passwordHash||data.email!==undefined&&data.email!==current.email||role!==current.role;
  if(credentialChange||status==='paused'||status==='removed')await tx.session.updateMany({where:{userId:id,revokedAt:null},data:{revokedAt:new Date()}});
  await audit(tx,ctx,status==='removed'?'account.removed':status==='paused'?'account.paused':status==='active'?'account.reactivated':'account.updated',id,{role,changedFields:Object.keys(data).filter(k=>!['newPassword','expectedRevision'].includes(k)),passwordReset:!!passwordHash});
  return publicUser(await tx.user.findUniqueOrThrow({where:{id}}));
 });
}
export async function removeAccount(ctx:Context,id:string,input:unknown){
 const data=parse(z.object({expectedRevision:z.number().int().min(1)}).strict(),input);
 return updateAccount(ctx,id,{...data,status:'removed'});
}
