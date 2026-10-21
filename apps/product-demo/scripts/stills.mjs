import fs from 'node:fs';
import path from 'node:path';
import {renderStill} from '@remotion/renderer';
import {prepare,project} from './project.mjs';
const {serveUrl,composition}=await prepare();
const story=JSON.parse(fs.readFileSync(path.join(project,'src/story.json'),'utf8'));
const timings=JSON.parse(fs.readFileSync(path.join(project,'src/narration-timings.json'),'utf8'));
const dir=path.join(project,'out/stills');fs.mkdirSync(dir,{recursive:true});
let frame=0;
for(const scene of story) {
  const duration=Math.ceil(Math.max(scene.minSeconds,timings[scene.id].seconds+2)*30);
  await renderStill({serveUrl,composition,frame:frame+Math.min(duration-20,scene.id==='intro'?260:scene.id==='messages'?325:260),output:path.join(dir,`${scene.id}.png`),imageFormat:'png',logLevel:'error'});
  console.log(`Checked still: ${scene.id}`);
  frame+=duration;
}
console.log(`Composition: ${composition.width}×${composition.height}, ${composition.fps} fps, ${(composition.durationInFrames/composition.fps).toFixed(1)} seconds`);
