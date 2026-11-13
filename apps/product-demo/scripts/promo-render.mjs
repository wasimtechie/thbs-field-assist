import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {renderMedia,renderStill} from '@remotion/renderer';
import {preparePromo,project,root,timing,ffmpeg,mediaEnv} from './promo-project.mjs';

const out=path.join(project,'out/voice-promo');fs.mkdirSync(out,{recursive:true});
const publicDir=path.join(project,'public/voice-promo');
const {serveUrl,select}=await preparePromo();
const review=await select('Voice-Review-Still');
await renderStill({serveUrl,composition:review,frame:0,output:path.join(publicDir,'review.png'),imageFormat:'png',logLevel:'error'});
console.log('Review image ready.');
const capture=await select('Voice-Demo-Capture');
const capturePath=path.join(publicDir,'visit-capture.mp4');
// A source re-render is intentionally cheap; this is an illustrative UI, never
// a live recording or performance measurement, and must match the film source.
await renderMedia({serveUrl,composition:capture,outputLocation:capturePath,codec:'h264',crf:22,pixelFormat:'yuv420p',concurrency:2,logLevel:'error',onProgress:({progress})=>{if(progress===1)console.log('Illustrative portrait capture ready.');}});
console.log('Portrait capture rendered.');
// Bundling snapshots public/ before generated media exists. Add those new
// assets to that snapshot before the main film requests them via staticFile.
const bundledPublic=path.join(project,'.cache/voice-promo/public/voice-promo');
fs.mkdirSync(bundledPublic,{recursive:true});
for(const file of ['review.png','visit-capture.mp4'])fs.copyFileSync(path.join(publicDir,file),path.join(bundledPublic,file));
const film=await select('Field-Assist-Voice-Promo');
const stills=path.join(out,'stills');fs.mkdirSync(stills,{recursive:true});
const frames=timing.scenes.map(s=>({id:s.id,frame:s.from+Math.min(s.durationInFrames-15,s.id==='followup'?220:s.id==='adapt'?270:s.id==='close'?210:s.id==='capture'?420:120)}));
for(const [id,local] of [['followup',82],['adapt',90],['close',48]]){const s=timing.scenes.find(s=>s.id===id);frames.push({id:`${id}-animation`,frame:s.from+local});}
for(const shot of frames){
 await renderStill({serveUrl,composition:film,frame:shot.frame,output:path.join(stills,`${shot.id}.png`),imageFormat:'png',logLevel:'error'});
 console.log(`Style frame: ${shot.id}`);
}
await renderStill({serveUrl,composition:film,frame:125,output:path.join(publicDir,'poster.jpg'),imageFormat:'jpeg',jpegQuality:94,logLevel:'error'});
fs.copyFileSync(path.join(publicDir,'poster.jpg'),path.join(root,'Field-Assist-Voice-Promo.jpg'));
fs.writeFileSync(path.join(out,'shots.json'),JSON.stringify(frames,null,2)+'\n');
if(process.argv.includes('--stills')){console.log('Stills ready for visual review.');process.exit(0);}
const raw=path.join(out,'render.mp4');
let last=-1;
console.log(`Rendering ${film.durationInFrames} frames, 1920×1080 / ${film.fps} fps.`);
await renderMedia({serveUrl,composition:film,outputLocation:raw,codec:'h264',audioCodec:'aac',crf:18,pixelFormat:'yuv420p',concurrency:3,logLevel:'error',onProgress:({progress})=>{const step=Math.floor(progress*20);if(step!==last){console.log(`Promo render ${step*5}%`);last=step;}}});
const final=path.join(root,'Field-Assist-Voice-Promo.mp4');
const mux=spawnSync(ffmpeg,['-y','-v','error','-i',raw,'-map','0:v:0','-map','0:a:0','-c','copy','-metadata','title=Field Assist — Speak the visit. Complete the record.','-movflags','+faststart',final],{env:mediaEnv,encoding:'utf8'});
if(mux.status!==0)throw new Error(mux.stderr||'MP4 finalization failed. Raw render retained.');
fs.copyFileSync(final,path.join(publicDir,'Field-Assist-Voice-Promo.mp4'));
fs.copyFileSync(path.join(project,'voice-promo/Field-Assist-Voice-Promo.srt'),path.join(root,'Field-Assist-Voice-Promo.srt'));
console.log(`Ready: ${final}, ${(fs.statSync(final).size/1e6).toFixed(1)} MB, ${timing.durationSeconds}s.`);
