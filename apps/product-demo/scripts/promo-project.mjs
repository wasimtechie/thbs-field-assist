import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';
import {bundle} from '@remotion/bundler';
import {selectComposition} from '@remotion/renderer';

export const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
export const root=path.resolve(project,'../..');
export const timing=JSON.parse(fs.readFileSync(path.join(project,'src/voice-promo/timing.json'),'utf8'));
const native=fs.readdirSync(path.join(project,'node_modules/@remotion')).find(n=>n.startsWith('compositor-')&&fs.existsSync(path.join(project,'node_modules/@remotion',n,process.platform==='win32'?'ffmpeg.exe':'ffmpeg')));
if(!native)throw new Error('Install the Remotion dependencies before rendering.');
export const nativeDir=path.join(project,'node_modules/@remotion',native);
export const mediaEnv={...process.env,DYLD_LIBRARY_PATH:nativeDir,LD_LIBRARY_PATH:nativeDir};
const mediaPython=path.join(root,'.local/voice-lab/.venv/bin/python');
const fullFfmpeg=fs.existsSync(mediaPython)?spawnSync(mediaPython,['-c','import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())'],{encoding:'utf8'}):null;
export const ffmpeg=process.env.PROMO_FFMPEG??(fullFfmpeg?.status===0?fullFfmpeg.stdout.trim():path.join(nativeDir,process.platform==='win32'?'ffmpeg.exe':'ffmpeg'));
export const ffprobe=path.join(nativeDir,process.platform==='win32'?'ffprobe.exe':'ffprobe');
export async function preparePromo(){
 const serveUrl=await bundle({entryPoint:path.join(project,'src/remotion.ts'),publicDir:path.join(project,'public'),outDir:path.join(project,'.cache/voice-promo'),webpackOverride:config=>({...config,resolve:{...config.resolve,alias:{...config.resolve?.alias,'@':path.join(project,'src')}}})});
 return {serveUrl,select:id=>selectComposition({serveUrl,id,logLevel:'error'})};
}
