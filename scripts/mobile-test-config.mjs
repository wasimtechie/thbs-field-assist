import {config} from 'dotenv';
import {readFileSync,writeFileSync,chmodSync} from 'node:fs';
config({quiet:true});
if(!process.env.SEED_ENGINEER_PASSWORD)throw new Error('Run setup and seed before preparing local test credentials.');
const build=JSON.parse(readFileSync('.local/mobile-config.json','utf8'));
const file='.local/mobile-test-config.json';
writeFileSync(file,JSON.stringify({...build,TEST_ENGINEER_EMAIL:'fibre@fieldassist.demo',TEST_ENGINEER_PASSWORD:process.env.SEED_ENGINEER_PASSWORD},null,2)+'\n',{mode:0o600});
chmodSync(file,0o600);
console.log('Private test configuration prepared. Use only for integration tests, never a distributable demo build.');
