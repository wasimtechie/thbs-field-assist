import {db} from '../../../../packages/database';
import {sha256} from '@field-assist/contracts';
import {customerJobStatusInputSchema,customerTime,customerVisitWindow} from '../../../../packages/contracts/src/customer-jobs';
import {type Context,requirePermission} from './auth';
import {workScope} from './scopes';
import {audit,parse,transaction} from './services';
import {ApiError,notFound} from './errors';
import {z} from 'zod';

export async function saveCustomerJobStatus(ctx:Context,workOrderId:string,input:unknown) {
  requirePermission(ctx,'work_orders.manage');
  const {expectedRevision,...data}=parse(customerJobStatusInputSchema,input);
  return transaction(async tx => {
    const job=await tx.workOrder.findFirst({where:{id:workOrderId,...await workScope(ctx,tx)}});
    if(!job)notFound();
    const current=await tx.customerJobStatus.findUnique({where:{workOrderId}});
    if((current?.revision??0)!==expectedRevision)throw new ApiError(409,'STALE_REVISION','Customer details changed. Reload before saving.');
    const fields={...data,appointmentStartAt:data.appointmentStartAt?new Date(data.appointmentStartAt):null,
      appointmentEndAt:data.appointmentEndAt?new Date(data.appointmentEndAt):null,
      activationAt:data.activationAt?new Date(data.activationAt):null,updatedBy:ctx.user.id};
    const row=current
      ? await tx.customerJobStatus.update({where:{workOrderId,revision:expectedRevision},data:{...fields,revision:{increment:1}}})
      : await tx.customerJobStatus.create({data:{...fields,workOrderId,organizationId:ctx.user.organizationId}});
    await audit(tx,ctx,'customer_job_status.updated',workOrderId,{revision:row.revision});
    return row;
  });
}

export async function readChatmCustomerJobs(request:Request,email:string) {
  const token=request.headers.get('authorization')?.match(/^Bearer (fa_chatm_[A-Za-z0-9_-]{43})$/)?.[1];
  if(!token)throw new ApiError(401,'CONNECTION_REQUIRED','A read-only backend connection is required.');
  const key=await db.chatmConnectionKey.findUnique({where:{tokenHash:sha256(token)}});
  if(!key||key.revokedAt)throw new ApiError(401,'CONNECTION_REQUIRED','The backend connection is unavailable.');
  const parsed=z.email().max(254).safeParse(email.toLowerCase().trim());
  if(!parsed.success)throw new ApiError(400,'INVALID_INPUT','Use a verified customer email.');
  const links=await db.customerJobStatus.findMany({where:{organizationId:key.organizationId,customerEmail:parsed.data},select:{workOrderId:true},take:101});
  // Never imply a complete account picture when a bounded response is truncated.
  const ids=links.slice(0,100).map(v=>v.workOrderId);
  const jobs=await db.workOrder.findMany({where:{organizationId:key.organizationId,id:{in:ids}},orderBy:[{updatedAt:'desc'},{id:'desc'}],take:21,
    select:{id:true,title:true,site:true,status:true,responseStatus:true,updatedAt:true}});
  const authorizations:{workOrderId:string;revision:number}[]=[];
  const items=await Promise.all(jobs.slice(0,20).map(async job => {
    const [status,summary]=await Promise.all([
      db.customerJobStatus.findFirst({where:{workOrderId:job.id,organizationId:key.organizationId,customerEmail:parsed.data}}),
      db.visitSummary.findFirst({where:{workOrderId:job.id,organizationId:key.organizationId},orderBy:[{confirmedAt:'desc'},{receivedAt:'desc'},{id:'desc'}],
        select:{id:true,values:true,confirmedAt:true,receivedAt:true}}),
    ]);
    if(!status)return null;
    authorizations.push({workOrderId:job.id,revision:status.revision});
    const v=summary?.values as Record<string,unknown>|undefined;
    return {reference:job.id,title:job.title,site:job.site,status:job.status,engineerAccepted:job.responseStatus==='accepted',
      appointment:status.appointmentStartAt?{startAt:status.appointmentStartAt,endAt:status.appointmentEndAt,timeZone:status.appointmentTimezone,displayWindow:customerVisitWindow(status.appointmentStartAt,status.appointmentEndAt,status.appointmentTimezone)}:null,
      activation:{status:status.activationStatus,at:status.activationAt,displayAt:status.activationAt?`${customerTime(status.activationAt,status.appointmentTimezone)} (${status.appointmentTimezone})`:null,note:status.activationNote},
      latestVisit:summary?{receiptId:summary.id,confirmedAt:summary.confirmedAt,receivedAt:summary.receivedAt,
        workDone:v?.actual_work??'',outcome:v?.claimed_outcome??'',assetReference:v?.serving_asset??null,
        opticalRxDbm:v?.optical_rx_dbm??null,testResult:v?.operational_test??null,nextAction:v?.next_action??null}:null,
      updatedAt:new Date(Math.max(job.updatedAt.getTime(),status.updatedAt.getTime(),summary?.receivedAt.getTime()??0)),
    };
  }));
  // Revoke or change customer linkage while a read is in flight: fail closed.
  const current=await db.chatmConnectionKey.findUnique({where:{id:key.id}});
  if(!current||current.revokedAt)throw new ApiError(401,'CONNECTION_REQUIRED','The backend connection is unavailable.');
  const stillLinked=await db.customerJobStatus.findMany({where:{organizationId:key.organizationId,customerEmail:parsed.data,workOrderId:{in:authorizations.map(v=>v.workOrderId)}},select:{workOrderId:true,revision:true}});
  if(stillLinked.length!==authorizations.length||authorizations.some(v=>!stillLinked.some(w=>w.workOrderId===v.workOrderId&&w.revision===v.revision)))
    throw new ApiError(409,'CUSTOMER_LINK_CHANGED','Customer job details changed. Try again.');
  const selected=items.filter(v=>v!==null);
  const result={customerEmail:parsed.data,checkedAt:new Date().toISOString(),truncated:links.length>100||jobs.length>20,jobs:selected};
  while(Buffer.byteLength(JSON.stringify(result))>60000 && result.jobs.length){result.jobs.pop();result.truncated=true;}
  return result;
}
