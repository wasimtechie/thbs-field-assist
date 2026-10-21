import {db} from '../../../../packages/database';
import {templateSchema,validateValues,schemaHash,schemaBytes,frozenReportSchema,sha256,hasPermission,type TemplateSchema,type Values} from '@field-assist/contracts';
import {ApiError,notFound} from './errors';
import {requireAdmin,requirePermission,requireEngineer,publicUser,identity,type Context} from './auth';
import {Prisma} from '@prisma/client';
import {SignJWT,importJWK} from 'jose';
import {z} from 'zod';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import path from 'node:path';
import {reportScope,workScope,engineerScope} from './scopes';

type Tx=Prisma.TransactionClient;
const json=(v:unknown)=>v as Prisma.InputJsonValue;
export function parse<T>(schema:z.ZodType<T>,input:unknown):T{const r=schema.safeParse(input);if(!r.success)throw new ApiError(422,'VALIDATION_FAILED','Review the highlighted fields.',r.error.issues.map(i=>({fieldId:i.path.join('.'),code:i.code,message:i.message})));return r.data;}
const expectedSchema=z.object({expectedRevision:z.number().int().min(1)});
export async function transaction<T>(fn:(tx:Tx)=>Promise<T>):Promise<T>{
  for(let attempt=0;attempt<5;attempt++)try{return await db.$transaction(fn,{isolationLevel:'Serializable',timeout:15000});}catch(e){if(e instanceof Prisma.PrismaClientKnownRequestError&&['P2034','P2002'].includes(e.code)&&attempt<4)continue;throw e;}
  throw new ApiError(503,'RETRY','Please retry.');
}
export const audit=(tx:Tx,ctx:Context,action:string,entityId:string,metadata:unknown={})=>tx.auditEvent.create({data:{organizationId:ctx.user.organizationId,actorId:ctx.user.id,action,entityId,metadata:json(metadata)}});
async function templateFor(ctx:Context,id:string,tx:Tx=db){const t=await tx.template.findFirst({where:{id,organizationId:ctx.user.organizationId}});if(!t)notFound();return t;}
const stale=()=>new ApiError(409,'STALE_REVISION','A newer revision exists. Reload before saving.');
export function pageParams(url:URL){const raw=url.searchParams.get('limit')??'25';const limit=Number(raw);if(!Number.isInteger(limit)||limit<1||limit>100)throw new ApiError(400,'INVALID_PAGINATION','Limit must be between 1 and 100.');const cursor=url.searchParams.get('cursor');if(cursor&&!z.uuid().safeParse(cursor).success)throw new ApiError(400,'INVALID_PAGINATION','Invalid cursor.');return {take:limit+1,...(cursor?{cursor:{id:cursor},skip:1}:{}),limit};}
const page=<T extends {id:string}>(items:T[],limit:number)=>({items:items.slice(0,limit),nextCursor:items.length>limit?items[limit-1].id:null});

export async function dashboard(ctx:Context){
  requirePermission(ctx,'overview.read');const org=ctx.user.organizationId;
  if(['ENGINEER','TEAM_LEAD','SALES'].includes(ctx.user.role)){
    const reports=ctx.user.role==='SALES'?0:await db.report.count({where:await reportScope(ctx)});
    const activeEngineers=ctx.user.role==='ENGINEER'?1:await db.user.count({where:{...await engineerScope(ctx),disabledAt:null}});
    const recent=hasPermission(ctx.user.role,'reports.read')?await listSubmissions(ctx,new URL('http://local?limit=5')):{items:[]};
    return {acceptedReports:reports,publishedTemplates:0,draftTemplates:0,activeEngineers,reportedDevices:0,voiceReadyLastReported:0,lastDeviceContact:null,recent:recent.items,activity:[],types:[],user:publicUser(ctx.user),scope:ctx.user.role};
  }
  const [reports,templates,engineers,devices,events]=await Promise.all([
    db.report.count({where:{organizationId:org}}),db.template.findMany({where:{organizationId:org,archivedAt:null}}),
    db.user.count({where:{organizationId:org,role:'ENGINEER',disabledAt:null}}),
    db.device.findMany({where:{organizationId:org},orderBy:{lastSeenAt:'desc'}}),
    db.auditEvent.findMany({where:{organizationId:org,...(ctx.user.role==='ADMIN'?{}:{OR:(hasPermission(ctx.user.role,'reports.read')?['report.','work_order.']:['template.','type.']).map(prefix=>({action:{startsWith:prefix}}))})},orderBy:[{createdAt:'desc'},{id:'desc'}],take:8}),
  ]);
  const recent=hasPermission(ctx.user.role,'reports.read')?await listSubmissions(ctx,new URL('http://local?limit=5')):{items:[]};
  const byType=await db.report.groupBy({by:['typeId'],where:{organizationId:org},_count:true});
  const types=await db.engineerType.findMany({where:{organizationId:org,archivedAt:null}});
  return {acceptedReports:reports,publishedTemplates:templates.filter(t=>t.currentPublishedVersionId).length,draftTemplates:templates.filter(t=>!t.currentPublishedVersionId).length,activeEngineers:engineers,lastDeviceContact:devices[0]?.lastSeenAt??null,reportedDevices:devices.length,voiceReadyLastReported:devices.filter(d=>(d.readiness as Record<string,unknown>)?.voiceReady===true).length,recent:recent.items,activity:events,types:types.map(t=>({...t,reports:byType.find(b=>b.typeId===t.id)?._count??0})),user:publicUser(ctx.user)};
}
export async function listTemplates(ctx:Context,url:URL){
  requirePermission(ctx,'templates.read');const {limit,...pagination}=pageParams(url);const search=url.searchParams.get('search')??'';
  const status=url.searchParams.get('status');const typeId=url.searchParams.get('typeId');
  if(status&&!['active','published','draft','archived'].includes(status))throw new ApiError(400,'INVALID_FILTER','Select an active, published, draft or archived status.');
  const rows=await db.template.findMany({where:{organizationId:ctx.user.organizationId,...(status==='archived'?{archivedAt:{not:null}}:{archivedAt:null}),...(typeId?{typeId}:{}),...(search?{name:{contains:search,mode:'insensitive'}}:{}),...(status==='draft'?{currentPublishedVersionId:null}:status==='published'?{currentPublishedVersionId:{not:null}}:{})},...pagination,orderBy:[{createdAt:'desc'},{id:'desc'}]});
  const items=await Promise.all(rows.map(async t=>{
    const [draft,version,type]=await Promise.all([db.templateDraft.findUnique({where:{templateId:t.id}}),t.currentPublishedVersionId?db.templateVersion.findUnique({where:{id:t.currentPublishedVersionId}}):null,db.engineerType.findUnique({where:{id:t.typeId}})]);
    const editor=draft?await db.user.findUnique({where:{id:draft.updatedBy}}):null;
    return {...t,version:version?.versionNumber??0,publishedAt:version?.publishedAt,fieldCount:(draft?.schema as unknown as TemplateSchema)?.fields?.length??0,revision:draft?.revision,typeName:type?.name??'Unassigned',lastEditor:editor?.name,updatedAt:draft?.updatedAt};
  }));return page(items,limit);
}
export async function createTemplate(ctx:Context,input:unknown){
  requirePermission(ctx,'templates.manage');const data=parse(z.object({name:z.string().trim().min(1).max(120),typeId:z.uuid()}),input);
  const type=await db.engineerType.findFirst({where:{id:data.typeId,organizationId:ctx.user.organizationId,archivedAt:null}});if(!type)notFound();
  return transaction(async tx=>{
    const t=await tx.template.create({data:{organizationId:ctx.user.organizationId,typeId:type.id,name:data.name}});
    const schema:TemplateSchema={schemaFormatVersion:1,templateId:t.id,engineerTypeId:type.id,title:t.name,sections:[{id:'work',label:'Work and testing',order:0}],fields:[]};
    await tx.templateDraft.create({data:{templateId:t.id,schema:json(schema),updatedBy:ctx.user.id}});await audit(tx,ctx,'template.created',t.id);return t;
  });
}
export async function getDraft(ctx:Context,id:string){requirePermission(ctx,'templates.manage');const template=await templateFor(ctx,id);const draft=await db.templateDraft.findUnique({where:{templateId:id}});if(!draft)notFound();const versions=await db.templateVersion.findMany({where:{templateId:id},orderBy:{versionNumber:'desc'},select:{id:true,versionNumber:true,schemaHash:true,publishedAt:true,disabledAt:true}});return {template,...draft,versions};}
export async function saveDraft(ctx:Context,id:string,input:unknown,expected:number){
  requirePermission(ctx,'templates.manage');const template=await templateFor(ctx,id);if(template.archivedAt)throw new ApiError(409,'TEMPLATE_ARCHIVED','Archived templates cannot be edited.');
  const schema=parse(templateSchema,input);if(schema.templateId!==id||schema.engineerTypeId!==template.typeId)throw new ApiError(422,'IDENTITY_MISMATCH','Template identity cannot be changed.');
  if(!Number.isInteger(expected)||expected<1)throw new ApiError(400,'REVISION_REQUIRED','Supply the current If-Match revision.');
  return transaction(async tx=>{
    const result=await tx.templateDraft.updateMany({where:{templateId:id,revision:expected},data:{schema:json(schema),revision:{increment:1},updatedBy:ctx.user.id}});if(!result.count)throw stale();
    await tx.template.update({where:{id},data:{name:schema.title}});await audit(tx,ctx,'template.draft_saved',id,{revision:expected+1});return tx.templateDraft.findUnique({where:{templateId:id}});
  });
}
export async function publishTemplate(ctx:Context,id:string,input:unknown){
  requirePermission(ctx,'templates.manage');const {expectedRevision}=parse(expectedSchema,input);
  return transaction(async tx=>{
    const template=await templateFor(ctx,id,tx);if(template.archivedAt)throw new ApiError(409,'TEMPLATE_ARCHIVED','Archived templates cannot be published.');
    const draft=await tx.templateDraft.findUnique({where:{templateId:id}});if(!draft||draft.revision!==expectedRevision)throw stale();
    const schema=parse(templateSchema,draft.schema);if(schema.fields.length===0)throw new ApiError(422,'EMPTY_TEMPLATE','Add at least one field before publishing.');
    const latest=await tx.templateVersion.findFirst({where:{templateId:id},orderBy:{versionNumber:'desc'}});
    const lock=await tx.templateDraft.updateMany({where:{templateId:id,revision:expectedRevision},data:{revision:{increment:1},updatedBy:ctx.user.id}});if(!lock.count)throw stale();
    const version=await tx.templateVersion.create({data:{templateId:id,organizationId:ctx.user.organizationId,versionNumber:(latest?.versionNumber??0)+1,schema:json(schema),schemaHash:schemaHash(schema),canonicalSchema:schemaBytes(schema),publishedBy:ctx.user.id}});
    await tx.template.update({where:{id},data:{currentPublishedVersionId:version.id}});await audit(tx,ctx,'template.published',id,{version:version.versionNumber,fields:schema.fields.length});return {...version,revision:expectedRevision+1,changeSummary:`Published ${schema.fields.length} fields as version ${version.versionNumber}.`};
  });
}
export async function archiveTemplate(ctx:Context,id:string,input:unknown){
  requirePermission(ctx,'templates.manage');const {expectedRevision}=parse(expectedSchema,input);await templateFor(ctx,id);
  return transaction(async tx=>{if(await tx.engineerType.count({where:{defaultTemplateId:id,archivedAt:null}}))throw new ApiError(409,'DEFAULT_TEMPLATE_IN_USE','Choose another default form before archiving this template.');
    const updated=await tx.templateDraft.updateMany({where:{templateId:id,revision:expectedRevision},data:{revision:{increment:1}}});if(!updated.count)throw stale();
    const result=await tx.template.update({where:{id},data:{archivedAt:new Date()}});await audit(tx,ctx,'template.archived',id);return result;
  });
}
export async function listTypes(ctx:Context,url:URL){
  requirePermission(ctx,'types.read');const {limit,...pagination}=pageParams(url);const rows=await db.engineerType.findMany({where:{organizationId:ctx.user.organizationId,...(url.searchParams.get('archived')==='true'?{}:{archivedAt:null})},...pagination,orderBy:[{createdAt:'desc'},{id:'desc'}]});
  const users=await db.user.findMany({where:{organizationId:ctx.user.organizationId,disabledAt:null},select:{id:true}});
  const items=await Promise.all(rows.map(async t=>({
    ...t,
    engineerCount:await db.engineerAssignment.count({where:{typeId:t.id,validTo:null,userId:{in:users.map(u=>u.id)}}}),
    defaultTemplate:t.defaultTemplateId?await db.template.findUnique({where:{id:t.defaultTemplateId},select:{id:true,name:true,currentPublishedVersionId:true}}):null,
  })));
  return page(items,limit);
}
export async function createType(ctx:Context,input:unknown){
  requirePermission(ctx,'types.manage');const data=parse(z.object({name:z.string().trim().min(1).max(100),description:z.string().max(300).optional()}),input);
  return transaction(async tx=>{const type=await tx.engineerType.create({data:{organizationId:ctx.user.organizationId,slug:`type-${randomUUID()}`,name:data.name,description:data.description??''}});await audit(tx,ctx,'type.created',type.id);return type;});
}
export async function patchType(ctx:Context,id:string,input:unknown){
  requirePermission(ctx,'types.manage');const data=parse(z.object({expectedRevision:z.number().int().min(1),name:z.string().trim().min(1).max(100).optional(),description:z.string().max(300).optional(),defaultTemplateId:z.uuid().nullable().optional(),archived:z.boolean().optional()}).strict(),input);
  return transaction(async tx=>{
    const type=await tx.engineerType.findFirst({where:{id,organizationId:ctx.user.organizationId}});if(!type)notFound();if(type.revision!==data.expectedRevision)throw stale();
    if(data.archived&&await tx.engineerAssignment.count({where:{typeId:id,validTo:null}}))throw new ApiError(409,'ACTIVE_ASSIGNMENTS','Reassign engineers before archiving this type.');
    if(data.defaultTemplateId){const t=await templateFor(ctx,data.defaultTemplateId,tx);if(t.typeId!==id||!t.currentPublishedVersionId||t.archivedAt)throw new ApiError(422,'INVALID_DEFAULT','Select a published, active template for this type.');}
    const updated=await tx.engineerType.updateMany({where:{id,revision:data.expectedRevision},data:{name:data.name,description:data.description,defaultTemplateId:data.defaultTemplateId,archivedAt:data.archived===undefined?undefined:data.archived?new Date():null,revision:{increment:1}}});if(!updated.count)throw stale();
    await audit(tx,ctx,'type.updated',id);return tx.engineerType.findUnique({where:{id}});
  });
}
export async function listEngineers(ctx:Context,url:URL){
  requirePermission(ctx,'engineers.read');const {limit,...pagination}=pageParams(url);const status=url.searchParams.get('status'),search=(url.searchParams.get('search')??'').trim().slice(0,180);const typeId=url.searchParams.get('typeId');const assignments=typeId?await db.engineerAssignment.findMany({where:{typeId,validTo:null}}):null;
  const users=await db.user.findMany({where:{...await engineerScope(ctx),...(status==='active'?{disabledAt:null}:status==='paused'?{disabledAt:{not:null}}:{}),...(search?{OR:['name','email','employeeCode','department'].map(key=>({[key]:{contains:search,mode:'insensitive'}}))}:{}),...(assignments?{id:{in:assignments.map(a=>a.userId)}}:{})},...pagination,orderBy:[{createdAt:'desc'},{id:'desc'}]});
  return page(await Promise.all(users.map(async u=>{const assignment=await db.engineerAssignment.findFirst({where:{userId:u.id,validTo:null}});const type=assignment?await db.engineerType.findUnique({where:{id:assignment.typeId}}):null;const device=await db.device.findFirst({where:{userId:u.id},orderBy:{lastSeenAt:'desc'}});return {...publicUser(u),createdAt:u.createdAt,type,assignmentRevision:assignment?.revision,lastContact:device?.lastSeenAt??null,packageVersion:device?.packageVersion??null};})),limit);
}
export async function createEngineer(ctx:Context,input:unknown){
  requireAdmin(ctx);const data=parse(z.object({email:z.email(),name:z.string().trim().min(1).max(100),typeId:z.uuid(),initialPassword:z.string().min(6).max(256)}).strict(),input);
  const {hash}=await import('@node-rs/argon2');const passwordHash=await hash(data.initialPassword);
  return transaction(async tx=>{const type=await tx.engineerType.findFirst({where:{id:data.typeId,organizationId:ctx.user.organizationId,archivedAt:null}});if(!type)notFound();if(await tx.user.findUnique({where:{email:data.email.toLowerCase()}}))throw new ApiError(409,'EMAIL_UNAVAILABLE','This email is already in use.');const u=await tx.user.create({data:{organizationId:ctx.user.organizationId,email:data.email.toLowerCase(),name:data.name,passwordHash,role:'ENGINEER'}});await tx.engineerAssignment.create({data:{userId:u.id,typeId:type.id,revision:1}});await audit(tx,ctx,'engineer.created',u.id);return publicUser(u);});
}
export async function patchEngineer(ctx:Context,id:string,input:unknown){
  requireAdmin(ctx);const data=parse(z.object({expectedRevision:z.number().int().min(1),typeId:z.uuid().optional(),disabled:z.boolean().optional()}).strict(),input);
  return transaction(async tx=>{
    const u=await tx.user.findFirst({where:{id,organizationId:ctx.user.organizationId,role:'ENGINEER'}});if(!u)notFound();if(u.revision!==data.expectedRevision)throw stale();
    if(data.typeId){const type=await tx.engineerType.findFirst({where:{id:data.typeId,organizationId:ctx.user.organizationId,archivedAt:null}});if(!type)notFound();const prev=await tx.engineerAssignment.findFirst({where:{userId:id,validTo:null}});if(prev?.typeId!==data.typeId){await tx.engineerAssignment.updateMany({where:{userId:id,validTo:null},data:{validTo:new Date()}});await tx.engineerAssignment.create({data:{userId:id,typeId:data.typeId,revision:(prev?.revision??0)+1}});}}
    if(data.disabled)await tx.session.updateMany({where:{userId:id,revokedAt:null},data:{revokedAt:new Date()}});
    const result=await tx.user.updateMany({where:{id,revision:data.expectedRevision},data:{disabledAt:data.disabled===undefined?undefined:data.disabled?new Date():null,revision:{increment:1}}});if(!result.count)throw stale();await audit(tx,ctx,'engineer.updated',id,{disabled:data.disabled??false});return publicUser((await tx.user.findUniqueOrThrow({where:{id}})));
  });
}
export async function listDevices(ctx:Context,url:URL){requirePermission(ctx,'devices.read');const {limit,...pagination}=pageParams(url);const engineer=url.searchParams.get('engineerId');const rows=await db.device.findMany({where:{organizationId:ctx.user.organizationId,...(engineer?{userId:engineer}:{})},...pagination,orderBy:[{lastSeenAt:'desc'},{id:'desc'}]});return page(await Promise.all(rows.map(async d=>({...d,engineer:publicUser(await db.user.findUniqueOrThrow({where:{id:d.userId}}))}))),limit);}

export async function provision(ctx:Context,input:unknown){
  requireEngineer(ctx);const data=parse(z.object({deviceId:z.uuid(),platform:z.enum(['ios','android']),appVersion:z.string().min(1).max(40),osVersion:z.string().min(1).max(100),model:z.string().max(100).optional()}),input);
  const who=await identity(ctx);if(!who.engineerType||who.engineerType.archivedAt||!who.engineerType.defaultTemplateId)throw new ApiError(422,'NO_ASSIGNED_FORM','Ask your administrator to assign a published default form.');
  const template=await templateFor(ctx,who.engineerType.defaultTemplateId);if(!template.currentPublishedVersionId||template.archivedAt)throw new ApiError(422,'NO_ASSIGNED_FORM','No published form is available.');
  const version=await db.templateVersion.findUniqueOrThrow({where:{id:template.currentPublishedVersionId}});if(version.disabledAt)throw new ApiError(422,'VERSION_DISABLED','The assigned version is disabled. Contact your administrator.');
  const issuedAt=new Date();const expiresAt=new Date(issuedAt.getTime()+Number(process.env.OFFLINE_LEASE_HOURS??72)*3600000);const entitlementId=randomUUID();
  const claims={entitlementId,userId:ctx.user.id,organizationId:ctx.user.organizationId,deviceId:data.deviceId,engineerTypeId:who.engineerType.id,allowedTemplateIds:[template.id],assignmentRevision:who.assignmentRevision,issuedAt:issuedAt.toISOString(),expiresAt:expiresAt.toISOString()};
  const key=await importJWK(JSON.parse(process.env.ENTITLEMENT_PRIVATE_JWK!),'ES256');
  const token=await new SignJWT(claims).setProtectedHeader({alg:'ES256',kid:process.env.ENTITLEMENT_KEY_ID}).setIssuer('field-assist').setAudience('field-assist-offline').setIssuedAt(Math.floor(issuedAt.getTime()/1000)).setExpirationTime(Math.floor(expiresAt.getTime()/1000)).sign(key);
  await transaction(async tx=>{const previous=await tx.device.findUnique({where:{id:data.deviceId}});if(previous&&previous.userId!==ctx.user.id)throw new ApiError(409,'DEVICE_ACCOUNT_CONFLICT','This device identifier belongs to another account.');await tx.device.upsert({where:{id:data.deviceId},create:{id:data.deviceId,userId:ctx.user.id,organizationId:ctx.user.organizationId,platform:data.platform,appVersion:data.appVersion,osVersion:data.osVersion,model:data.model??'Unreported model',readiness:{voiceReady:false,manualReady:false}},update:{lastSeenAt:issuedAt,appVersion:data.appVersion,osVersion:data.osVersion}});await tx.offlineEntitlement.create({data:{id:entitlementId,userId:ctx.user.id,organizationId:ctx.user.organizationId,deviceId:data.deviceId,typeId:who.engineerType!.id,assignmentRevision:who.assignmentRevision,allowedTemplates:[template.id],issuedAt,expiresAt,token}});});
  return {user:who,entitlementId,entitlement:token,serverTime:issuedAt.toISOString(),expiresAt:expiresAt.toISOString(),manifest:await manifest(ctx,data.deviceId),template:{...version.schema as object,versionId:version.id,versionNumber:version.versionNumber,schemaHash:version.schemaHash}};
}
export async function manifest(ctx:Context,deviceId:string){
  requireEngineer(ctx);const device=await db.device.findFirst({where:{id:deviceId,userId:ctx.user.id}});if(!device)notFound();const who=await identity(ctx);const type=who.engineerType;
  const template=type?.defaultTemplateId?await db.template.findFirst({where:{id:type.defaultTemplateId,organizationId:ctx.user.organizationId,archivedAt:null}}):null;
  const version=template?.currentPublishedVersionId?await db.templateVersion.findUnique({where:{id:template.currentPublishedVersionId}}):null;
  let assets:unknown={manifestVersion:1,ready:false,assets:[]};
  const file=process.env.MODEL_MANIFEST_PATH??'fixtures/voice/asset-manifest.json';
  for(const candidate of [path.resolve(file),path.resolve('../../',file)])try{assets=JSON.parse(readFileSync(candidate,'utf8'));break;}catch{}
  return {assignmentRevision:who.assignmentRevision,template:version&&!version.disabledAt?{...version.schema as object,versionId:version.id,versionNumber:version.versionNumber,schemaHash:version.schemaHash}:null,assets,serverTime:new Date().toISOString()};
}
export async function heartbeat(ctx:Context,input:unknown){
  requireEngineer(ctx);const data=parse(z.object({deviceId:z.uuid(),readiness:z.object({voiceReady:z.boolean(),manualReady:z.boolean(),components:z.record(z.string(),z.string()).optional()}).strict(),packageVersion:z.string().max(100).optional(),schemaVersion:z.string().max(100).optional()}),input);
  const result=await db.device.updateMany({where:{id:data.deviceId,userId:ctx.user.id},data:{lastSeenAt:new Date(),readiness:json(data.readiness),packageVersion:data.packageVersion,schemaVersion:data.schemaVersion}});if(!result.count)notFound();return {recordedAt:new Date().toISOString()};
}
export async function getVersion(ctx:Context,id:string,versionId:string){
  const t=await templateFor(ctx,id);const version=await db.templateVersion.findFirst({where:{id:versionId,templateId:t.id}});if(!version)notFound();
  if(ctx.user.role!=='ADMIN'){const leases=await db.offlineEntitlement.findMany({where:{userId:ctx.user.id,allowedTemplates:{has:id}}});if(!leases.length)notFound();}
  if(version.disabledAt)throw new ApiError(422,'VERSION_DISABLED','This version was disabled. Existing work is preserved.');return {...version.schema as object,versionId:version.id,versionNumber:version.versionNumber,schemaHash:version.schemaHash};
}
async function receiptFor(tx:Tx,reportId:string){return tx.receipt.findUniqueOrThrow({where:{reportId}});}
export async function acceptSubmission(ctx:Context,raw:string,providedHash:string|null){
  requireEngineer(ctx);const payloadHash=sha256(raw);if(!providedHash||payloadHash!==providedHash)throw new ApiError(400,'PAYLOAD_HASH_MISMATCH','The frozen payload hash does not match.');
  let input:unknown;try{input=JSON.parse(raw);}catch{throw new ApiError(400,'MALFORMED_JSON','Send valid JSON.');}const data=parse(frozenReportSchema,input);
  return transaction(async tx=>{
    const user=await tx.user.findUniqueOrThrow({where:{id:ctx.user.id}});if(user.disabledAt||user.removedAt||user.role!=='ENGINEER')throw new ApiError(403,'ACCOUNT_DISABLED','Your account is disabled. Local work is preserved.');
    const prior=await tx.submissionAttempt.findUnique({where:{organizationId_userId_attemptId:{organizationId:user.organizationId,userId:user.id,attemptId:data.submissionAttemptId}}});
    if(prior){if(prior.payloadHash!==payloadHash||prior.clientReportId!==data.clientReportId)throw new ApiError(409,'IDEMPOTENCY_CONFLICT','This attempt has a different frozen payload.');if(prior.status==='cancelled')throw new ApiError(409,'ATTEMPT_CANCELLED','This attempt was cancelled and cannot be accepted.');return {created:false,receipt:await tx.receipt.findUniqueOrThrow({where:{id:prior.receiptId!}})};}
    const existing=await tx.report.findUnique({where:{organizationId_clientReportId:{organizationId:user.organizationId,clientReportId:data.clientReportId}}});
    if(existing)throw new ApiError(409,'REPORT_ALREADY_ACCEPTED','This report was already accepted.',[],existing.userId===user.id?{receipt:await receiptFor(tx,existing.id)}:{});
    const entitlement=await tx.offlineEntitlement.findFirst({where:{id:data.entitlementId,userId:user.id,organizationId:user.organizationId}});
    const confirmed=new Date(data.confirmedAt);
    if(!entitlement||!entitlement.allowedTemplates.includes(data.templateId)||confirmed<entitlement.issuedAt||confirmed>entitlement.expiresAt||confirmed.getTime()>Date.now()+120000)throw new ApiError(403,'ENTITLEMENT_INVALID','The report is outside its authorized offline lease. Local work is preserved.');
    const version=await tx.templateVersion.findFirst({where:{id:data.versionId,templateId:data.templateId,organizationId:user.organizationId}});if(!version)notFound();
    if(version.disabledAt)throw new ApiError(422,'VERSION_DISABLED','The report version is disabled. Local work is preserved.');
    const schema=parse(templateSchema,version.schema);if(schema.engineerTypeId!==entitlement.typeId||version.schemaHash!==data.schemaHash)throw new ApiError(422,'SCHEMA_MISMATCH','The report does not match its pinned template.');
    const validation=validateValues(schema,data.values as Values);if(!validation.valid)throw new ApiError(422,'FIELD_VALIDATION_FAILED','Review the highlighted fields.',validation.errors);
    if(validation.excluded.length)throw new ApiError(422,'HIDDEN_VALUES','Hidden fields must be excluded from submission.',validation.excluded.map(fieldId=>({fieldId,code:'HIDDEN_FIELD'})));
    if(data.workOrderId){
      const job=await tx.workOrder.findFirst({where:{id:data.workOrderId,organizationId:user.organizationId,assigneeId:user.id,typeId:entitlement.typeId}});
      if(!job)throw new ApiError(403,'WORK_ORDER_UNAVAILABLE','This job is not assigned to this account and form type. Local work is preserved.');
      if(data.workOrderAssignmentRevision!==undefined&&data.workOrderAssignmentRevision!==job.assignmentRevision||data.workOrderAssignmentRevision===undefined&&job.assignmentRevision>1)throw new ApiError(409,'ASSIGNMENT_CHANGED','This report belongs to an earlier assignment brief. Local work is preserved; contact your lead.');
      if(job.responseStatus!=='accepted')throw new ApiError(409,'ASSIGNMENT_NOT_ACCEPTED','Accept the current assignment before submitting its report. Your local work is preserved.');
      if(!['assigned','follow_up'].includes(job.status))throw new ApiError(409,'WORK_ORDER_NOT_OPEN','This job already has a report awaiting review or is completed. Local work is preserved.');
    }
    const report=await tx.report.create({data:{organizationId:user.organizationId,clientReportId:data.clientReportId,userId:user.id,typeId:entitlement.typeId,templateVersionId:version.id,schemaHash:version.schemaHash,values:json(validation.values),...(data.location?{location:json(data.location)}:{}),...(data.workOrderId?{workOrderId:data.workOrderId,workOrderAssignmentRevision:data.workOrderAssignmentRevision??(await tx.workOrder.findUniqueOrThrow({where:{id:data.workOrderId}})).assignmentRevision}:{}),teamId:data.workOrderId?(await tx.workOrder.findUniqueOrThrow({where:{id:data.workOrderId}})).teamId:user.teamId,confirmedAt:confirmed,originatingTimezone:data.originatingTimezone}});
    if(data.workOrderId)await tx.workOrder.update({where:{id:data.workOrderId},data:{status:'submitted',latestReportId:report.id,revision:{increment:1}}});
    const receipt=await tx.receipt.create({data:{reportId:report.id}});
    await tx.submissionAttempt.create({data:{attemptId:data.submissionAttemptId,clientReportId:data.clientReportId,organizationId:user.organizationId,userId:user.id,payloadHash,status:'accepted',receiptId:receipt.id}});
    await audit(tx,ctx,'report.accepted',report.id);return {created:true,receipt};
  });
}
export async function submissionStatus(ctx:Context,clientReportId:string){requireEngineer(ctx);const r=await db.report.findFirst({where:{organizationId:ctx.user.organizationId,userId:ctx.user.id,clientReportId}});return r?{status:'accepted',receipt:await receiptFor(db,r.id)}:{status:'unaccepted',cancelledAttempts:(await db.submissionAttempt.findMany({where:{organizationId:ctx.user.organizationId,userId:ctx.user.id,clientReportId,status:'cancelled'},select:{attemptId:true}})).map(a=>a.attemptId)};}
export async function cancelAttempt(ctx:Context,attemptId:string,input:unknown){
  requireEngineer(ctx);const data=parse(z.object({clientReportId:z.uuid(),payloadHash:z.string().regex(/^[a-f0-9]{64}$/)}).strict(),input);
  return transaction(async tx=>{
    const report=await tx.report.findFirst({where:{organizationId:ctx.user.organizationId,userId:ctx.user.id,clientReportId:data.clientReportId}});if(report)return {status:'accepted',receipt:await receiptFor(tx,report.id)};
    const key={organizationId:ctx.user.organizationId,userId:ctx.user.id,attemptId};const prior=await tx.submissionAttempt.findUnique({where:{organizationId_userId_attemptId:key}});
    if(prior&&(prior.payloadHash!==data.payloadHash||prior.clientReportId!==data.clientReportId))throw new ApiError(409,'IDEMPOTENCY_CONFLICT','Attempt identity does not match.');
    if(prior?.status==='accepted')return {status:'accepted',receipt:await tx.receipt.findUniqueOrThrow({where:{id:prior.receiptId!}})};
    if(!prior)await tx.submissionAttempt.create({data:{...key,clientReportId:data.clientReportId,payloadHash:data.payloadHash,status:'cancelled'}});
    return {status:'cancelled',attemptId};
  });
}
export async function listSubmissions(ctx:Context,url:URL){
  requirePermission(ctx,'reports.read');const {limit,...pagination}=pageParams(url);const typeId=url.searchParams.get('typeId'),engineerId=url.searchParams.get('engineerId');const from=url.searchParams.get('from'),to=url.searchParams.get('to');
  if(from&&!z.iso.date().safeParse(from).success||to&&!z.iso.date().safeParse(to).success)throw new ApiError(400,'INVALID_DATE','Use YYYY-MM-DD date filters.');
  const reports=await db.report.findMany({where:{AND:[await reportScope(ctx)],organizationId:ctx.user.organizationId,...(typeId?{typeId}:{}),...(engineerId?{userId:engineerId}:{}),...(from||to?{receivedAt:{...(from?{gte:new Date(from)}:{}),...(to?{lt:new Date(new Date(to).getTime()+86400000)}:{})}}:{})},...pagination,orderBy:[{receivedAt:'desc'},{id:'desc'}]});
  return page(await Promise.all(reports.map(async r=>({...r,engineer:publicUser(await db.user.findUniqueOrThrow({where:{id:r.userId}})),type:await db.engineerType.findUnique({where:{id:r.typeId}}),version:await db.templateVersion.findUnique({where:{id:r.templateVersionId},select:{id:true,versionNumber:true}}),receipt:await receiptFor(db,r.id)}))),limit);
}
export async function submissionDetail(ctx:Context,id:string){requirePermission(ctx,'reports.read');const report=await db.report.findFirst({where:{id,...await reportScope(ctx)}});if(!report)notFound();return {...report,review:await db.reportReview.findUnique({where:{reportId:id}}),workOrder:report.workOrderId?await db.workOrder.findUnique({where:{id:report.workOrderId}}):null,receipt:await receiptFor(db,id),engineer:publicUser(await db.user.findUniqueOrThrow({where:{id:report.userId}})),version:await db.templateVersion.findUniqueOrThrow({where:{id:report.templateVersionId}})};}
