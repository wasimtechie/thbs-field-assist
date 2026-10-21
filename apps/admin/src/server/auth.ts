import {db} from '../../../../packages/database';
import {sha256,hasPermission,permissionsFor,canUseDashboard,type Permission} from '@field-assist/contracts';
import {verify} from '@node-rs/argon2';
import {randomBytes} from 'node:crypto';
import {ApiError} from './errors';
import {z} from 'zod';
import type {User} from '@prisma/client';
export type Context={user:User;sessionId:string;audience:string};
export async function authenticate(request:Request):Promise<Context>{
  const bearer=request.headers.get('authorization');
  const cookie=request.headers.get('cookie')?.split(';').map(v=>v.trim()).find(v=>v.startsWith('fa_session='))?.slice(11);
  const token=bearer?.startsWith('Bearer ')?bearer.slice(7):cookie;
  if(!token)throw new ApiError(401,'SESSION_REQUIRED','Sign in to continue.');
  const session=await db.session.findUnique({where:{tokenHash:sha256(token)}});
  if(!session||session.revokedAt||session.expiresAt<new Date()||(bearer?session.audience!=='mobile':session.audience!=='web'))throw new ApiError(401,'SESSION_EXPIRED','Your session has expired. Sign in again.');
  const user=await db.user.findUnique({where:{id:session.userId}});
  if(!user)throw new ApiError(401,'SESSION_REQUIRED','Sign in to continue.');
  if(user.disabledAt||user.removedAt)throw new ApiError(403,'ACCOUNT_DISABLED','Your account is paused or removed. Contact your administrator.');
  if(session.audience==='web'&&!canUseDashboard(user.role)||session.audience==='mobile'&&user.role!=='ENGINEER')throw new ApiError(403,'AUDIENCE_FORBIDDEN','Use the sign-in assigned to your account.');
  if(session.audience==='web'&&!['GET','HEAD','OPTIONS'].includes(request.method))checkOrigin(request);
  return {user,sessionId:session.id,audience:session.audience};
}
export function checkOrigin(request:Request){
  const origin=request.headers.get('origin');
  if(origin!==(process.env.APP_ORIGIN??'http://localhost:3000'))throw new ApiError(403,'ORIGIN_REJECTED','The request origin is not allowed.');
}
export function requireAdmin(ctx:Context){if(ctx.user.disabledAt||ctx.user.removedAt||ctx.user.role!=='ADMIN')throw new ApiError(403,'FORBIDDEN','Administrator access is required.');}
export function requireEngineer(ctx:Context){if(ctx.user.disabledAt||ctx.user.removedAt||ctx.user.role!=='ENGINEER')throw new ApiError(403,'FORBIDDEN','An engineer account is required.');}
export function requirePermission(ctx:Context,permission:Permission){if(ctx.user.disabledAt||ctx.user.removedAt||!hasPermission(ctx.user.role,permission))throw new ApiError(403,'FORBIDDEN','Your access level does not permit this operation.');}
export const publicUser=(u:User)=>({avatarId:u.avatarId,id:u.id,name:u.name,email:u.email,role:u.role,organizationId:u.organizationId,disabledAt:u.disabledAt,removedAt:u.removedAt,employeeCode:u.employeeCode,department:u.department,jobTitle:u.jobTitle,phone:u.phone,baseLocation:u.baseLocation,teamId:u.teamId,revision:u.revision,permissions:permissionsFor(u.role)});
export async function identity(ctx:Context){
  const assignment=await db.engineerAssignment.findFirst({where:{userId:ctx.user.id,validTo:null},orderBy:{revision:'desc'}});
  const type=assignment?await db.engineerType.findUnique({where:{id:assignment.typeId}}):null;
  return {...publicUser(ctx.user),engineerType:type,assignmentRevision:assignment?.revision??0};
}
export async function login(request:Request,input:unknown){
  const parsed=z.object({email:z.email().max(254),password:z.string().min(1).max(256),audience:z.enum(['web','mobile']),deviceId:z.uuid().optional()}).strict().safeParse(input);
  if(!parsed.success)throw new ApiError(400,'INVALID_INPUT','Enter a valid email and password.');
  const data=parsed.data;if(data.audience==='web')checkOrigin(request);
  const email=data.email.toLowerCase().trim();
  const key=sha256(email);const now=new Date();
  const attempt=await db.loginAttempt.upsert({where:{key},create:{key,count:1,windowStart:now},update:{count:{increment:1}}});
  if(now.getTime()-attempt.windowStart.getTime()>900000)await db.loginAttempt.update({where:{key},data:{count:1,windowStart:now}});
  else if(attempt.count>12)throw new ApiError(429,'RATE_LIMITED','Too many sign-in attempts. Try again in 15 minutes.');
  const user=await db.user.findUnique({where:{email}});
  const valid=user?await verify(user.passwordHash,data.password):false;
  if(!user||!valid||user.disabledAt||user.removedAt||data.audience==='web'&&!canUseDashboard(user.role)||data.audience==='mobile'&&user.role!=='ENGINEER')throw new ApiError(401,'INVALID_CREDENTIALS','The email or password is incorrect or this login is not assigned to this sign-in.');
  await db.loginAttempt.deleteMany({where:{key}});
  const token=randomBytes(32).toString('base64url');const expiresAt=new Date(Date.now()+Number(process.env.SESSION_DAYS??7)*86400000);
  const session=await db.session.create({data:{tokenHash:sha256(token),userId:user.id,audience:data.audience,expiresAt}});
  const response=Response.json({user:await identity({user,sessionId:session.id,audience:data.audience}),expiresAt,...(data.audience==='mobile'?{token}:{})});
  if(data.audience==='web')response.headers.set('Set-Cookie',`fa_session=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${Number(process.env.SESSION_DAYS??7)*86400}${process.env.APP_ORIGIN?.startsWith('https:')?'; Secure':''}`);
  response.headers.set('Cache-Control','no-store');return response;
}
