import 'dotenv/config';
import {readFileSync,writeFileSync,chmodSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {db} from '../packages/database';
const origin=process.env.APP_ORIGIN??'http://localhost:3000';
async function main(){
 const org=await db.organization.findFirstOrThrow({where:{name:{startsWith:'Synthetic collaboration verification'}},orderBy:{id:'desc'}});
 const users=await db.user.findMany({where:{organizationId:org.id}}),engineer=users.find(u=>u.name==='Repair Tester')!,lead=users.find(u=>u.name==='Repair Lead')!;
 await db.user.updateMany({where:{id:{in:[engineer.id,lead.id]}},data:{disabledAt:null}});
 async function login(email:string,audience:string){const r=await fetch(`${origin}/api/v1/auth/login`,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json'},body:JSON.stringify({email,password:'123456',audience})});if(!r.ok)throw new Error('Synthetic native login failed');return {data:await r.json(),cookie:r.headers.get('set-cookie')?.split(';')[0]};}
 const mobile=await login(engineer.email,'mobile'),web=await login(lead.email,'web');
 async function call(path:string,body:unknown,webAuth=false){const r=await fetch(`${origin}/api/v1/${path}`,{method:'POST',headers:{Origin:origin,'Content-Type':'application/json',...(webAuth?{Cookie:web.cookie!}:{Authorization:`Bearer ${mobile.data.token}`})},body:JSON.stringify(body)});if(!r.ok)throw new Error(`Native fixture request failed: ${path} ${r.status}`);return r.json();}
 const client=await db.client.findFirstOrThrow({where:{organizationId:org.id,teamId:engineer.teamId!}});
 const job=await call('admin/work-orders',{title:'Synthetic native encrypted queue proof',site:'Synthetic simulator test site',instructions:'Synthetic test only.',assetReference:`NATIVE-${randomUUID().slice(0,8)}`,assigneeId:engineer.id,clientId:client.id,priority:'normal',dueAt:new Date(Date.now()+86400000).toISOString()},true);
 const provision=await call('devices/provision',{deviceId:randomUUID(),platform:'ios',appVersion:'collaboration-native-proof',osVersion:'Simulator integration',model:'Synthetic SQLCipher proof fixture'}),conversation=await call('conversations',{recipientId:lead.id});
 const build=JSON.parse(readFileSync('.local/mobile-config.json','utf8'));
 const config={...build,TEST_COLLAB_OWNER:engineer.id,TEST_COLLAB_TOKEN:mobile.data.token,TEST_COLLAB_LEAD_COOKIE:web.cookie,TEST_COLLAB_ORIGIN:origin,TEST_COLLAB_JOB_ID:job.id,TEST_COLLAB_CONVERSATION_ID:conversation.id,TEST_COLLAB_FORM:JSON.stringify(provision.template),TEST_COLLAB_ENTITLEMENT:provision.entitlementId};
 const file='.local/collaboration-native-config.json';writeFileSync(file,JSON.stringify(config,null,2)+'\n',{mode:0o600});chmodSync(file,0o600);
 writeFileSync('.local/collaboration-native-fixture.json',JSON.stringify({organizationId:org.id,userIds:[engineer.id,lead.id]},null,2)+'\n',{mode:0o600});console.log('Private native test configuration prepared. Never use this file to build a distributable app.');
}
main().catch(e=>{console.error(e.message);process.exitCode=1;}).finally(()=>db.$disconnect());
