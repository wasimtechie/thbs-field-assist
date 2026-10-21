import 'dotenv/config';
import {strict as assert} from 'node:assert';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
import {thbsAccounts} from '../packages/database/thbs-demo-accounts';
const base=process.env.APP_ORIGIN??'http://localhost:3000',checks:string[]=[],run=randomUUID().slice(0,8);
type Auth={cookie?:string;token?:string};
async function request(path:string,auth:Auth={},method='GET',body?:unknown){
 const r=await fetch(`${base}/api/v1/${path}`,{method,headers:{Origin:base,'Content-Type':'application/json',...(auth.cookie?{Cookie:auth.cookie}:{}),...(auth.token?{Authorization:`Bearer ${auth.token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});
 const data=await r.json();return {status:r.status,data,cookie:r.headers.get('set-cookie')?.split(';')[0]};
}
function check(name:string,value:unknown){assert.ok(value,name);checks.push(name);console.log(`PASS ${name}`);}
async function login(email:string,audience='web'){const r=await request('auth/login',{},'POST',{email,password:'123456',audience});return {...r,auth:{cookie:r.cookie,token:r.data.token} as Auth};}
const owned:string[]=[],extraOrgs:string[]=[];
let admin:Auth={};
async function main(){
 check('Database readiness',(await request('health')).status===200);
 const sessions=new Map<string,Awaited<ReturnType<typeof login>>>();
 for(const a of thbsAccounts){const l=await login(a.email.startsWith('business')?a.email.replace('business','Business'):a.email,a.role==='ENGINEER'?'mobile':'web');check(`${a.email}: password and ${a.role} login`,l.status===200&&l.data.user.role===a.role);if(a.slug)check(`${a.email}: assigned ${a.slug} form`,l.data.user.engineerType?.slug===a.slug);sessions.set(a.email,l);}
 admin=sessions.get('admin@thbs.com')!.auth;
 const ops=sessions.get('waseem@thbs.com')!.auth,viewer=sessions.get('test@thbs.com')!.auth,fibre=sessions.get('fibre1@thbs.com')!.auth;
 check('Dashboard credentials rejected at app login',(await login('admin@thbs.com','mobile')).status===401);
 check('Engineer credentials allow limited dashboard login',(await login('fibre1@thbs.com')).status===200);
 check('Engineer cannot read admin directory',(await request('admin/users',fibre)).status===403);
 check('Anonymous account listing denied',(await request('admin/users')).status===401);
 for(const [name,auth] of [['Operations Manager',ops],['Viewer',viewer]] as const){
  for(const path of ['admin/dashboard','admin/work-orders','admin/submissions','admin/reviews','admin/asset-history','admin/operations/summary'])check(`${name} can read ${path}`,(await request(path,auth)).status===200);
  for(const path of ['admin/users','admin/templates'])check(`${name} denied ${path}`,(await request(path,auth)).status===403);
 }
 check('Viewer denied engineer directory',(await request('admin/engineers',viewer)).status===403);
 check('Viewer denied assignment mutation',(await request('admin/work-orders',viewer,'POST',{})).status===403);
 check('Viewer denied report decisions',(await request(`admin/submissions/${randomUUID()}/review`,viewer,'POST',{})).status===403);
 check('Operations Manager permitted assignment validation',(await request('admin/work-orders',ops,'POST',{})).status===422);
 check('Operations Manager permitted review validation',(await request(`admin/submissions/${randomUUID()}/review`,ops,'POST',{})).status===422);
 check('Operations Manager denied account mutation',(await request('admin/users',ops,'POST',{})).status===403);
 const types=(await request('admin/engineer-types?limit=100',admin)).data.items;
 const typeId=types.find((x:any)=>x.slug==='fibre').id;
 async function create(role:string,suffix:string,extra:Record<string,unknown>={}){const r=await request('admin/users',admin,'POST',{name:`Synthetic RBAC ${suffix} ${run}`,email:`rbac-${run}-${suffix}@example.invalid`,role,initialPassword:'123456',...extra});check(`Create ${suffix}`,r.status===201);owned.push(r.data.id);check(`${suffix}: response excludes password/hash`,!('passwordHash'in r.data)&&!('initialPassword'in r.data)&&!('newPassword'in r.data));return r.data;}
 const manager=await create('TEMPLATE_MANAGER','template'),engineer=await create('ENGINEER','engineer',{typeId,employeeCode:`QA-${run}`,department:'Synthetic test',jobTitle:'QA engineer',phone:'0000000000',baseLocation:'Synthetic test location'});
 const tm=(await login(manager.email)).auth;
 for(const path of ['admin/dashboard','admin/templates','admin/engineer-types','admin/engineers','admin/devices'])check(`Template Manager can read ${path}`,(await request(path,tm)).status===200);
 for(const path of ['admin/users','admin/work-orders','admin/reviews','admin/submissions','admin/asset-history'])check(`Template Manager denied ${path}`,(await request(path,tm)).status===403);
 check('Template Manager permitted form validation',(await request('admin/templates',tm,'POST',{})).status===422);
 check('Template Manager permitted type validation',(await request('admin/engineer-types',tm,'POST',{})).status===422);
 const tmOverview=(await request('admin/dashboard',tm)).data;
 check('Template Manager overview omits report records',tmOverview.recent.length===0&&tmOverview.activity.every((a:any)=>a.action.startsWith('template.')||a.action.startsWith('type.')));
 check('Directory server search finds requested account',(await request('admin/users?kind=engineer&search=fibre1%40thbs.com',admin)).data.total===1);
 const duplicate=await request('admin/users',admin,'POST',{name:'Duplicate',email:'FIBRE1@THBS.COM',role:'ENGINEER',typeId,initialPassword:'123456'});
 check('Case-insensitive email uniqueness',duplicate.status===409);
 check('Employee ID uniqueness',(await request('admin/users',admin,'POST',{name:'Duplicate code',email:`rbac-${run}-duplicate@example.invalid`,employeeCode:`QA-${run}`,role:'VIEWER',initialPassword:'123456'})).status===409);
 let u=engineer;
 let l=await login(u.email,'mobile');check('New field account logs into assigned form',l.status===200&&l.data.user.engineerType.id===typeId);
 let r=await request(`admin/users/${u.id}`,admin,'PATCH',{expectedRevision:u.revision,name:'Synthetic profile updated',department:'Updated QA'});check('Update employee details',r.status===200&&r.data.department==='Updated QA'&&r.data.phone==='0000000000');u=r.data;
 check('Stale account revision rejected',(await request(`admin/users/${u.id}`,admin,'PATCH',{expectedRevision:1,name:'Stale'})).status===409);
 r=await request(`admin/users/${u.id}`,admin,'PATCH',{expectedRevision:u.revision,newPassword:'123456'});check('Reset password',r.status===200);u=r.data;
 check('Password reset revokes existing token',(await request('me',l.auth)).status===401);
 l=await login(u.email,'mobile');check('Reset password permits new login',l.status===200);
 r=await request(`admin/users/${u.id}`,admin,'PATCH',{expectedRevision:u.revision,status:'paused'});check('Pause preserves profile',r.status===200&&r.data.disabledAt&&r.data.department==='Updated QA');u=r.data;
 check('Pause revokes existing token',(await request('me',l.auth)).status===401);
 check('Paused account cannot log in',(await login(u.email,'mobile')).status===401);
 check('Paused filter finds account',(await request(`admin/users?status=paused&search=${encodeURIComponent(u.email)}`,admin)).data.total===1);
 r=await request(`admin/users/${u.id}`,admin,'PATCH',{expectedRevision:u.revision,status:'active'});check('Reactivate account',r.status===200&&!r.data.disabledAt);u=r.data;
 l=await login(u.email,'mobile');check('Reactivated engineer retains assignment',l.status===200&&l.data.user.engineerType.id===typeId);
 r=await request(`admin/users/${u.id}`,admin,'DELETE',{expectedRevision:u.revision});check('Remove retains account profile',r.status===200&&r.data.removedAt&&r.data.phone==='0000000000');u=r.data;
 check('Removed account token revoked',(await request('me',l.auth)).status===401);
 check('Removed account cannot log in',(await login(u.email,'mobile')).status===401);
 check('Removed account excluded from current directory',(await request(`admin/users?search=${encodeURIComponent(u.email)}`,admin)).data.total===0);
 check('Removed filter retains profile',(await request(`admin/users?status=removed&search=${encodeURIComponent(u.email)}`,admin)).data.total===1);
 r=await request(`admin/users/${u.id}`,admin,'PATCH',{expectedRevision:u.revision,status:'active'});check('Restore retains details',r.status===200&&!r.data.removedAt&&r.data.department==='Updated QA');u=r.data;
 check('Restored engineer login and form',(await login(u.email,'mobile')).data.user.engineerType.id===typeId);
 const self=sessions.get('admin@thbs.com')!.data.user;
 for(const patch of [{status:'paused'},{status:'removed'},{role:'VIEWER'}])check(`Administrator self-access protected: ${JSON.stringify(patch)}`,(await request(`admin/users/${self.id}`,admin,'PATCH',{expectedRevision:self.revision,...patch})).status===409);
 const assigned=sessions.get('fibre1@thbs.com')!.data.user;
 check('Engineer with open jobs cannot be converted to employee',(await request(`admin/users/${assigned.id}`,admin,'PATCH',{expectedRevision:assigned.revision,role:'VIEWER'})).status===409);
 const foreignOrg=await db.organization.create({data:{name:`Synthetic RBAC isolated ${run}`}});extraOrgs.push(foreignOrg.id);
 const passwordHash=await hash('123456');
 const a=await db.user.create({data:{organizationId:foreignOrg.id,name:'Synthetic admin A',email:`rbac-${run}-a@example.invalid`,role:'ADMIN',passwordHash}}),b=await db.user.create({data:{organizationId:foreignOrg.id,name:'Synthetic admin B',email:`rbac-${run}-b@example.invalid`,role:'ADMIN',passwordHash}});
 const foreignType=await db.engineerType.create({data:{organizationId:foreignOrg.id,name:'Isolated test',slug:'isolated'}});
 check('Foreign workspace account cannot update',(await request(`admin/users/${a.id}`,admin,'PATCH',{expectedRevision:a.revision,name:'Forbidden'})).status===404);
 check('Foreign engineer type cannot assign',(await request(`admin/users/${u.id}`,admin,'PATCH',{expectedRevision:u.revision,typeId:foreignType.id})).status===422);
 const al=await login(a.email),bl=await login(b.email);
 const race=await Promise.all([request(`admin/users/${b.id}`,al.auth,'PATCH',{expectedRevision:b.revision,role:'VIEWER'}),request(`admin/users/${a.id}`,bl.auth,'PATCH',{expectedRevision:a.revision,role:'VIEWER'})]);
 check('Concurrent demotions preserve one active administrator',race.filter(x=>x.status===200).length===1&&await db.user.count({where:{organizationId:foreignOrg.id,role:'ADMIN',disabledAt:null,removedAt:null}})===1);
 const survivor=await db.user.findFirstOrThrow({where:{organizationId:foreignOrg.id,role:'ADMIN',disabledAt:null,removedAt:null}});
 const inactive=await db.user.create({data:{organizationId:foreignOrg.id,name:'Synthetic paused administrator',email:`rbac-${run}-paused@example.invalid`,role:'ADMIN',passwordHash,disabledAt:new Date()}});
 const survivorAuth=survivor.id===a.id?al.auth:bl.auth;
 check('Sole active administrator can remove an already-paused admin',(await request(`admin/users/${inactive.id}`,survivorAuth,'DELETE',{expectedRevision:inactive.revision})).status===200);
 check('Engineer mobile operations remain owner-scoped',(await request('mobile/operations',fibre)).data.workOrders.every((j:any)=>j.assigneeId===assigned.id));
 const provision=await request('devices/provision',fibre,'POST',{deviceId:randomUUID(),platform:'android',appVersion:'rbac-api-check',osVersion:'Synthetic API test',model:'Synthetic account verification'});
 check('Requested fibre login provisions existing mobile package',provision.status===200&&provision.data.template.engineerTypeId===typeId&&provision.data.entitlement);
}
async function cleanup(){
 for(const id of owned){const u=await db.user.findUnique({where:{id}});if(u&&!u.removedAt){const r=await request(`admin/users/${id}`,admin,'DELETE',{expectedRevision:u.revision});assert.equal(r.status,200,'Synthetic account cleanup');}}
 for(const org of extraOrgs){const users=await db.user.findMany({where:{organizationId:org},select:{id:true,email:true}});const ids=users.map(u=>u.id);await db.session.deleteMany({where:{userId:{in:ids}}});await db.auditEvent.deleteMany({where:{organizationId:org}});await db.engineerType.deleteMany({where:{organizationId:org}});await db.user.deleteMany({where:{organizationId:org}});await db.organization.delete({where:{id:org}});}
 const devices=await db.device.findMany({where:{appVersion:'rbac-api-check',model:'Synthetic account verification'},select:{id:true}});const deviceIds=devices.map(d=>d.id);
 await db.offlineEntitlement.deleteMany({where:{deviceId:{in:deviceIds}}});await db.device.deleteMany({where:{id:{in:deviceIds}}});
 await db.$disconnect();
}
main().then(()=>{writeFileSync('docs/evidence/accounts-api-checks.json',JSON.stringify({at:new Date().toISOString(),checks,passed:checks.length,scope:'Real local HTTP/API and PostgreSQL. Synthetic lifecycle fixtures; no physical-device claim.'},null,2)+'\n');console.log(`${checks.length} account/RBAC checks passed.`);}).catch(e=>{console.error(e.message);process.exitCode=1;}).finally(cleanup);
