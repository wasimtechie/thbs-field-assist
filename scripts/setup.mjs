import {generateKeyPairSync,randomBytes} from 'node:crypto';
import {existsSync,mkdirSync,writeFileSync} from 'node:fs';
if(existsSync('.env')){console.log('Existing .env preserved.');process.exit(0);}
mkdirSync('.local',{recursive:true});
const {privateKey,publicKey}=generateKeyPairSync('ec',{namedCurve:'P-256'});
const secret=()=>randomBytes(18).toString('base64url');
const admin=secret(),engineer=secret(),database=secret();
const values={DATABASE_URL:`postgresql://fieldassist:${database}@127.0.0.1:54329/fieldassist?schema=public`,POSTGRES_PASSWORD:database,APP_ORIGIN:'http://localhost:3000',SESSION_DAYS:'7',OFFLINE_LEASE_HOURS:'72',ENTITLEMENT_PRIVATE_JWK:JSON.stringify(privateKey.export({format:'jwk'})),ENTITLEMENT_PUBLIC_JWK:JSON.stringify(publicKey.export({format:'jwk'})),ENTITLEMENT_KEY_ID:'field-assist-local-1',SEED_ADMIN_PASSWORD:admin,SEED_ENGINEER_PASSWORD:engineer,MODEL_MANIFEST_PATH:'fixtures/voice/asset-manifest.json'};
writeFileSync('.env',Object.entries(values).map(([k,v])=>`${k}='${v}'`).join('\n')+'\n',{mode:0o600});
writeFileSync('.local/mobile-config.json',JSON.stringify({API_BASE_URL:'http://127.0.0.1:3000/api/v1/',ALLOW_INSECURE_LOCAL:'true',ENTITLEMENT_PUBLIC_JWK:values.ENTITLEMENT_PUBLIC_JWK,ENTITLEMENT_KEY_ID:values.ENTITLEMENT_KEY_ID},null,2)+'\n');
writeFileSync('.local/credentials.txt',`Synthetic demo accounts\nAdmin: admin@fieldassist.demo\nPassword: ${admin}\nEngineers: fibre@fieldassist.demo, repair@fieldassist.demo, business@fieldassist.demo, survey@fieldassist.demo\nEngineer password: ${engineer}\n`,{mode:0o600});
console.log('Generated local secrets, signing keys and .env. Credentials are in .local/credentials.txt (not committed).');
