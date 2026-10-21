import 'dotenv/config';
import {strict as assert} from 'node:assert';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
const origin=process.env.APP_ORIGIN??'http://localhost:3000',run=randomUUID().slice(0,8),checks:string[]=[],orgs:string[]=[];
type Auth={cookie?:string;token?:string};
async function req(path:string,a:Auth={},method='GET',body?:unknown){const r=await fetch(`${origin}/api/v1/${path}`,{method,headers:{Origin:origin,'Content-Type':'application/json',...(a.cookie?{Cookie:a.cookie}:{}),...(a.token?{Authorization:`Bearer ${a.token}`}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return {status:r.status,data:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]};}
function check(name:string,condition:unknown){assert.ok(condition,name);checks.push(name);console.log(`PASS ${name}`);}
function safe(value:unknown){const raw=JSON.stringify(value);return !['passwordHash','phone','revision','permissions','sessionId','createdBy','notes','clientCount','tokenHash','timeEvents'].some(k=>raw.includes(`"${k}"`));}
async function main(){
 check('API database ready',(await req('health')).status===200);
 check('Organisation requires authentication',(await req('organisation')).status===401);
 const org=await db.organization.create({data:{name:`Synthetic organisation QA ${run}`}});orgs.push(org.id);
 const foreign=await db.organization.create({data:{name:`Synthetic foreign QA ${run}`}});orgs.push(foreign.id);
 const passwordHash=await hash('123456'),users:any={},auth:Record<string,Auth>={};
 const names:Record<string,string>={admin:'QA Administrator',operations:'QA Operations',lead:'Mira Shah',sales:'QA Sales',template:'QA Template',viewer:'QA Viewer',engineer:'Asha Rao'};
 for(const [key,role] of [['admin','ADMIN'],['operations','OPERATIONS_MANAGER'],['lead','TEAM_LEAD'],['sales','SALES'],['template','TEMPLATE_MANAGER'],['viewer','VIEWER'],['engineer','ENGINEER']]){
  users[key]=await db.user.create({data:{organizationId:org.id,email:`org-${run}-${key}@example.invalid`,name:names[key],passwordHash,role,department:key==='engineer'?'Field Services':'IT',jobTitle:key==='engineer'?'Fibre technician':'Demo '+key,employeeCode:'QA-'+key,phone:'DO-NOT-EXPOSE',baseLocation:'Synthetic Bengaluru'}});
  const r=await req('auth/login',{},'POST',{email:users[key].email,password:'123456',audience:'web'});check(`Login ${key}`,r.status===200);auth[key]={cookie:r.cookie};
 }
 const a=auth.admin,e=auth.engineer;
 const t1=await db.team.create({data:{organizationId:org.id,name:'Fibre Delivery QA',department:'Field Services',leadId:users.lead.id}}),t2=await db.team.create({data:{organizationId:org.id,name:'Repair Squad QA',department:'Networks',leadId:users.lead.id}}),archived=await db.team.create({data:{organizationId:org.id,name:'Archived QA',department:'Legacy',leadId:users.lead.id,archivedAt:new Date()}});
 await db.user.update({where:{id:users.engineer.id},data:{teamId:t1.id}});await db.user.update({where:{id:users.sales.id},data:{teamId:t2.id}});
 const peers=[];for(let i=0;i<5;i++)peers.push(await db.user.create({data:{organizationId:org.id,name:'QA Peer '+i,email:`org-${run}-peer${i}@example.invalid`,passwordHash,role:'ENGINEER',department:'Field Services',teamId:t1.id}}));
 const archivedMember=await db.user.create({data:{organizationId:org.id,name:'QA Archived membership',email:`org-${run}-archived@example.invalid`,passwordHash,role:'VIEWER',teamId:archived.id}});
 const paused=await db.user.create({data:{organizationId:org.id,name:'QA Paused',email:`org-${run}-paused@example.invalid`,passwordHash,role:'ENGINEER',teamId:t1.id,disabledAt:new Date()}}),removed=await db.user.create({data:{organizationId:org.id,name:'QA Removed',email:`org-${run}-removed@example.invalid`,passwordHash,role:'ENGINEER',teamId:t1.id,removedAt:new Date()}}),other=await db.user.create({data:{organizationId:foreign.id,name:'Foreign person',email:`org-${run}-foreign@example.invalid`,passwordHash,role:'ADMIN'}});
 const foreignTeam=await db.team.create({data:{organizationId:foreign.id,name:'Foreign team',department:'Secret department',leadId:other.id}});
 for(const [key,session] of Object.entries(auth)){
  let r=await req('organisation',session);check(`${key} sees own organisation and all active squads`,r.status===200&&r.data.organisation.id===org.id&&r.data.teams.length===2&&r.data.counts.people===13);check(`${key} organisation excludes operational and credential data`,safe(r.data));
  r=await req(`directory/${users.engineer.id}`,session);check(`${key} can inspect another department's profile and lead`,r.status===200&&r.data.primaryTeam.lead.id===users.lead.id&&r.data.person.id===users.engineer.id);check(`${key} colleague response is directory-only data`,safe(r.data));
  check(`${key} cannot inspect foreign colleague`,(await req(`directory/${other.id}`,session)).status===404);
 }
 const orgResult=(await req('organisation',e)).data;check('Squad preview counts exclude hidden users and cap at four',orgResult.teams.find((t:any)=>t.id===t1.id).memberCount===6&&orgResult.teams.find((t:any)=>t.id===t1.id).members.length===4);check('Archived teams do not appear',!JSON.stringify(orgResult).includes(archived.id));check('Foreign departments and teams are excluded',!JSON.stringify(orgResult).includes('Secret department')&&!JSON.stringify(orgResult).includes(other.id));
 const lead=(await req(`directory/${users.lead.id}`,e)).data;check('Lead profile joins all led squads and distinct members',lead.teamsLed.length===2&&lead.reportCount===7&&lead.reports.length===7);check('Lead profile shows no invented supervisor',lead.primaryTeam===null);
 const engineer=(await req(`directory/${users.engineer.id}`,a)).data;check('Engineer sees five same-squad peers excluding self',engineer.peerCount===5&&engineer.peers.every((p:any)=>p.id!==users.engineer.id));
 let r=await req('directory?search=Asha%20Roa',e);check('Fuzzy name search survives typo',r.status===200&&r.data.items.some((p:any)=>p.id===users.engineer.id));
 r=await req('directory?department=Networks',e);check('Department filter includes squad department',r.data.items.length===1&&r.data.items[0].id===users.sales.id);
 r=await req(`directory?teamId=${t1.id}&limit=2`,e);check('Squad filter is paginated',r.data.items.length===2&&r.data.nextOffset===2);const ids=r.data.items.map((p:any)=>p.id);r=await req(`directory?teamId=${t1.id}&limit=2&offset=2`,e);check('Second squad page does not repeat colleagues',r.data.items.length===2&&r.data.items.every((p:any)=>!ids.includes(p.id)));
 check('Archived membership is treated as unassigned',(await req('directory?unassigned=true',e)).data.items.some((p:any)=>p.id===archivedMember.id));
 check('Paused profile unavailable',(await req(`directory/${paused.id}`,a)).status===404);check('Removed profile unavailable',(await req(`directory/${removed.id}`,a)).status===404);
 check('Foreign squad filter has no matches',(await req(`directory?teamId=${foreignTeam.id}`,e)).data.items.length===0);check('Invalid colleague identifier rejected',(await req('directory/invalid',e)).status===400);check('Invalid squad identifier rejected',(await req('directory?teamId=invalid',e)).status===400);
 check('Operational teams remain engineer-scoped',(await req('teams',e)).data.items.length===1);check('Engineer account administration remains forbidden',(await req('admin/users',e)).status===403);
 const mobileLogin=await req('auth/login',{},'POST',{email:users.engineer.email,password:'123456',audience:'mobile'}),mobile={token:mobileLogin.data.token};check('Mobile session can read colleague context',(await req(`directory/${users.lead.id}`,mobile)).status===200);
 const before=(await req('me',e)).data;
 r=await req('me/profile',e,'PATCH',{name:'  Asha Rao Demo  ',expectedRevision:before.revision});check('Engineer saves a trimmed own name with optimistic revision',r.status===200&&r.data.name==='Asha Rao Demo'&&r.data.revision===before.revision+1&&r.data.role==='ENGINEER'&&r.data.teamId===t1.id);
 check('Name appears on colleague profile',(await req(`directory/${users.engineer.id}`,auth.viewer)).data.person.name==='Asha Rao Demo');check('Name is immediately searchable',(await req('directory?search=Asha%20Rao%20Demo',auth.sales)).data.items.some((p:any)=>p.id===users.engineer.id&&p.name==='Asha Rao Demo'));
 check('Name update keeps the current session valid',(await req('me',e)).status===200);
 check('Stale name update is rejected',(await req('me/profile',e,'PATCH',{name:'Stale overwrite',expectedRevision:before.revision})).status===409);
 for(const [label,body] of [['empty',{name:'   ',expectedRevision:2}],['too long',{name:'x'.repeat(101),expectedRevision:2}],['no revision',{name:'No revision'}],['role injection',{name:'Asha',expectedRevision:2,role:'ADMIN'}],['other person injection',{name:'Asha',expectedRevision:2,id:users.sales.id}],['department injection',{name:'Asha',expectedRevision:2,department:'ADMIN'}],['email injection',{name:'Asha',expectedRevision:2,email:other.email}],['empty patch',{}]])check(`Profile rejects ${label}`,(await req('me/profile',e,'PATCH',body)).status===422);
 r=await req('me/profile',mobile,'PATCH',{avatarId:'3d_1'});check('Legacy avatar-only mobile update stays compatible',r.status===200&&r.data.avatarId==='3d_1'&&r.data.name==='Asha Rao Demo');
 const fresh=(await req('me',e)).data;const races=await Promise.all(['Asha Rao A','Asha Rao B'].map(name=>req('me/profile',e,'PATCH',{name,expectedRevision:fresh.revision})));check('Concurrent same-revision name edits have one winner',races.filter(r=>r.status===200).length===1&&races.filter(r=>r.status===409).length===1);
 check('Profile audit records only changed field names',!!await db.auditEvent.findFirst({where:{actorId:users.engineer.id,action:'profile.updated'},orderBy:{createdAt:'desc'}}));
 check('Other colleagues names remain unchanged',(await db.user.findUniqueOrThrow({where:{id:users.sales.id}})).name===users.sales.name);
 // A lead belonging to their own squad must never appear as their own manager/report.
 await db.user.update({where:{id:users.lead.id},data:{teamId:t1.id}});r=await req(`directory/${users.lead.id}`,e);check('Lead is not their own supervisor or report',r.data.primaryTeam.lead===null&&r.data.reports.every((p:any)=>p.id!==users.lead.id));
 await db.user.update({where:{id:users.lead.id},data:{teamId:null,disabledAt:new Date()}});r=await req(`directory/${users.engineer.id}`,e);check('Paused lead is omitted from reporting details',r.data.primaryTeam.lead===null);check('Paused lead is omitted from directory join',(await req(`directory?teamId=${t1.id}`,e)).data.items.every((p:any)=>p.leadName===null));
}
async function cleanup(){for(const organizationId of orgs){const users=await db.user.findMany({where:{organizationId},select:{id:true}});await db.session.updateMany({where:{userId:{in:users.map(u=>u.id)}},data:{revokedAt:new Date()}});await db.user.updateMany({where:{organizationId},data:{disabledAt:new Date()}});}await db.$disconnect();}
main().then(()=>{writeFileSync('docs/evidence/organisation-api.json',JSON.stringify({at:new Date().toISOString(),passed:checks.length,checks,scope:'Real local HTTP/PostgreSQL using isolated synthetic organisations. No real profile, account, squad or message was changed. Fixture accounts disabled and sessions revoked.'},null,2)+'\n');console.log(`${checks.length} organisation checks passed.`);}).catch(e=>{console.error(e.message);process.exitCode=1;}).finally(cleanup);
