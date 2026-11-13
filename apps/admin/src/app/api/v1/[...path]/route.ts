import {db} from '../../../../../../../packages/database';
import {authenticate,login,identity} from '@/server/auth';
import {ApiError,errorResponse} from '@/server/errors';
import * as s from '@/server/services';
import * as ops from '@/server/operations';
import * as ai from '@/server/ai';
import * as accounts from '@/server/accounts';
import * as collab from '@/server/collaboration';
import * as workspace from '@/server/workspace';
import * as people from '@/server/people';
import * as summaries from '@/server/visit-summaries';
import * as customerJobs from '@/server/customer-jobs';
import {assetResponse} from '@/server/assets';
import {z} from 'zod';
export const runtime='nodejs';
export const dynamic='force-dynamic';
async function handle(request:Request){
  try{
    const url=new URL(request.url);const p=url.pathname.replace('/api/v1/','');const method=request.method;
    const ids:string[]=[];
    if(/^admin\/(templates|engineers|engineer-types|submissions|visit-summaries|work-orders|users|clients|teams|boards)\/[^/]+/.test(p))ids.push(p.split('/')[2]);
    if(/^(conversations|notifications|work-orders|directory)\/[^/]+/.test(p))ids.push(p.split('/')[1]);
    if(/^templates\/[^/]+\/versions\/[^/]+$/.test(p))ids.push(p.split('/')[1],p.split('/')[3]);
    if(/^submissions\/status\/[^/]+$/.test(p))ids.push(p.split('/')[2]);
    if(/^submission-attempts\/[^/]+\/cancel$/.test(p))ids.push(p.split('/')[1]);
    for(const name of ['typeId','engineerId','deviceId','clientId','jobId','boardId','userId','teamId']){const value=url.searchParams.get(name);if(value)ids.push(value);}
    if(ids.some(id=>!z.uuid().safeParse(id).success)||p==='sync/manifest'&&!url.searchParams.get('deviceId'))throw new ApiError(400,'INVALID_IDENTIFIER','Use a valid UUID identifier.');
    if(p==='health'&&method==='GET'){await db.$queryRaw`SELECT 1`;return Response.json({status:'ready',database:'postgresql'});}
    if(p.startsWith('integrations/chatm/')){
      const match=p.match(/^integrations\/chatm\/customers\/([^/]+)\/jobs$/);
      if(method!=='GET'||!match||url.search)throw new ApiError(404,'NOT_FOUND','This backend operation is unavailable.');
      let email:string;try{email=decodeURIComponent(match[1]);}catch{throw new ApiError(400,'INVALID_INPUT','Use a valid customer email.');}
      return Response.json(await customerJobs.readChatmCustomerJobs(request,email),{headers:{'Cache-Control':'no-store'}});
    }
    let raw='';if(!['GET','HEAD'].includes(method)){
      if(Number(request.headers.get('content-length')??0)>1048576)throw new ApiError(400,'BODY_TOO_LARGE','Maximum JSON body size is 1 MiB.');
      const reader=request.body?.getReader();const chunks:Uint8Array[]=[];let size=0;
      if(reader)while(true){const {value,done}=await reader.read();if(done)break;size+=value.length;if(size>1048576){await reader.cancel();throw new ApiError(400,'BODY_TOO_LARGE','Maximum JSON body size is 1 MiB.');}chunks.push(value);}
      raw=Buffer.concat(chunks).toString('utf8');
    }
    const body=()=>{try{return JSON.parse(raw||'{}');}catch{throw new ApiError(400,'MALFORMED_JSON','Send valid JSON.');}};
    if(p==='auth/login'&&method==='POST')return await login(request,body());
    const ctx=await authenticate(request);let result:unknown;let status=200;
    if(/^assets\/[a-f0-9]{64}$/.test(p)&&method==='GET')return assetResponse(ctx,p.split('/')[1],request);
    if(p==='auth/logout'&&method==='POST'){await db.session.update({where:{id:ctx.sessionId},data:{revokedAt:new Date()}});const r=Response.json({signedOut:true});r.headers.set('Set-Cookie','fa_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0');return r;}
    if(p==='me'&&method==='GET')result=await identity(ctx);
    else if(p==='me/profile'&&method==='PATCH')result=await workspace.updateProfile(ctx,body());
    else if(p==='boards'&&method==='GET')result=await workspace.listBoards(ctx);
    else if(p==='boards'&&method==='POST'){result=await workspace.createBoard(ctx,body());status=201;}
    else if(p==='time-tracking'&&method==='GET')result=await workspace.listTime(ctx,url);
    else if(/^work-orders\/[^/]+\/time-events$/.test(p)&&method==='POST'){result=await workspace.recordTime(ctx,p.split('/')[1],body());status=201;}
    else if(p==='ai/status'&&method==='GET')result=ai.aiStatus(ctx);
    else if(p==='ai/operations'&&method==='POST')result=await ai.generateAi(ctx,'operations',body());
    else if(p==='ai/report'&&method==='POST')result=await ai.generateAi(ctx,'report',body());
    else if(p==='ai/brief'&&method==='POST')result=await ai.generateAi(ctx,'brief',body());
    else if(p==='admin/dashboard'&&method==='GET')result=await s.dashboard(ctx);
    else if(p==='admin/users'&&method==='GET')result=await accounts.listAccounts(ctx,url);
    else if(p==='admin/users'&&method==='POST'){result=await accounts.createAccount(ctx,body());status=201;}
    else if(/^admin\/users\/[^/]+$/.test(p)&&method==='PATCH')result=await accounts.updateAccount(ctx,p.split('/')[2],body());
    else if(/^admin\/users\/[^/]+$/.test(p)&&method==='DELETE')result=await accounts.removeAccount(ctx,p.split('/')[2],body());
    else if(p==='admin/clients'&&method==='GET')result=await collab.listClients(ctx,url);
    else if(p==='admin/clients'&&method==='POST'){result=await collab.saveClient(ctx,body());status=201;}
    else if(/^admin\/clients\/[^/]+$/.test(p)&&method==='PATCH')result=await collab.saveClient(ctx,body(),p.split('/')[2]);
    else if(p==='teams'&&method==='GET')result=await collab.listTeams(ctx);
    else if(p==='admin/teams'&&method==='POST'){result=await collab.saveTeam(ctx,body());status=201;}
    else if(/^admin\/teams\/[^/]+$/.test(p)&&method==='PATCH')result=await collab.saveTeam(ctx,body(),p.split('/')[2]);
    else if(p==='directory'&&method==='GET')result=await collab.directory(ctx,url);
    else if(/^directory\/[^/]+$/.test(p)&&method==='GET')result=await people.colleague(ctx,p.split('/')[1]);
    else if(p==='organisation'&&method==='GET')result=await people.organisation(ctx);
    else if(p==='conversations'&&method==='GET')result=await collab.listConversations(ctx,url);
    else if(p==='conversations'&&method==='POST'){result=await collab.openConversation(ctx,body());status=201;}
    else if(/^conversations\/[^/]+\/messages$/.test(p)&&method==='GET')result=await collab.listMessages(ctx,p.split('/')[1],url);
    else if(/^conversations\/[^/]+\/messages$/.test(p)&&method==='POST'){result=await collab.sendMessage(ctx,p.split('/')[1],body());status=201;}
    else if(/^conversations\/[^/]+\/read$/.test(p)&&method==='POST')result=await collab.readConversation(ctx,p.split('/')[1],body());
    else if(p==='notifications'&&method==='GET')result=await collab.notifications(ctx,url);
    else if(/^notifications\/[^/]+\/read$/.test(p)&&method==='POST')result=await collab.readNotification(ctx,p.split('/')[1]);
    else if(/^work-orders\/[^/]+\/response$/.test(p)&&method==='POST')result=await collab.respondToJob(ctx,p.split('/')[1],body());
    else if(p==='admin/workspace/summary'&&method==='GET')result=await collab.workspaceSummary(ctx);
    else if(p==='admin/operations/summary'&&method==='GET')result=await ops.operationsSummary(ctx);
    else if(p==='admin/work-orders'&&method==='GET')result=await ops.listWorkOrders(ctx,url);
    else if(p==='admin/work-orders'&&method==='POST'){result=await ops.saveWorkOrder(ctx,body());status=201;}
    else if(/^admin\/work-orders\/[^/]+$/.test(p)&&method==='PATCH')result=await ops.saveWorkOrder(ctx,body(),p.split('/')[2]);
    else if(/^admin\/work-orders\/[^/]+\/customer-status$/.test(p)&&method==='PUT')result=await customerJobs.saveCustomerJobStatus(ctx,p.split('/')[2],body());
    else if(p==='admin/reviews'&&method==='GET')result=await ops.listReviews(ctx,url);
    else if(/^admin\/submissions\/[^/]+\/review$/.test(p)&&method==='POST')result=await ops.reviewReport(ctx,p.split('/')[2],body());
    else if(p==='admin/asset-history'&&method==='GET')result=await ops.assetHistory(ctx,url);
    else if(p==='mobile/operations'&&method==='GET')result=await ops.mobileOperations(ctx);
    else if(p==='admin/templates'&&method==='GET')result=await s.listTemplates(ctx,url);
    else if(p==='admin/templates'&&method==='POST'){result=await s.createTemplate(ctx,body());status=201;}
    else if(/^admin\/templates\/[^/]+\/draft$/.test(p)&&method==='GET')result=await s.getDraft(ctx,p.split('/')[2]);
    else if(/^admin\/templates\/[^/]+\/draft$/.test(p)&&method==='PUT')result=await s.saveDraft(ctx,p.split('/')[2],body(),Number(request.headers.get('if-match')?.replaceAll('"','')));
    else if(/^admin\/templates\/[^/]+\/publish$/.test(p)&&method==='POST'){result=await s.publishTemplate(ctx,p.split('/')[2],body());status=201;}
    else if(/^admin\/templates\/[^/]+\/archive$/.test(p)&&method==='POST')result=await s.archiveTemplate(ctx,p.split('/')[2],body());
    else if(p==='admin/engineer-types'&&method==='GET')result=await s.listTypes(ctx,url);
    else if(p==='admin/engineer-types'&&method==='POST'){result=await s.createType(ctx,body());status=201;}
    else if(/^admin\/engineer-types\/[^/]+$/.test(p)&&method==='PATCH')result=await s.patchType(ctx,p.split('/')[2],body());
    else if(p==='admin/engineers'&&method==='GET')result=await s.listEngineers(ctx,url);
    else if(p==='admin/engineers'&&method==='POST'){result=await s.createEngineer(ctx,body());status=201;}
    else if(/^admin\/engineers\/[^/]+$/.test(p)&&method==='PATCH')result=await s.patchEngineer(ctx,p.split('/')[2],body());
    else if(p==='admin/devices'&&method==='GET')result=await s.listDevices(ctx,url);
    else if(p==='devices/provision'&&method==='POST')result=await s.provision(ctx,body());
    else if(p==='devices/heartbeat'&&method==='POST')result=await s.heartbeat(ctx,body());
    else if(p==='sync/manifest'&&method==='GET')result=await s.manifest(ctx,url.searchParams.get('deviceId')??'');
    else if(/^templates\/[^/]+\/versions\/[^/]+$/.test(p)&&method==='GET')result=await s.getVersion(ctx,p.split('/')[1],p.split('/')[3]);
    else if(p==='submissions'&&method==='POST'){const accepted=await s.acceptSubmission(ctx,raw,request.headers.get('x-payload-sha256'));result=accepted;status=accepted.created?201:200;}
    else if(/^submissions\/status\/[^/]+$/.test(p)&&method==='GET')result=await s.submissionStatus(ctx,p.split('/')[2]);
    else if(/^submission-attempts\/[^/]+\/cancel$/.test(p)&&method==='POST')result=await s.cancelAttempt(ctx,p.split('/')[1],body());
    else if(p==='admin/submissions'&&method==='GET')result=await s.listSubmissions(ctx,url);
    else if(p==='visit-summaries'&&method==='POST'){result=await summaries.submitVisitSummary(ctx,body());status=201;}
    else if(p==='admin/visit-summaries'&&method==='GET')result=await summaries.listVisitSummaries(ctx,url);
    else if(/^admin\/visit-summaries\/[^/]+$/.test(p)&&method==='GET')result=await summaries.visitSummaryDetail(ctx,p.split('/')[2]);
    else if(/^admin\/submissions\/[^/]+$/.test(p)&&method==='GET')result=await s.submissionDetail(ctx,p.split('/')[2]);
    else throw new ApiError(404,'NOT_FOUND','This API operation is unavailable.');
    return Response.json(result,{status,headers:{'Cache-Control':'no-store'}});
  }catch(error){return errorResponse(error);}
}
export {handle as GET,handle as POST,handle as PUT,handle as PATCH,handle as DELETE};
