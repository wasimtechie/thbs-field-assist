import {spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,writeFileSync} from 'node:fs';
import {config} from 'dotenv';
import path from 'node:path';
config({quiet:true});
const data=path.resolve('.local/postgres');const log=path.resolve('.local/postgres.log');
const action=process.argv[2];
const pgEnv={...process.env,PGPASSWORD:decodeURIComponent(new URL(process.env.DATABASE_URL).password)};
const run=(cmd,args)=>{const result=spawnSync(cmd,args,{stdio:'inherit',env:pgEnv});if(result.status!==0)process.exit(result.status??1);};
if(action==='stop'){run('pg_ctl',['-D',data,'-m','fast','stop']);process.exit(0);}
if(!existsSync(path.join(data,'PG_VERSION'))){
  mkdirSync('.local',{recursive:true});
  const url=new URL(process.env.DATABASE_URL);const pass=path.resolve('.local/pg-password');
  writeFileSync(pass,decodeURIComponent(url.password),{mode:0o600});
  run('initdb',['-D',data,'-U','fieldassist','--auth-host=scram-sha-256','--auth-local=trust',`--pwfile=${pass}`]);
}
const status=spawnSync('pg_ctl',['-D',data,'status'],{stdio:'ignore'});
if(status.status!==0)run('pg_ctl',['-D',data,'-l',log,'-o','-h 127.0.0.1 -p 54329 -k /tmp','start']);
const env={...process.env,PGPASSWORD:decodeURIComponent(new URL(process.env.DATABASE_URL).password)};
const exists=spawnSync('psql',['-h','127.0.0.1','-p','54329','-U','fieldassist','-d','postgres','-tAc',"SELECT 1 FROM pg_database WHERE datname='fieldassist'"],{env,encoding:'utf8'});
if(exists.status!==0){console.error(exists.stderr);process.exit(1);}
if(exists.stdout.trim()!=='1')run('createdb',['-w','-h','127.0.0.1','-p','54329','-U','fieldassist','fieldassist']);
console.log('PostgreSQL ready at 127.0.0.1:54329.');
