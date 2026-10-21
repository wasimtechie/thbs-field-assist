import {db} from '../../../../packages/database';
import {Prisma,type Conversation} from '@prisma/client';
import {z} from 'zod';
import {teamInputSchema,clientInputSchema,conversationInputSchema,messageInputSchema,assignmentResponseSchema} from '@field-assist/contracts';
import {requirePermission,requireEngineer,publicUser,type Context} from './auth';
import {parse,transaction,audit,pageParams} from './services';
import {clientScope,ledTeams,workScope,reportScope} from './scopes';
import {ApiError,notFound} from './errors';
type Store=Prisma.TransactionClient;
const revision={expectedRevision:z.number().int().min(1)};
const leadRoles=['ADMIN','OPERATIONS_MANAGER','TEAM_LEAD'];
const person=(u:any)=>({avatarId:u.avatarId,id:u.id,name:u.name,email:u.email,role:u.role,department:u.department,jobTitle:u.jobTitle,employeeCode:u.employeeCode,teamId:u.teamId,disabledAt:u.disabledAt,removedAt:u.removedAt});
export async function notify(tx:Store,org:string,userIds:string[],kind:string,resourceId:string,title:string,body:string,key:string){
 const users=await tx.user.findMany({where:{id:{in:[...new Set(userIds)]},organizationId:org,disabledAt:null,removedAt:null},select:{id:true}});
 if(users.length)await tx.notification.createMany({data:users.map(u=>({organizationId:org,userId:u.id,kind,resourceId,title:title.slice(0,160),body:body.slice(0,300),deliveryKey:key})),skipDuplicates:true});
}
export async function teamPeople(teamId:string,org:string,tx:Store=db){const t=await tx.team.findFirst({where:{id:teamId,organizationId:org,archivedAt:null}});if(!t)return [];return tx.user.findMany({where:{organizationId:org,disabledAt:null,removedAt:null,OR:[{teamId:t.id},{id:t.leadId}]},orderBy:{name:'asc'}});}
export async function listTeams(ctx:Context){
 requirePermission(ctx,'teams.read');const org=ctx.user.organizationId;
 const where:Prisma.TeamWhereInput={organizationId:org,archivedAt:null,...(ctx.user.role==='ENGINEER'?{id:ctx.user.teamId??'00000000-0000-4000-8000-000000000000'}:ctx.user.role==='TEAM_LEAD'?{OR:[{leadId:ctx.user.id},{id:ctx.user.teamId??'00000000-0000-4000-8000-000000000000'}]}:{})};
 const teams=await db.team.findMany({where,orderBy:{name:'asc'}});
 return {items:await Promise.all(teams.map(async t=>({...t,lead:person(await db.user.findUniqueOrThrow({where:{id:t.leadId}})),members:(await teamPeople(t.id,org)).map(person),clientCount:await db.client.count({where:{teamId:t.id,organizationId:org,status:{not:'paused'}}})}))) };
}
export async function saveTeam(ctx:Context,input:unknown,id?:string){
 requirePermission(ctx,'teams.manage');const data=parse(id?teamInputSchema.extend(revision):teamInputSchema,input);
 return transaction(async tx=>{
 const lead=await tx.user.findFirst({where:{id:data.leadId,organizationId:ctx.user.organizationId,role:{in:leadRoles},disabledAt:null,removedAt:null}});if(!lead)throw new ApiError(422,'LEAD_UNAVAILABLE','Choose an active Team Lead, Operations Manager or Administrator.');
 const {expectedRevision,...fields}=data as typeof data&{expectedRevision?:number};
 let team;
 if(id){const current=await tx.team.findFirst({where:{id,organizationId:ctx.user.organizationId,archivedAt:null}});if(!current)notFound();if(current.revision!==expectedRevision)throw new ApiError(409,'STALE_REVISION','This team changed. Reload before saving.');team=await tx.team.update({where:{id},data:{...fields,revision:{increment:1}}});}
 else{team=await tx.team.create({data:{...fields,organizationId:ctx.user.organizationId}});await tx.conversation.create({data:{organizationId:team.organizationId,kind:'team',teamId:team.id}});}
 await audit(tx,ctx,id?'team.updated':'team.created',team.id,{leadId:team.leadId});return team;
 });
}
async function clientDetails(c:any,ctx:Context){const team=c.teamId?await db.team.findUnique({where:{id:c.teamId}}):null;return {...c,...(ctx.user.role==='ENGINEER'?{notes:undefined,createdBy:undefined}:{}),team:team?{id:team.id,name:team.name,department:team.department,leadId:team.leadId}:null,jobCount:await db.workOrder.count({where:{...await workScope(ctx),clientId:c.id}})};}
export async function listClients(ctx:Context,url:URL){
 requirePermission(ctx,'clients.read');const {limit,...pagination}=pageParams(url),search=(url.searchParams.get('search')??'').trim().slice(0,120),status=url.searchParams.get('status');
 if(status&&!['prospect','active','paused'].includes(status))throw new ApiError(400,'INVALID_FILTER','Select a supported client status.');
 const where:Prisma.ClientWhereInput={...await clientScope(ctx),...(status?{status}:{}),...(search?{OR:['name','contactName','email','address'].map(k=>({[k]:{contains:search,mode:'insensitive'}}))}:{})};
 const [rows,total]=await Promise.all([db.client.findMany({where,...pagination,orderBy:[{createdAt:'desc'},{id:'desc'}]}),db.client.count({where})]);
 return {items:await Promise.all(rows.slice(0,limit).map(c=>clientDetails(c,ctx))),total,nextCursor:rows.length>limit?rows[limit-1].id:null};
}
export async function saveClient(ctx:Context,input:unknown,id?:string){
 requirePermission(ctx,'clients.manage');const data=parse(id?clientInputSchema.extend(revision):clientInputSchema,input);
 return transaction(async tx=>{
 const org=ctx.user.organizationId;const team=data.teamId?await tx.team.findFirst({where:{id:data.teamId,organizationId:org,archivedAt:null}}):null;if(data.teamId&&!team)throw new ApiError(422,'TEAM_UNAVAILABLE','Choose an active team in this organisation.');
 const {expectedRevision,...fields}=data as typeof data&{expectedRevision?:number};let client;
 if(id){const current=await tx.client.findFirst({where:{id,...await clientScope(ctx,tx)}});if(!current)notFound();if(current.revision!==expectedRevision)throw new ApiError(409,'STALE_REVISION','This client changed. Reload before saving.');client=await tx.client.update({where:{id},data:{...fields,revision:{increment:1}}});}
 else client=await tx.client.create({data:{...fields,organizationId:org,createdBy:ctx.user.id}});
 if(team)await notify(tx,org,[team.leadId],'client.assigned',client.id,'Client routed to your team',`${client.name} · ${team.name}`,`client:${client.id}:${client.revision}`);
 await audit(tx,ctx,id?'client.updated':'client.created',client.id,{teamId:client.teamId});return client;
 });
}
export async function directory(ctx:Context,url:URL){
 requirePermission(ctx,'directory.read');const q=(url.searchParams.get('search')??'').trim().toLowerCase().slice(0,120),limit=Number(url.searchParams.get('limit')??30),offset=Number(url.searchParams.get('offset')??0);
 const department=(url.searchParams.get('department')??'').trim().slice(0,100),teamId=url.searchParams.get('teamId'),unassigned=url.searchParams.get('unassigned');
 if(!Number.isInteger(limit)||limit<1||limit>50||!Number.isInteger(offset)||offset<0||offset>10000)throw new ApiError(400,'INVALID_PAGINATION','Choose a directory page of 1–50 people.');
 if(teamId&&!z.uuid().safeParse(teamId).success||unassigned!==null&&!['true','false'].includes(unassigned))throw new ApiError(400,'INVALID_FILTER','Choose a valid squad or assignment filter.');
 const pattern=`%${q.replace(/[\\%_]/g,'\\$&')}%`;
 const text=Prisma.sql`lower(u.name || ' ' || u.email || ' ' || u.department || ' ' || u."jobTitle" || ' ' || u."employeeCode" || ' ' || replace(u.role,'_',' ') || ' ' || coalesce(t.name,'') || ' ' || coalesce(t.department,''))`;
 const rows=await db.$queryRaw<any[]>(Prisma.sql`SELECT u.id,u.name,u."avatarId",u.email,u.role,u.department,u."jobTitle",u."employeeCode",u."teamId",t.name AS "teamName",t."leadId",l.name AS "leadName",
 CASE WHEN ${q}='' THEN 0 ELSE greatest(word_similarity(${q},${text}),CASE WHEN lower(u.name)=${q} THEN 2 ELSE 0 END) END AS score
 FROM "User" u LEFT JOIN "Team" t ON t.id=u."teamId" AND t."organizationId"=u."organizationId" AND t."archivedAt" IS NULL
 LEFT JOIN "User" l ON l.id=t."leadId" AND l."organizationId"=u."organizationId" AND l."disabledAt" IS NULL AND l."removedAt" IS NULL
 WHERE u."organizationId"=${ctx.user.organizationId}::uuid AND u."disabledAt" IS NULL AND u."removedAt" IS NULL
 AND (${q}='' OR ${text} LIKE ${pattern} ESCAPE '\' OR word_similarity(${q},${text})>=0.25)
 ${department?Prisma.sql`AND (u.department=${department} OR t.department=${department})`:Prisma.empty}
 ${teamId?Prisma.sql`AND t.id=${teamId}::uuid`:Prisma.empty}
 ${unassigned==='true'?Prisma.sql`AND t.id IS NULL`:Prisma.empty}
 ORDER BY score DESC,u.name,u.id LIMIT ${limit+1} OFFSET ${offset}`);
 return {items:rows.slice(0,limit).map(({score,...p})=>p),nextOffset:rows.length>limit?offset+limit:null,search:q};
}

async function accessibleConversation(ctx:Context,id:string,tx:Store=db){
 const c=await tx.conversation.findFirst({where:{id,organizationId:ctx.user.organizationId}});if(!c)notFound();
 if(c.kind==='direct'){if(!await tx.conversationMember.findUnique({where:{conversationId_userId:{conversationId:id,userId:ctx.user.id}}}))notFound();}
 else if(!(await teamPeople(c.teamId!,ctx.user.organizationId,tx)).some(u=>u.id===ctx.user.id))notFound();
 return c;
}
async function participants(c:Conversation,tx:Store=db){if(c.kind==='team')return teamPeople(c.teamId!,c.organizationId,tx);const members=await tx.conversationMember.findMany({where:{conversationId:c.id}});return tx.user.findMany({where:{id:{in:members.map(m=>m.userId)},organizationId:c.organizationId}});}
async function conversationDetails(ctx:Context,c:Conversation){const people=await participants(c),member=await db.conversationMember.findUnique({where:{conversationId_userId:{conversationId:c.id,userId:ctx.user.id}}}),last=await db.message.findFirst({where:{conversationId:c.id},orderBy:{sequence:'desc'}});return {...c,participants:people.map(person),title:c.kind==='team'?(await db.team.findUniqueOrThrow({where:{id:c.teamId!}})).name:people.filter(u=>u.id!==ctx.user.id).map(u=>u.name).join(', '),lastMessage:last?serializeMessage(last):null,unread:await db.message.count({where:{conversationId:c.id,senderId:{not:ctx.user.id},sequence:{gt:member?.lastReadSequence??0n}}})};}
const serializeMessage=(m:any)=>({...m,sequence:m.sequence.toString()});
export async function openConversation(ctx:Context,input:unknown){
 requirePermission(ctx,'messages.use');const data=parse(conversationInputSchema,input);
 return transaction(async tx=>{
 if('teamId'in data){const people=await teamPeople(data.teamId,ctx.user.organizationId,tx);if(!people.some(u=>u.id===ctx.user.id))notFound();return tx.conversation.upsert({where:{teamId:data.teamId},create:{organizationId:ctx.user.organizationId,kind:'team',teamId:data.teamId},update:{}});}
 if(data.recipientId===ctx.user.id)throw new ApiError(422,'SELF_MESSAGE','Choose a colleague to message.');
 const recipient=await tx.user.findFirst({where:{id:data.recipientId,organizationId:ctx.user.organizationId,disabledAt:null,removedAt:null}});if(!recipient)notFound();
 const directKey=[ctx.user.id,recipient.id].sort().join(':');const c=await tx.conversation.upsert({where:{organizationId_directKey:{organizationId:ctx.user.organizationId,directKey}},create:{organizationId:ctx.user.organizationId,kind:'direct',directKey},update:{}});
 await tx.conversationMember.createMany({data:[ctx.user.id,recipient.id].map(userId=>({conversationId:c.id,userId})),skipDuplicates:true});return c;
 });
}
export async function listConversations(ctx:Context,url:URL){
 requirePermission(ctx,'messages.use');const {limit,...pagination}=pageParams(url),org=ctx.user.organizationId;
 const ownTeams=(await db.team.findMany({where:{organizationId:org,archivedAt:null,OR:[{leadId:ctx.user.id},{id:ctx.user.teamId??'00000000-0000-4000-8000-000000000000'}]},select:{id:true}})).map(t=>t.id);
 const membership=await db.conversationMember.findMany({where:{userId:ctx.user.id},select:{conversationId:true}});
 const where:Prisma.ConversationWhereInput={organizationId:org,OR:[{kind:'direct',id:{in:membership.map(m=>m.conversationId)}},{kind:'team',teamId:{in:ownTeams}}]};
 const all=await db.conversation.findMany({where,orderBy:[{updatedAt:'desc'},{id:'desc'}]});
 const rows=await db.conversation.findMany({where,...pagination,orderBy:[{updatedAt:'desc'},{id:'desc'}]});
 const counts=await Promise.all(all.map(async c=>{const member=await db.conversationMember.findUnique({where:{conversationId_userId:{conversationId:c.id,userId:ctx.user.id}}});return db.message.count({where:{conversationId:c.id,senderId:{not:ctx.user.id},sequence:{gt:member?.lastReadSequence??0n}}});}));
 return {items:await Promise.all(rows.slice(0,limit).map(c=>conversationDetails(ctx,c))),total:all.length,unread:counts.reduce((a,b)=>a+b,0),nextCursor:rows.length>limit?rows[limit-1].id:null};
}
export async function listMessages(ctx:Context,id:string,url:URL){
 requirePermission(ctx,'messages.use');const c=await accessibleConversation(ctx,id);const raw=url.searchParams.get('before'),limit=Number(url.searchParams.get('limit')??50);
 if(raw&&!/^\d{1,18}$/.test(raw)||!Number.isInteger(limit)||limit<1||limit>100)throw new ApiError(400,'INVALID_PAGINATION','Choose a valid message page.');
 const rows=await db.message.findMany({where:{conversationId:id,...(raw?{sequence:{lt:BigInt(raw)}}:{})},orderBy:{sequence:'desc'},take:limit+1});
 return {conversation:await conversationDetails(ctx,c),items:rows.slice(0,limit).reverse().map(serializeMessage),nextBefore:rows.length>limit?rows[limit-1].sequence.toString():null};
}
export async function sendMessage(ctx:Context,id:string,input:unknown){
 requirePermission(ctx,'messages.use');const data=parse(messageInputSchema,input);
 return transaction(async tx=>{
 const c=await accessibleConversation(ctx,id,tx);
 const previous=await tx.message.findUnique({where:{conversationId_senderId_clientMessageId:{conversationId:id,senderId:ctx.user.id,clientMessageId:data.clientMessageId}}});
 if(previous){if(previous.text!==data.text)throw new ApiError(409,'IDEMPOTENCY_CONFLICT','This message reference already has different text.');return serializeMessage(previous);}
 const people=(await participants(c,tx)).filter(u=>!u.disabledAt&&!u.removedAt);if(!people.some(u=>u.id!==ctx.user.id))throw new ApiError(409,'RECIPIENT_UNAVAILABLE','This colleague is unavailable. Your message has not been sent.');
 const message=await tx.message.create({data:{...data,organizationId:ctx.user.organizationId,conversationId:id,senderId:ctx.user.id}});
 await tx.conversation.update({where:{id},data:{updatedAt:new Date()}});
 await notify(tx,ctx.user.organizationId,people.filter(p=>p.id!==ctx.user.id).map(p=>p.id),'message.new',c.id,`${ctx.user.name} sent a message`,data.text,`message:${message.id}`);
 return serializeMessage(message);
 });
}
export async function readConversation(ctx:Context,id:string,input:unknown){
 requirePermission(ctx,'messages.use');const data=parse(z.object({throughSequence:z.string().regex(/^\d{1,18}$/)}).strict(),input);
 return transaction(async tx=>{await accessibleConversation(ctx,id,tx);const through=BigInt(data.throughSequence);if(!await tx.message.findFirst({where:{conversationId:id,sequence:through}}))throw new ApiError(422,'MESSAGE_UNAVAILABLE','Read a message from this conversation.');
 await tx.conversationMember.upsert({where:{conversationId_userId:{conversationId:id,userId:ctx.user.id}},create:{conversationId:id,userId:ctx.user.id,lastReadSequence:through},update:{}});
 await tx.conversationMember.updateMany({where:{conversationId:id,userId:ctx.user.id,lastReadSequence:{lt:through}},data:{lastReadSequence:through}});
 await tx.$executeRaw`UPDATE "Notification" SET "readAt"=CURRENT_TIMESTAMP WHERE "userId"=${ctx.user.id}::uuid AND "organizationId"=${ctx.user.organizationId}::uuid AND kind='message.new' AND "deliveryKey" IN (SELECT 'message:' || id::text FROM "Message" WHERE "conversationId"=${id}::uuid AND sequence<=${through})`;
 return {readThrough:through.toString()};});
}
export async function notifications(ctx:Context,url:URL){
 requirePermission(ctx,'notifications.read');const {limit,...pagination}=pageParams(url),where={organizationId:ctx.user.organizationId,userId:ctx.user.id};
 const [rows,unread]=await Promise.all([db.notification.findMany({where,...pagination,orderBy:[{createdAt:'desc'},{id:'desc'}]}),db.notification.count({where:{...where,readAt:null}})]);
 return {items:rows.slice(0,limit),unread,nextCursor:rows.length>limit?rows[limit-1].id:null};
}
export async function readNotification(ctx:Context,id:string){requirePermission(ctx,'notifications.read');const r=await db.notification.updateMany({where:{id,organizationId:ctx.user.organizationId,userId:ctx.user.id,readAt:null},data:{readAt:new Date()}});if(!r.count&&!await db.notification.findFirst({where:{id,userId:ctx.user.id,organizationId:ctx.user.organizationId}}))notFound();return {read:true};}
export async function respondToJob(ctx:Context,id:string,input:unknown){
 requirePermission(ctx,'work_orders.respond');requireEngineer(ctx);const data=parse(assignmentResponseSchema,input);
 return transaction(async tx=>{
 const prior=await tx.assignmentResponse.findUnique({where:{userId_requestId:{userId:ctx.user.id,requestId:data.requestId}}});
 if(prior){if(prior.workOrderId!==id||prior.assignmentRevision!==data.assignmentRevision||prior.decision!==data.decision||prior.note!==data.note)throw new ApiError(409,'IDEMPOTENCY_CONFLICT','This response reference already has different content.');return prior;}
 const job=await tx.workOrder.findFirst({where:{id,organizationId:ctx.user.organizationId,assigneeId:ctx.user.id}});if(!job)notFound();
 if(job.assignmentRevision!==data.assignmentRevision||!['assigned','follow_up'].includes(job.status))throw new ApiError(409,'ASSIGNMENT_CHANGED','This assignment changed. Refresh the brief before responding.');
 if(job.responseStatus!=='pending')throw new ApiError(409,'ALREADY_RESPONDED','A response was already recorded for this assignment. Ask your lead to reassign if needed.');
 const response=await tx.assignmentResponse.create({data:{...data,workOrderId:id,organizationId:ctx.user.organizationId,userId:ctx.user.id,brief:{title:job.title,site:job.site,instructions:job.instructions,priority:job.priority,assetReference:job.assetReference,dueAt:job.dueAt.toISOString(),teamId:job.teamId,clientId:job.clientId,assigneeId:job.assigneeId}}});
 await tx.workOrder.update({where:{id},data:{responseStatus:data.decision,responseNote:data.note,respondedAt:response.respondedAt,revision:{increment:1}}});
 const team=job.teamId?await tx.team.findUnique({where:{id:job.teamId}}):null;
 await notify(tx,ctx.user.organizationId,[job.createdBy,...(team?[team.leadId]:[])].filter(u=>u!==ctx.user.id),'job.responded',id,`Assignment ${data.decision}`,`${ctx.user.name} · ${job.title}${data.note?': '+data.note:''}`,`response:${response.id}`);
 await audit(tx,ctx,`work_order.${data.decision}`,id,{assignmentRevision:data.assignmentRevision,note:data.note});return response;
 });
}
export async function workspaceSummary(ctx:Context){
 requirePermission(ctx,'overview.read');const jobs=await db.workOrder.findMany({where:await workScope(ctx)}),reports=await db.report.count({where:await reportScope(ctx)});
 const clients=['ADMIN','OPERATIONS_MANAGER','TEAM_LEAD','SALES','ENGINEER'].includes(ctx.user.role)?await db.client.count({where:await clientScope(ctx)}):0;
 return {scope:ctx.user.role==='ENGINEER'?'Your assignments and reports':ctx.user.role==='TEAM_LEAD'?'Your led teams':ctx.user.role==='SALES'?'Client delivery':'Organisation',clients,jobs:jobs.length,pending:jobs.filter(j=>j.responseStatus==='pending').length,accepted:jobs.filter(j=>j.responseStatus==='accepted').length,declined:jobs.filter(j=>j.responseStatus==='declined').length,completed:jobs.filter(j=>j.status==='completed').length,reports:ctx.user.role==='SALES'?null:reports};
}
