import 'dotenv/config';
import {mkdirSync,writeFileSync,chmodSync} from 'node:fs';
import {db} from '../packages/database';
import {seedThbsAccounts,thbsAccounts} from '../packages/database/thbs-demo-accounts';
async function main(){
 await seedThbsAccounts({resetExisting:true});
 mkdirSync('.local',{recursive:true});
 const file='.local/thbs-test-accounts.json';
 writeFileSync(file,JSON.stringify({scope:'User-requested local demo credentials',password:'123456',accounts:thbsAccounts},null,2)+'\n',{mode:0o600});chmodSync(file,0o600);
 console.log('Provisioned the 10 unique requested THBS accounts. Profiles, engineer types and dashboard roles assigned; previous report history retained.');
}
main().finally(()=>db.$disconnect());
