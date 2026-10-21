import {createReadStream,readFileSync,statSync} from 'node:fs';
import path from 'node:path';
import {Readable} from 'node:stream';
import {ApiError,notFound} from './errors';
import type {Context} from './auth';
import {requireEngineer} from './auth';
export function assetResponse(ctx:Context,id:string,request:Request){
  requireEngineer(ctx);let root=process.cwd();if(root.endsWith('/apps/admin'))root=path.resolve(root,'../..');
  let manifest;try{manifest=JSON.parse(readFileSync(path.join(root,'fixtures/voice/asset-manifest.json'),'utf8'));}catch{throw new ApiError(503,'ASSETS_UNAVAILABLE','The voice package has not been installed on this server.');}
  const asset=manifest.assets.find((a:{id:string})=>a.id===id);if(!asset)notFound();
  const directory=path.join(root,'.local/model-assets');const file=path.resolve(directory,asset.relativePath);if(!file.startsWith(directory+path.sep))notFound();let size;try{size=statSync(file).size;}catch{notFound();}
  let start=0,end=size-1;const range=request.headers.get('range');if(range){const match=/^bytes=(\d+)-(\d*)$/.exec(range);if(!match)throw new ApiError(400,'INVALID_RANGE','Invalid asset range.');start=Number(match[1]);end=match[2]?Number(match[2]):end;if(start>end||end>=size)return new Response(null,{status:416,headers:{'Content-Range':`bytes */${size}`}});}
  return new Response(Readable.toWeb(createReadStream(file,{start,end})) as ReadableStream,{status:range?206:200,headers:{'Content-Type':'application/octet-stream','Content-Length':String(end-start+1),'Accept-Ranges':'bytes','ETag':`"${asset.sha256}"`,'Cache-Control':'private, max-age=31536000, immutable',...(range?{'Content-Range':`bytes ${start}-${end}/${size}`}:{})}});
}
