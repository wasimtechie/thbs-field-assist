import {spawnSync} from 'node:child_process';
import {config} from 'dotenv';
config({quiet:true});
const url=new URL(process.env.DATABASE_URL);
if(process.env.NODE_ENV==='production'||!process.argv.includes('--confirm-delete-demo-data')||!['localhost','127.0.0.1'].includes(url.hostname)){
  console.error('Reset refused. Only a local development database with --confirm-delete-demo-data is permitted.');process.exit(1);
}
const result=spawnSync('npx',['prisma','migrate','reset','--force','--skip-seed','--schema','packages/database/prisma/schema.prisma'],{stdio:'inherit'});
if(result.status!==0)process.exit(result.status??1);
process.exit(spawnSync('npm',['run','db:seed'],{stdio:'inherit'}).status??1);
