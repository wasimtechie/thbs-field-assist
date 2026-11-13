import {FTTP_TEMPLATE_ID,CLOSURE_TEMPLATE_ID} from '@field-assist/contracts';
import {db} from '../../../../packages/database';
import {Prisma} from '@prisma/client';
import {workOrderInputSchema,reviewInputSchema,workOrderStatuses,workOrderPriorities,jobIsOverdue,hasPermission} from '@field-assist/contracts';
import {parse,transaction,audit,pageParams} from './services';
import {requirePermission,requireEngineer,publicUser,type Context} from './auth';
import {ApiError,notFound} from './errors';
import {z} from 'zod';
import {workScope,reportScope,engineerScope,ledTeams,clientScope} from './scopes';
import {notify} from './collaboration';
import {boardScope} from './workspace';

const details=async(job:any)=>({...job,customerStatus:await db.customerJobStatus.findUnique({where:{workOrderId:job.id}}),assignedBy:publicUser(await db.user.findUniqueOrThrow({where:{id:job.assignedById??job.createdBy}})),board:job.boardId?await db.jobBoard.findUnique({where:{id:job.boardId},select:{id:true,name:true}}):null,latestReportOwnerId:job.latestReportId?(await db.report.findUnique({where:{id:job.latestReportId},select:{userId:true}}))?.userId:null,assignee:publicUser(await db.user.findUniqueOrThrow({where:{id:job.assigneeId}})),client:job.clientId?await db.client.findUnique({where:{id:job.clientId},select:{id:true,name:true,teamId:true}}):null,team:job.teamId?await db.team.findUnique({where:{id:job.teamId},select:{id:true,name:true,leadId:true}}):null,responses:await db.assignmentResponse.findMany({where:{workOrderId:job.id},orderBy:{respondedAt:'desc'}}),latestReview:job.latestReportId?await db.reportReview.findUnique({where:{reportId:job.latestReportId}}):null});
export async function listWorkOrders(ctx:Context,url:URL){
  requirePermission(ctx,'work_orders.read');const {limit,...pagination}=pageParams(url);
  const boardId=url.searchParams.get('boardId');const response=url.searchParams.get('response'),clientId=url.searchParams.get('clientId'),jobId=url.searchParams.get('jobId');if(response&&!['pending','accepted','declined'].includes(response))throw new ApiError(400,'INVALID_FILTER','Choose an assignment response.');
  const status=url.searchParams.get('status'),priority=url.searchParams.get('priority'),search=(url.searchParams.get('search')??'').trim().slice(0,180);
  if(status&&!workOrderStatuses.includes(status as any)||priority&&!workOrderPriorities.includes(priority as any))throw new ApiError(400,'INVALID_FILTER','Choose a supported status and priority.');
  const where:Prisma.WorkOrderWhereInput={AND:[await workScope(ctx),...(url.searchParams.get('overdue')==='true'?[{status:{in:['assigned','follow_up']}},{dueAt:{lt:new Date()}}]:[])],organizationId:ctx.user.organizationId,...(response?{responseStatus:response}:{}),...(boardId?{boardId}:{}),...(clientId?{clientId}:{}),...(jobId?{id:jobId}:{}),...(status?{status}:{}),...(priority?{priority}:{}),...(search?{OR:['title','site','assetReference'].map(key=>({[key]:{contains:search,mode:'insensitive'}}))}:{})};
  const [rows,total]=await Promise.all([db.workOrder.findMany({where,...pagination,orderBy:[{createdAt:'desc'},{id:'desc'}]}),db.workOrder.count({where})]);
  return {items:await Promise.all(rows.slice(0,limit).map(details)),total,nextCursor:rows.length>limit?rows[limit-1].id:null};
}
export async function saveWorkOrder(ctx:Context,input:unknown,id?:string){
  requirePermission(ctx,'work_orders.manage');
  const data=parse(id?workOrderInputSchema.extend({expectedRevision:z.number().int().min(1)}):workOrderInputSchema,input);
  return transaction(async tx=>{
    const assignee=await tx.user.findFirst({where:{id:data.assigneeId,...await engineerScope(ctx,tx),disabledAt:null}});
    if(!assignee)throw new ApiError(422,'ASSIGNEE_UNAVAILABLE','Select an active engineer in this workspace.');
    const assignment=await tx.engineerAssignment.findFirst({where:{userId:assignee.id,validTo:null},orderBy:{revision:'desc'}});
    const type=assignment?await tx.engineerType.findFirst({where:{id:assignment.typeId,organizationId:ctx.user.organizationId,archivedAt:null}}):null;
    const template=type?.defaultTemplateId?await tx.template.findFirst({where:{id:type.defaultTemplateId,archivedAt:null,currentPublishedVersionId:{not:null}}}):null;
    if(!type||!template)throw new ApiError(422,'NO_ASSIGNED_FORM','The engineer needs an active type with a published default form.');
    const client=data.clientId?await tx.client.findFirst({where:{id:data.clientId,...await clientScope(ctx,tx),status:{not:'paused'}}}):null;
    if(data.clientId&&!client)throw new ApiError(422,'CLIENT_UNAVAILABLE','Choose an active or prospective client in this organisation.');
    if(ctx.user.role==='SALES'&&!client)throw new ApiError(422,'CLIENT_REQUIRED','Sales assignments must belong to a client.');
    if(client?.teamId&&client.teamId!==assignee.teamId)throw new ApiError(422,'CLIENT_TEAM_MISMATCH','Choose an engineer in the client’s assigned team, or route the client to the correct team first.');
    if(ctx.user.role==='SALES'&&(!client?.teamId||!assignee.teamId))throw new ApiError(422,'TEAM_REQUIRED','Route the client and engineer to a team before assigning the job.');
    const team=assignee.teamId?await tx.team.findFirst({where:{id:assignee.teamId,organizationId:ctx.user.organizationId,archivedAt:null}}):null;
    if(assignee.teamId&&!team)throw new ApiError(422,'TEAM_UNAVAILABLE','The engineer needs an active team.');
    const board=data.boardId?await tx.jobBoard.findFirst({where:{id:data.boardId,...await boardScope(ctx,tx)}}):null;
    if(data.boardId&&(!board||board.teamId!==team?.id||board.clientId&&board.clientId!==client?.id))throw new ApiError(422,'BOARD_MISMATCH','Choose a board for the assigned squad and client.');
    const fields={boardId:board?.id??null,assignedById:ctx.user.id,title:data.title,site:data.site,instructions:data.instructions,assetReference:data.assetReference,assigneeId:assignee.id,typeId:type.id,teamId:team?.id??null,clientId:client?.id??null,priority:data.priority,dueAt:new Date(data.dueAt)};
    if(id){
      const current=await tx.workOrder.findFirst({where:{id,...await workScope(ctx,tx)}});if(!current)notFound();
      if(await tx.timeVisit.findFirst({where:{workOrderId:id,endedAt:null}}))throw new ApiError(409,'ACTIVE_SITE_VISIT','The engineer must check out before this assignment is changed.');
      if(!['assigned','follow_up'].includes(current.status))throw new ApiError(409,'JOB_LOCKED','Submitted and completed jobs retain their assignment history.');
      // Reassignment can invalidate offline drafts; make the conflict explicit at sync.
      const changed=await tx.workOrder.updateMany({where:{id,revision:(data as any).expectedRevision},data:{...fields,responseStatus:'pending',responseNote:'',respondedAt:null,assignmentRevision:{increment:1},revision:{increment:1}}});
      if(!changed.count)throw new ApiError(409,'STALE_REVISION','This job changed. Reload before editing.');
      const changedJob=await tx.workOrder.findUniqueOrThrow({where:{id}});await notify(tx,ctx.user.organizationId,[assignee.id],'job.updated',id,'Assignment updated',data.title,`job:${id}:${changedJob.assignmentRevision}`);await audit(tx,ctx,'work_order.updated',id);return changedJob;
    }
    const job=await tx.workOrder.create({data:{...fields,organizationId:ctx.user.organizationId,createdBy:ctx.user.id}});
    await notify(tx,ctx.user.organizationId,[assignee.id],'job.assigned',job.id,'New job assigned',data.title,`job:${job.id}:${job.assignmentRevision}`);await audit(tx,ctx,'work_order.assigned',job.id,{assigneeId:job.assigneeId});return job;
  });
}
export async function reviewReport(ctx:Context,id:string,input:unknown){
  requirePermission(ctx,'reports.review');const data=parse(reviewInputSchema,input);
  return transaction(async tx=>{
    const report=await tx.report.findFirst({where:{id,...await reportScope(ctx,tx)}});if(!report)notFound();
    const version=await tx.templateVersion.findUniqueOrThrow({where:{id:report.templateVersionId}});
    if(version.templateId===FTTP_TEMPLATE_ID&&(report.values as Record<string,unknown>).installation_outcome!=='completed'&&data.decision==='approved')throw new ApiError(422,'FTTP_FOLLOW_UP_REQUIRED','This visit did not complete the installation. Request follow-up with the next team and action instead of closing the job.');
    if(version.templateId===CLOSURE_TEMPLATE_ID&&!['completed','stage_completed','network_ready'].includes(String((report.values as Record<string,unknown>).claimed_outcome))&&data.decision==='approved')throw new ApiError(422,'CLOSURE_FOLLOW_UP_REQUIRED','This is a hold, partial or referral. Record the next action as a follow-up.');
    const previous=await tx.reportReview.findUnique({where:{reportId:id}});
    if(previous){if(previous.decision===data.decision&&previous.note===data.note)return previous;throw new ApiError(409,'ALREADY_REVIEWED','This report already has a recorded decision. Follow-up uses a new report.');}
    if(report.workOrderId){
      const job=await tx.workOrder.findFirst({where:{id:report.workOrderId,organizationId:ctx.user.organizationId}});
      if(!job||job.latestReportId!==id||job.status!=='submitted')throw new ApiError(409,'JOB_CHANGED','Review the latest submitted report for this job.');
      await tx.workOrder.update({where:{id:job.id},data:{status:data.decision==='approved'?'completed':'follow_up',reviewNote:data.note,revision:{increment:1}}});
    }
    const review=await tx.reportReview.create({data:{reportId:id,organizationId:ctx.user.organizationId,reviewerId:ctx.user.id,...data}});
    await audit(tx,ctx,`report.${data.decision}`,id,{note:data.note,workOrderId:report.workOrderId});return review;
  });
}
export async function listReviews(ctx:Context,url:URL){
  requirePermission(ctx,'reports.read');const {limit,...pagination}=pageParams(url);
  const raw=url.searchParams.get('status')??'pending';if(!['pending','approved','follow_up'].includes(raw))throw new ApiError(400,'INVALID_FILTER','Choose a review status.');
  const decisions=raw==='pending'?null:raw;
  // NOT EXISTS avoids truncating the review filter to an arbitrary ID list.
  const ids=await db.$queryRaw<{id:string}[]>`SELECT r.id FROM "Report" r WHERE r."organizationId"=${ctx.user.organizationId}::uuid AND (${decisions}::text IS NULL AND NOT EXISTS(SELECT 1 FROM "ReportReview" v WHERE v."reportId"=r.id) OR EXISTS(SELECT 1 FROM "ReportReview" v WHERE v."reportId"=r.id AND v.decision=${decisions})) ORDER BY r."receivedAt" DESC,r.id DESC`;
  const where={...await reportScope(ctx),id:{in:ids.map(r=>r.id)}};
  const reports=await db.report.findMany({where,omit:{evidence:true,closureReview:true},...pagination,orderBy:[{receivedAt:'desc'},{id:'desc'}]});
  return {items:await Promise.all(reports.slice(0,limit).map(async r=>({...r,engineer:publicUser(await db.user.findUniqueOrThrow({where:{id:r.userId}})),workOrder:r.workOrderId?await db.workOrder.findUnique({where:{id:r.workOrderId}}):null,review:await db.reportReview.findUnique({where:{reportId:r.id}})}))),total:await db.report.count({where}),nextCursor:reports.length>limit?reports[limit-1].id:null};
}
export async function mobileOperations(ctx:Context){
  requireEngineer(ctx);const where={organizationId:ctx.user.organizationId,assigneeId:ctx.user.id};
  const jobs=await db.workOrder.findMany({where,orderBy:[{updatedAt:'desc'},{id:'desc'}],take:201});
  // Includes completed work for context, while pending jobs are never dropped by
  // an arbitrary history limit. Large active queues explicitly require online refresh.
  const active=await db.workOrder.findMany({where:{...where,status:{not:'completed'}},orderBy:[{dueAt:'asc'},{id:'asc'}]});
  const items=[...new Map([...active,...jobs.slice(0,200)].map(j=>[j.id,j])).values()];
  const reviews=await db.$queryRaw<any[]>`SELECT v.*,r."clientReportId",r."workOrderId" FROM "ReportReview" v JOIN "Report" r ON r.id=v."reportId" WHERE r."organizationId"=${ctx.user.organizationId}::uuid AND r."userId"=${ctx.user.id}::uuid ORDER BY v."reviewedAt" DESC LIMIT 40`;
  return {workOrders:await Promise.all(items.map(details)),feedback:reviews,syncedAt:new Date().toISOString(),historyLimited:jobs.length>200};
}
export async function operationsSummary(ctx:Context){
 requirePermission(ctx,'work_orders.read');const where=await workScope(ctx),now=new Date(),start=new Date(now);start.setUTCHours(0,0,0,0);start.setUTCDate(start.getUTCDate()-6);
 const jobs=await db.workOrder.findMany({where}),reports=hasPermission(ctx.user.role,'reports.read')?await db.report.findMany({where:await reportScope(ctx),select:{id:true,receivedAt:true}}):[];
 const reviewed=await db.reportReview.findMany({where:{reportId:{in:reports.map(r=>r.id)}},select:{reportId:true}});
 const engineers=ctx.user.role==='ENGINEER'?[ctx.user]:await db.user.findMany({where:{...await engineerScope(ctx),disabledAt:null}});
 const counts=Object.fromEntries(workOrderStatuses.map(s=>[s,jobs.filter(j=>j.status===s).length]));
 return {counts,total:jobs.length,overdue:jobs.filter(j=>jobIsOverdue(j,now)).length,pendingReviews:reports.length-reviewed.length,responses:{pending:jobs.filter(j=>j.responseStatus==='pending').length,accepted:jobs.filter(j=>j.responseStatus==='accepted').length,declined:jobs.filter(j=>j.responseStatus==='declined').length},asOf:now.toISOString(),workload:engineers.map(e=>({id:e.id,name:e.name,open:jobs.filter(j=>j.assigneeId===e.id&&j.status!=='completed').length,overdue:jobs.filter(j=>j.assigneeId===e.id&&jobIsOverdue(j,now)).length})),trend:Array.from({length:7},(_,i)=>{const date=new Date(start);date.setUTCDate(date.getUTCDate()+i);const day=date.toISOString().slice(0,10);return {day,reports:reports.filter(r=>r.receivedAt.toISOString().startsWith(day)).length};})};
}
export async function assetHistory(ctx:Context,url:URL){
  requirePermission(ctx,'assets.read');const search=(url.searchParams.get('search')??'').trim().slice(0,120),asset=url.searchParams.get('asset');
  const groups=await db.workOrder.groupBy({by:['assetReference'],where:{...await workScope(ctx),assetReference:{not:'',...(search?{contains:search,mode:'insensitive' as const}:{})}},_count:true,_max:{updatedAt:true},orderBy:{_max:{updatedAt:'desc'}},take:100});
  const history=asset?await db.workOrder.findMany({where:{...await workScope(ctx),assetReference:asset},orderBy:[{createdAt:'desc'},{id:'desc'}],take:100}):[];
  return {items:groups.map(g=>({reference:g.assetReference,jobs:g._count,lastActivity:g._max.updatedAt})),history:await Promise.all(history.map(async job=>({...await details(job),reportHistory:await Promise.all((await db.report.findMany({where:{...await reportScope(ctx),workOrderId:job.id},orderBy:[{receivedAt:'desc'},{id:'desc'}],select:{id:true,clientReportId:true,receivedAt:true}})).map(async r=>({...r,review:await db.reportReview.findUnique({where:{reportId:r.id}})})))}))),limit:100};
}
