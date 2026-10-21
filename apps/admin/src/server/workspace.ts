import {db} from '../../../../packages/database';
import {Prisma} from '@prisma/client';
import {boardInputSchema,profileInputSchema,timeEventInputSchema,visitDurations,sha256} from '@field-assist/contracts';
import {canonicalize} from 'json-canonicalize';
import {requirePermission,requireEngineer,publicUser,type Context} from './auth';
import {parse,transaction,audit,pageParams} from './services';
import {ledTeams,workScope,clientScope} from './scopes';
import {ApiError,notFound} from './errors';
type Store=Prisma.TransactionClient;
export async function updateProfile(ctx:Context,input:unknown){
 const {expectedRevision,...data}=parse(profileInputSchema,input);
 return transaction(async tx=>{
  const changed=await tx.user.updateMany({where:{id:ctx.user.id,organizationId:ctx.user.organizationId,...(expectedRevision===undefined?{}:{revision:expectedRevision})},data:{...data,revision:{increment:1}}});
  if(!changed.count)throw new ApiError(409,'STALE_REVISION','Your profile changed. Reload it before saving again.');
  const u=await tx.user.findUniqueOrThrow({where:{id:ctx.user.id}});
  await audit(tx,ctx,'profile.updated',u.id,{changedFields:Object.keys(data)});return publicUser(u);
 });
}
export async function boardScope(ctx:Context,tx:Store=db):Promise<Prisma.JobBoardWhereInput>{
 const org={organizationId:ctx.user.organizationId};
 if(ctx.user.role==='TEAM_LEAD')return {...org,teamId:{in:await ledTeams(ctx,tx)}};
 if(ctx.user.role==='ENGINEER'){const jobs=await tx.workOrder.findMany({where:await workScope(ctx,tx),select:{boardId:true}});return {...org,id:{in:jobs.flatMap(j=>j.boardId?[j.boardId]:[])}};}
 if(ctx.user.role==='SALES')return {...org,clientId:{not:null}};
 return org;
}
export async function listBoards(ctx:Context){
 requirePermission(ctx,'boards.read');const items=await db.jobBoard.findMany({where:await boardScope(ctx),orderBy:[{createdAt:'desc'},{id:'desc'}],take:201});
 return {items:await Promise.all(items.slice(0,200).map(async b=>({...b,team:await db.team.findUnique({where:{id:b.teamId},select:{id:true,name:true}}),client:b.clientId?await db.client.findUnique({where:{id:b.clientId},select:{id:true,name:true}}):null,jobCount:await db.workOrder.count({where:{...await workScope(ctx),boardId:b.id}})}))),limited:items.length>200};
}
export async function createBoard(ctx:Context,input:unknown){
 requirePermission(ctx,'boards.manage');const data=parse(boardInputSchema,input);
 return transaction(async tx=>{
  const team=await tx.team.findFirst({where:{id:data.teamId,organizationId:ctx.user.organizationId,archivedAt:null,...(ctx.user.role==='TEAM_LEAD'?{leadId:ctx.user.id}:{})}});if(!team)throw new ApiError(422,'TEAM_UNAVAILABLE','Choose an active squad you manage.');
  const client=data.clientId?await tx.client.findFirst({where:{id:data.clientId,...await clientScope(ctx,tx),teamId:team.id,status:{not:'paused'}}}):null;
  if(data.clientId&&!client)throw new ApiError(422,'CLIENT_TEAM_MISMATCH','Select a client routed to this squad.');
  if(ctx.user.role==='SALES'&&!client)throw new ApiError(422,'CLIENT_REQUIRED','Sales boards must have a routed client.');
  const board=await tx.jobBoard.create({data:{...data,organizationId:ctx.user.organizationId,createdBy:ctx.user.id}});await audit(tx,ctx,'board.created',board.id,{teamId:team.id});return board;
 });
}
async function timeScope(ctx:Context,tx:Store=db):Promise<Prisma.TimeVisitWhereInput>{
 const org={organizationId:ctx.user.organizationId};
 if(ctx.user.role==='ENGINEER')return {...org,userId:ctx.user.id};
 if(ctx.user.role==='TEAM_LEAD')return {...org,teamId:{in:await ledTeams(ctx,tx)}};
 return org;
}
export async function visitDetails(visit:any,tx:Store=db){
 const events=await tx.timeEvent.findMany({where:{visitId:visit.id},orderBy:{sequence:'asc'}}),user=await tx.user.findUniqueOrThrow({where:{id:visit.userId}}),job=await tx.workOrder.findUniqueOrThrow({where:{id:visit.workOrderId}});
 return {...visit,events,user:{id:user.id,name:user.name,avatarId:user.avatarId},job:{id:job.id,title:job.title,site:job.site},...visitDurations(events),asOf:new Date().toISOString()};
}
export async function listTime(ctx:Context,url:URL){
 requirePermission(ctx,'time.read');const {limit,...pagination}=pageParams(url),jobId=url.searchParams.get('jobId'),userId=url.searchParams.get('userId');
 const where:Prisma.TimeVisitWhereInput={...await timeScope(ctx),...(jobId?{workOrderId:jobId}:{}),...(userId?{AND:[{userId}]}:{})};
 const rows=await db.timeVisit.findMany({where,...pagination,orderBy:[{startedAt:'desc'},{id:'desc'}]}),active=ctx.user.role==='ENGINEER'?await db.timeVisit.findMany({where:{organizationId:ctx.user.organizationId,userId:ctx.user.id,endedAt:null}}):[];
 return {items:await Promise.all(rows.slice(0,limit).map(v=>visitDetails(v))),active:await Promise.all(active.map(v=>visitDetails(v))),total:await db.timeVisit.count({where}),nextCursor:rows.length>limit?rows[limit-1].id:null,asOf:new Date().toISOString()};
}
export async function recordTime(ctx:Context,id:string,input:unknown){
 requireEngineer(ctx);const data=parse(timeEventInputSchema,input),payloadHash=sha256(canonicalize({workOrderId:id,...data}));
 return transaction(async tx=>{
  const prior=await tx.timeEvent.findUnique({where:{userId_requestId:{userId:ctx.user.id,requestId:data.requestId}}});
  if(prior){if(prior.payloadHash!==payloadHash)throw new ApiError(409,'IDEMPOTENCY_CONFLICT','This time action reference has different content.');return visitDetails(await tx.timeVisit.findUniqueOrThrow({where:{id:prior.visitId}}),tx);}
  const occurredAt=new Date(data.occurredAt),now=Date.now();if(occurredAt.getTime()>now+300000||occurredAt.getTime()<now-31*86400000)throw new ApiError(422,'TIME_OUT_OF_RANGE','Check the phone clock. Time actions must be within the last 31 days and cannot be in the future.');
  let visit=await tx.timeVisit.findUnique({where:{id:data.visitId}});
  if(data.action==='check_in'){
   if(visit)throw new ApiError(409,'VISIT_EXISTS','This visit has already started.');
   const job=await tx.workOrder.findFirst({where:{id,organizationId:ctx.user.organizationId,assigneeId:ctx.user.id}});if(!job)notFound();
   if(job.assignmentRevision!==data.assignmentRevision||job.responseStatus!=='accepted'||!['assigned','follow_up'].includes(job.status))throw new ApiError(409,'ASSIGNMENT_CHANGED','Accept the current assignment before checking in.');
   if(await tx.timeVisit.findFirst({where:{userId:ctx.user.id,endedAt:null}}))throw new ApiError(409,'VISIT_ALREADY_ACTIVE','Check out of your current site before starting another visit.');
   visit=await tx.timeVisit.create({data:{id:data.visitId,organizationId:ctx.user.organizationId,userId:ctx.user.id,workOrderId:id,teamId:job.teamId,assignmentRevision:data.assignmentRevision,startedAt:occurredAt,lastOccurredAt:occurredAt,state:'working',sequence:1}});
  }else{
   if(!visit||visit.organizationId!==ctx.user.organizationId||visit.userId!==ctx.user.id||visit.workOrderId!==id)notFound();
   if(visit.assignmentRevision!==data.assignmentRevision||visit.state==='closed'||data.sequence!==visit.sequence+1)throw new ApiError(409,'TIME_SEQUENCE_CONFLICT','Synchronize earlier visit actions first. Closed visits cannot be changed.');
   if(occurredAt<visit.lastOccurredAt)throw new ApiError(422,'CLOCK_MOVED_BACK','This action precedes the previous action. Check the phone clock.');
   if(data.action==='break_start'&&visit.state!=='working'||data.action==='break_end'&&visit.state!=='break')throw new ApiError(409,'TIME_STATE_CONFLICT','Refresh the visit before changing the break state.');
   visit=await tx.timeVisit.update({where:{id:visit.id},data:{state:data.action==='check_out'?'closed':data.action==='break_start'?'break':'working',endedAt:data.action==='check_out'?occurredAt:null,lastOccurredAt:occurredAt,sequence:data.sequence}});
  }
  await tx.timeEvent.create({data:{requestId:data.requestId,visitId:visit.id,organizationId:ctx.user.organizationId,userId:ctx.user.id,sequence:data.sequence,action:data.action,occurredAt,location:data.location as Prisma.InputJsonValue|undefined,note:data.note,payloadHash}});
  await audit(tx,ctx,'visit.'+data.action,visit.id,{workOrderId:id,sequence:data.sequence});return visitDetails(visit,tx);
 });
}
