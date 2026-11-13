import {db} from '../../../../packages/database';
import {visitSummarySchema} from '../../../../packages/contracts/src/visit-summary';
import {sha256} from '@field-assist/contracts';
import {Prisma} from '@prisma/client';
import {requireEngineer,requirePermission,publicUser,type Context} from './auth';
import {ApiError,notFound} from './errors';
import {ledTeams} from './scopes';
async function summaryScope(ctx:Context) {return {organizationId:ctx.user.organizationId,...(ctx.user.role==='ENGINEER'?{userId:ctx.user.id}:ctx.user.role==='TEAM_LEAD'?{teamId:{in:await ledTeams(ctx)}}:{})};}
import {audit,pageParams,parse,transaction} from './services';

export async function submitVisitSummary(ctx:Context,input:unknown) {
  requireEngineer(ctx);
  const body=parse(visitSummarySchema,input), org=ctx.user.organizationId;
  if(new Date(body.confirmedAt).getTime()>Date.now()+60000)throw new ApiError(422,'INVALID_CONFIRMATION','Confirmation time cannot be in the future.');
  const hash=sha256(JSON.stringify(body));
  return transaction(async tx=>{
    const existing=await tx.visitSummary.findUnique({where:{organizationId_clientSummaryId:{organizationId:org,clientSummaryId:body.clientSummaryId}}});
    if(existing){
      if(existing.userId!==ctx.user.id||existing.payloadHash!==hash)throw new ApiError(409,'SUMMARY_CONFLICT','This submission identifier has already been used. Review the edited summary again.');
      return receipt(existing);
    }
    const job=body.workOrderId?await tx.workOrder.findFirst({where:{id:body.workOrderId,organizationId:org,assigneeId:ctx.user.id}}):null;
    if(body.workOrderId&&!job)notFound();
    const row=await tx.visitSummary.create({data:{organizationId:org,userId:ctx.user.id,teamId:job?.teamId??ctx.user.teamId,
      clientSummaryId:body.clientSummaryId,clientReportId:body.clientReportId,workOrderId:body.workOrderId,
      values:body.values as Prisma.InputJsonValue,sources:body.sources as Prisma.InputJsonValue,
      payloadHash:hash,confirmedAt:new Date(body.confirmedAt)}});
    await audit(tx,ctx,'visit_summary.received',row.id,{clientSummaryId:row.clientSummaryId});
    return receipt(row);
  });
}
function receipt(row:{id:string;receivedAt:Date;clientSummaryId:string}) {
  return {id:row.id,clientSummaryId:row.clientSummaryId,receivedAt:row.receivedAt,kind:'visit_summary',operationalClosureApproved:false};
}
export async function listVisitSummaries(ctx:Context,url:URL) {
  requirePermission(ctx,'reports.read');
  const {limit,...pagination}=pageParams(url);
  const rows=await db.visitSummary.findMany({where:await summaryScope(ctx),...pagination,
    orderBy:[{receivedAt:'desc'},{id:'desc'}],omit:{sources:true,payloadHash:true}});
  const items=await Promise.all(rows.slice(0,limit).map(async row=>({...row,kind:'visit_summary',operationalClosureApproved:false,
    engineer:publicUser(await db.user.findUniqueOrThrow({where:{id:row.userId}})),
    workOrder:row.workOrderId?await db.workOrder.findUnique({where:{id:row.workOrderId},select:{title:true,site:true}}):null})));
  return {items,nextCursor:rows.length>limit?items.at(-1)?.id:null};
}
export async function visitSummaryDetail(ctx:Context,id:string) {
  requirePermission(ctx,'reports.read');
  const row=await db.visitSummary.findFirst({where:{id,...await summaryScope(ctx)}});
  if(!row)notFound();
  const {payloadHash:_,...summary}=row;
  return {...summary,kind:'visit_summary',operationalClosureApproved:false,
    engineer:publicUser(await db.user.findUniqueOrThrow({where:{id:row.userId}})),
    workOrder:row.workOrderId?await db.workOrder.findUnique({where:{id:row.workOrderId},select:{title:true,site:true}}):null};
}
