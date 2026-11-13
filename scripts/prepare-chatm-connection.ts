import {randomBytes} from 'node:crypto';
import {existsSync,readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {db} from '../packages/database';
import {sha256} from '@field-assist/contracts';

async function main(){
  if(process.env.NODE_ENV==='production'||!['localhost','127.0.0.1'].includes(new URL(process.env.DATABASE_URL!).hostname))throw Error('Use the local demo database.');
  const job=await db.workOrder.findUniqueOrThrow({where:{id:'80000000-0000-4000-8006-000000000001'}});
  if(!job.title.startsWith('S1')||!job.site.startsWith('Fictional demo property'))throw Error('Expected the existing synthetic S1 job.');
  const file='.local/chatm-field-assist-connection.json';mkdirSync('.local',{recursive:true});
  let key:string;
  if(existsSync(file)){
    const saved=JSON.parse(readFileSync(file,'utf8')) as {key:string;organizationId:string};
    if(saved.organizationId!==job.organizationId)throw Error('Connection belongs to a different workspace.');
    key=saved.key;
    const current=await db.chatmConnectionKey.findUnique({where:{tokenHash:sha256(key)}});
    if(!current||current.revokedAt)throw Error('Existing connection was revoked; rotate explicitly instead of silently re-enabling it.');
  }else{
    key='fa_chatm_'+randomBytes(32).toString('base64url');
    await db.chatmConnectionKey.create({data:{organizationId:job.organizationId,label:'Chatm local demo · read customer jobs',tokenHash:sha256(key)}});
    writeFileSync(file,JSON.stringify({origin:'http://127.0.0.1:3002',organizationId:job.organizationId,key,testCustomerEmail:'customer@fieldassist.demo'},null,2),{flag:'wx',mode:0o600});
  }
  // An explicit customer link; no promised visit/activation is inferred from the job due date or engineer test.
  await db.customerJobStatus.upsert({where:{workOrderId:job.id},update:{},create:{workOrderId:job.id,organizationId:job.organizationId,customerEmail:'customer@fieldassist.demo',updatedBy:job.createdBy}});
  console.log('Local read-only connection prepared. Existing S1 linked to customer@fieldassist.demo; submitted summaries stay unchanged. Credentials saved privately.');
}
main().finally(()=>db.$disconnect());
