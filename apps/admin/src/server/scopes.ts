import {db} from '../../../../packages/database';
import type {Prisma} from '@prisma/client';
import type {Context} from './auth';
type Store=Prisma.TransactionClient;
export async function ledTeams(ctx:Context,tx:Store=db){return (await tx.team.findMany({where:{organizationId:ctx.user.organizationId,leadId:ctx.user.id,archivedAt:null},select:{id:true}})).map(t=>t.id);}
export async function workScope(ctx:Context,tx:Store=db):Promise<Prisma.WorkOrderWhereInput>{
 const organizationId=ctx.user.organizationId;
 if(ctx.user.role==='ENGINEER')return {organizationId,assigneeId:ctx.user.id};
 if(ctx.user.role==='TEAM_LEAD')return {organizationId,teamId:{in:await ledTeams(ctx,tx)}};
 if(ctx.user.role==='SALES')return {organizationId,clientId:{not:null}};
 return {organizationId};
}
export async function reportScope(ctx:Context,tx:Store=db):Promise<Prisma.ReportWhereInput>{
 return {organizationId:ctx.user.organizationId,...(ctx.user.role==='ENGINEER'?{userId:ctx.user.id}:ctx.user.role==='TEAM_LEAD'?{teamId:{in:await ledTeams(ctx,tx)}}:{})};
}
export async function engineerScope(ctx:Context,tx:Store=db):Promise<Prisma.UserWhereInput>{return {organizationId:ctx.user.organizationId,role:'ENGINEER',removedAt:null,...(ctx.user.role==='TEAM_LEAD'?{teamId:{in:await ledTeams(ctx,tx)}}:{})};}
export async function clientScope(ctx:Context,tx:Store=db):Promise<Prisma.ClientWhereInput>{
 const organizationId=ctx.user.organizationId;
 if(ctx.user.role==='TEAM_LEAD')return {organizationId,teamId:{in:await ledTeams(ctx,tx)}};
 if(ctx.user.role==='ENGINEER'){const jobs=await tx.workOrder.findMany({where:{organizationId,assigneeId:ctx.user.id,clientId:{not:null}},select:{clientId:true}});return {organizationId,id:{in:jobs.map(j=>j.clientId!)}};}
 return {organizationId};
}
