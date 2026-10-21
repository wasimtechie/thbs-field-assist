import 'dotenv/config';
import {strict as assert} from 'node:assert';
import {randomUUID} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {hash} from '@node-rs/argon2';
import {db} from '../packages/database';
import {schemaHash,schemaBytes} from '../packages/contracts/src';
const origin=process.env.APP_ORIGIN??'http://localhost:3000',checks:string[]=[],run=randomUUID().slice(0,8),orgs:string[]=[];
type Auth={cookie?:string;token?:string};
async function req(path:string,a:Auth={},method='GET',body?:unknown){const r=await fetch(`${origin}/api/v1/${path}`,{method,headers:{Origin:origin,'Content-Type':'application/json',...(a.cookie?{Cookie:a.cookie}:{}),...(a.token?{Authorization:`Bearer ${a.token}`} :{})},...(body===undefined?{}:{body:JSON.stringify(body)})});return {status:r.status,data:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]};}
function check(n:string,v:unknown){assert.ok(v,n);checks.push(n);console.log(`PASS ${n}`);}
async function login(email:string,audience='web'){const r=await req('auth/login',{},'POST',{email,password:'123456',audience});check(`Login ${email.split('@')[0]} ${audience}`,r.status===200);return {cookie:r.cookie,token:r.data.token};}
async function main(){
 check('Database ready',(await req('health')).status===200);const org=await db.organization.create({data:{name:`Synthetic workspace verification ${run}`}});orgs.push(org.id);const passwordHash=await hash('123456'),users:any={},auth:Record<string,Auth>={};
 for(const [key,role] of [['admin','ADMIN'],['lead','TEAM_LEAD'],['otherlead','TEAM_LEAD'],['sales','SALES'],['engineer','ENGINEER'],['otherengineer','ENGINEER'],['viewer','VIEWER']]){users[key]=await db.user.create({data:{organizationId:org.id,email:`workspace-${run}-${key}@example.invalid`,name:'QA '+key,passwordHash,role}});auth[key]=await login(users[key].email);}
 const mobile=await login(users.engineer.email,'mobile'),a=auth.admin,l=auth.lead,e=auth.engineer,s=auth.sales;
 const ta=await db.team.create({data:{organizationId:org.id,name:'QA Fibre',department:'QA',leadId:users.lead.id}}),tb=await db.team.create({data:{organizationId:org.id,name:'QA Repair',department:'QA',leadId:users.otherlead.id}});
 await db.user.update({where:{id:users.engineer.id},data:{teamId:ta.id}});await db.user.update({where:{id:users.otherengineer.id},data:{teamId:tb.id}});
 const client=await db.client.create({data:{organizationId:org.id,name:'Synthetic client',teamId:ta.id,createdBy:users.sales.id}}),wrong=await db.client.create({data:{organizationId:org.id,name:'Other client',teamId:tb.id,createdBy:users.sales.id}});
 const type=await db.engineerType.create({data:{organizationId:org.id,name:'QA Fibre',slug:'fibre'}}),templateId=randomUUID(),versionId=randomUUID(),original=await db.templateVersion.findFirstOrThrow({where:{templateId:'40000000-0000-4000-8000-000000000001'},orderBy:{versionNumber:'desc'}}),schema:any={...(original.schema as object),templateId,engineerTypeId:type.id};
 await db.template.create({data:{id:templateId,organizationId:org.id,typeId:type.id,name:'QA form'}});await db.templateVersion.create({data:{id:versionId,templateId,organizationId:org.id,versionNumber:1,schema,canonicalSchema:schemaBytes(schema),schemaHash:schemaHash(schema),publishedBy:users.admin.id}});await db.template.update({where:{id:templateId},data:{currentPublishedVersionId:versionId}});await db.engineerType.update({where:{id:type.id},data:{defaultTemplateId:templateId}});await db.engineerAssignment.create({data:{userId:users.engineer.id,typeId:type.id,revision:1}});
 let r=await req('boards',l,'POST',{name:'Fibre pilot board',teamId:ta.id,clientId:client.id});check('Team Lead creates a board for own squad',r.status===201);const board=r.data;
 check('Lead cannot create another squad board',(await req('boards',l,'POST',{name:'Forbidden',teamId:tb.id})).status===422);
 check('Board rejects client routed to another squad',(await req('boards',l,'POST',{name:'Wrong route',teamId:ta.id,clientId:wrong.id})).status===422);
 check('Sales board requires a routed client',(await req('boards',s,'POST',{name:'Sales board',teamId:ta.id})).status===422);
 check('Engineer cannot create boards',(await req('boards',e,'POST',{name:'Forbidden',teamId:ta.id})).status===403);
 const otherBoard=await db.jobBoard.create({data:{organizationId:org.id,teamId:tb.id,name:'Other squad board',createdBy:users.otherlead.id}});
 check('Lead board listing excludes other squad',(await req('boards',l)).data.items.every((b:any)=>b.teamId===ta.id));check('Engineer has no unassigned boards',(await req('boards',e)).data.items.length===0);
 const input={title:'Synthetic time visit',site:'Synthetic site',assigneeId:users.engineer.id,clientId:client.id,boardId:board.id,priority:'normal',dueAt:new Date(Date.now()+86400000).toISOString()};
 check('Job rejects mismatched board',(await req('admin/work-orders',l,'POST',{...input,boardId:otherBoard.id})).status===422);
 r=await req('admin/work-orders',l,'POST',input);check('Lead assigns job to own board',r.status===201);const job=r.data;
 const otherJob=(await req('admin/work-orders',l,'POST',{...input,title:'Second synthetic visit'})).data;
 check('Engineer sees board with own assigned job',(await req('boards',e)).data.items.some((b:any)=>b.id===board.id));check('Board filter limits permitted job rows',(await req('admin/work-orders?boardId='+otherBoard.id,e)).data.total===0);
 r=await req('me/profile',mobile,'PATCH',{avatarId:'vibrent_3'});check('Engineer can select own catalogue avatar',r.status===200&&r.data.avatarId==='vibrent_3'&&!('passwordHash'in r.data));
 check('External avatar URL rejected',(await req('me/profile',e,'PATCH',{avatarId:'https://example.invalid/tracker.png'})).status===422);
 check('Profile cannot escalate own role',(await req('me/profile',e,'PATCH',{avatarId:'',role:'ADMIN'})).status===422);
 const brief=(await req('admin/work-orders?jobId='+job.id,e)).data.items[0];check('Job brief contains assigned by and to avatars',brief.assignedBy.id===users.lead.id&&brief.assignee.avatarId==='vibrent_3');
 check('Fuzzy directory includes selected avatar',(await req('directory?search=engineer',e)).data.items.some((p:any)=>p.id===users.engineer.id&&p.avatarId==='vibrent_3'));
 const visitId=randomUUID(),baseTime=Date.now()-3600000,fix=(t:number)=>({latitude:12.97,longitude:77.59,accuracyMeters:8,capturedAt:new Date(t).toISOString(),isMocked:true}),event=(action:string,sequence:number,offset:number,visit=visitId)=>({requestId:randomUUID(),visitId:visit,assignmentRevision:1,action,sequence,occurredAt:new Date(baseTime+offset).toISOString(),...(['check_in','check_out'].includes(action)?{location:fix(baseTime+offset)}:{})});
 const start=event('check_in',1,0),path=`work-orders/${job.id}/time-events`;
 check('Pending assignment cannot check in',(await req(path,mobile,'POST',start)).status===409);
 await req(`work-orders/${job.id}/response`,mobile,'POST',{requestId:randomUUID(),assignmentRevision:1,decision:'accepted'});
 await req(`work-orders/${otherJob.id}/response`,mobile,'POST',{requestId:randomUUID(),assignmentRevision:1,decision:'accepted'});
 check('Check-in requires location',(await req(path,mobile,'POST',{...start,location:undefined})).status===422);
 r=await req(path,mobile,'POST',start);check('Accepted engineer checks in with device location',r.status===201&&r.data.state==='working'&&r.data.events.length===1);
 const firstId=r.data.events[0].id;check('Lost check-in response retry is idempotent',(await req(path,mobile,'POST',start)).data.events[0].id===firstId);
 check('Time request ID cannot change content',(await req(path,mobile,'POST',{...start,note:'Changed'})).status===409);
 check('Only one active visit per engineer',(await req(`work-orders/${otherJob.id}/time-events`,mobile,'POST',event('check_in',1,1000,randomUUID()))).status===409);
 check('Active visit prevents reassignment edit',(await req('admin/work-orders/'+job.id,l,'PATCH',{...input,expectedRevision:job.revision})).status===409);
 check('Time sequence gaps rejected',(await req(path,mobile,'POST',event('break_start',3,10000))).status===409);
 check('Cannot resume when no break started',(await req(path,mobile,'POST',event('break_end',2,10000))).status===409);
 check('Another engineer cannot record this visit',(await req(path,auth.otherengineer,'POST',event('break_start',2,10000))).status===404);
 check('Admin cannot record engineer attendance',(await req(path,a,'POST',event('break_start',2,10000))).status===403);
 const pause=event('break_start',2,1200000);r=await req(path,mobile,'POST',pause);check('Break start records exact sequence',r.status===201&&r.data.state==='break');
 check('Clock rollback rejected',(await req(path,mobile,'POST',event('break_end',3,1100000))).status===422);
 check('Resume records working state',(await req(path,mobile,'POST',event('break_end',3,1800000))).data.state==='working');
 const checkout=event('check_out',4,3000000);r=await req(path,mobile,'POST',checkout);check('Check-out closes visit with exact durations',r.status===201&&r.data.state==='closed'&&r.data.siteSeconds===3000&&r.data.workSeconds===2400&&r.data.breakSeconds===600);
 check('Check-out retry does not duplicate history',(await req(path,mobile,'POST',checkout)).data.events.length===4);
 check('Closed visit cannot append a new event',(await req(path,mobile,'POST',event('break_start',5,3100000))).status===409);
 check('Own timesheet appears in app',(await req('time-tracking',mobile)).data.items.length===1);
 check('Other engineer cannot read colleague timesheet',(await req('time-tracking?userId='+users.engineer.id,auth.otherengineer)).data.items.length===0);
 check('Responsible lead sees squad timesheet',(await req('time-tracking',l)).data.items.length===1);
 check('Other lead cannot read time by job filter',(await req('time-tracking?jobId='+job.id,auth.otherlead)).data.items.length===0);
 check('Sales has no personal timesheet access',(await req('time-tracking',s)).status===403);
 check('Viewer can inspect time without recording',(await req('time-tracking',auth.viewer)).data.items.length===1);
 let immutable=false;try{await db.timeEvent.update({where:{id:firstId},data:{note:'Forbidden edit'}});}catch{immutable=true;}check('Database preserves immutable action history',immutable);
 check('Malformed user time filter rejected',(await req('time-tracking?userId=bad',a)).status===400);
 const future=event('check_in',1,0,randomUUID());future.occurredAt=new Date(Date.now()+600000).toISOString();future.location=fix(Date.now()+600000);check('Future phone clock rejected',(await req(`work-orders/${otherJob.id}/time-events`,mobile,'POST',future)).status===422);
 const foreign=await db.organization.create({data:{name:`Synthetic workspace foreign ${run}`}});orgs.push(foreign.id);const foreignUser=await db.user.create({data:{organizationId:foreign.id,name:'Foreign admin',email:`workspace-${run}-foreign@example.invalid`,role:'ADMIN',passwordHash}}),fa=await login(foreignUser.email);
 check('Foreign organisation sees no time records',(await req('time-tracking?jobId='+job.id,fa)).data.items.length===0);
 check('Foreign organisation sees no boards',(await req('boards',fa)).data.items.length===0);
}
async function cleanup(){for(const organizationId of orgs){const users=await db.user.findMany({where:{organizationId},select:{id:true}});await db.session.updateMany({where:{userId:{in:users.map(u=>u.id)}},data:{revokedAt:new Date()}});await db.user.updateMany({where:{organizationId},data:{disabledAt:new Date()}});}await db.$disconnect();}
main().then(()=>{writeFileSync('docs/evidence/workspace-api.json',JSON.stringify({at:new Date().toISOString(),passed:checks.length,checks,scope:'Real local HTTP/PostgreSQL; isolated synthetic organisations, no hardware location or employee messages. Time and assignment history preserved; fixture users disabled and sessions revoked.'},null,2)+'\n');console.log(`${checks.length} workspace checks passed.`);}).catch(e=>{console.error(e.message);process.exitCode=1;}).finally(cleanup);
