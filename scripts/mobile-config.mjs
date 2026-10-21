import {config} from 'dotenv';
import {mkdirSync,writeFileSync} from 'node:fs';
config({quiet:true});
if(!process.env.ENTITLEMENT_PUBLIC_JWK)throw new Error('Run npm run setup first.');
mkdirSync('.local',{recursive:true});
writeFileSync('.local/mobile-config.json',JSON.stringify({API_BASE_URL:'http://127.0.0.1:3000/api/v1/',ALLOW_INSECURE_LOCAL:'true',ENTITLEMENT_PUBLIC_JWK:process.env.ENTITLEMENT_PUBLIC_JWK,ENTITLEMENT_KEY_ID:process.env.ENTITLEMENT_KEY_ID??'field-assist-local-1'},null,2)+'\n');
console.log('Public mobile build configuration generated. Use a reachable trusted HTTPS API address on physical devices.');
