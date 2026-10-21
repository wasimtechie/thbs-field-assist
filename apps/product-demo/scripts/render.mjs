import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {renderMedia} from '@remotion/renderer';
import {prepare,project} from './project.mjs';
import './captions.mjs';
const {serveUrl,composition}=await prepare();
const raw=path.join(project,'out/demo-render.mp4');
const final=path.resolve(project,'../../THBS-Field-Assist-Demo.mp4');
const captions=path.join(project,'out/THBS-Field-Assist-Demo.srt');
let last=-1;
console.log(`Rendering ${composition.durationInFrames} frames at 1920×1080 / 30 fps.`);
await renderMedia({serveUrl,composition,outputLocation:raw,codec:'h264',audioCodec:'aac',crf:19,pixelFormat:'yuv420p',concurrency:3,logLevel:'error',onProgress:({progress})=>{const step=Math.floor(progress*20);if(step!==last){console.log(`Render ${step*5}%`);last=step;}}});
// Captions are in the picture. Keep the SRT separate so players cannot display
// a second, automatically enabled subtitle copy over the visible text.
const mux=spawnSync('ffmpeg',['-y','-v','error','-i',raw,'-map','0:v:0','-map','0:a:0','-c','copy','-metadata','title=THBS Field Assist — Product Demo','-movflags','+faststart',final],{stdio:'inherit'});
if(mux.status!==0)throw new Error('Caption mux failed; raw render retained.');
fs.copyFileSync(captions,path.resolve(project,'../../THBS-Field-Assist-Demo.srt'));
console.log(`Saved ${final} (${(fs.statSync(final).size/1024/1024).toFixed(1)} MiB), with visible burned-in captions and adjacent English SRT.`);
