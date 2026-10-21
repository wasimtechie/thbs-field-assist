import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createCaptionCues} from '../src/caption-cues.mjs';
const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const story=JSON.parse(fs.readFileSync(path.join(project,'src/story.json'),'utf8'));
const timings=JSON.parse(fs.readFileSync(path.join(project,'src/narration-timings.json'),'utf8'));
const timestamp=seconds=>new Date(Math.round(seconds*1000)).toISOString().slice(11,23).replace('.',',');
const out=[];const chapters=[];let at=0;let index=1;
for(const scene of story) {
  const duration=Math.ceil(Math.max(scene.minSeconds,timings[scene.id].seconds+2)*30)/30;
  chapters.push({id:scene.id,title:scene.label,fromSeconds:at,durationSeconds:duration,narration:scene.narration});
  const cues=createCaptionCues(scene.narration,timings[scene.id].seconds,30);
  for(const cue of cues) {
    out.push(`${index++}\n${timestamp(at+cue.startFrame/30)} --> ${timestamp(at+cue.endFrame/30)}\n${cue.lines.join('\n')}\n`);
  }
  at+=duration;
}
const dir=path.join(project,'out');fs.mkdirSync(dir,{recursive:true});
fs.writeFileSync(path.join(dir,'THBS-Field-Assist-Demo.srt'),out.join('\n'));
fs.writeFileSync(path.join(dir,'chapters.json'),JSON.stringify({fps:30,durationSeconds:at,chapters},null,2)+'\n');
console.log(`Wrote ${out.length} subtitle cues and ${chapters.length} chapters.`);
