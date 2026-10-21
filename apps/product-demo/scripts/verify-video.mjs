import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const project=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const root=path.resolve(project,'../..');
const video=path.join(root,'THBS-Field-Assist-Demo.mp4');
const probe=spawnSync('ffprobe',['-v','error','-show_streams','-show_format','-of','json',video],{encoding:'utf8'});
assert.equal(probe.status,0,probe.stderr);
const info=JSON.parse(probe.stdout);
const picture=info.streams.find(s=>s.codec_type==='video');
const sound=info.streams.find(s=>s.codec_type==='audio');
const subtitles=info.streams.find(s=>s.codec_type==='subtitle');
assert.equal(picture.width,1920);assert.equal(picture.height,1080);assert.equal(picture.r_frame_rate,'30/1');assert.equal(picture.codec_name,'h264');assert.equal(picture.nb_frames,'4861');
assert.equal(sound.codec_name,'aac');
assert.equal(subtitles,undefined,'No second subtitle track should duplicate the burned-in captions');
const chapters=JSON.parse(fs.readFileSync(path.join(project,'out/chapters.json'),'utf8'));
assert.ok(Math.abs(Number(info.format.duration)-chapters.durationSeconds)<.1);
const decode=spawnSync('ffmpeg',['-v','error','-i',video,'-f','null','-'],{encoding:'utf8'});
assert.equal(decode.status,0,decode.stderr);assert.equal(decode.stderr,'');
const stillDir=path.join(project,'out/stills');fs.mkdirSync(stillDir,{recursive:true});
for(const c of chapters.chapters) {
  const local=c.id==='messages'?10.84:Math.min(8.67,c.durationSeconds-1);
  const frame=spawnSync('ffmpeg',['-y','-v','error','-ss',String(c.fromSeconds+local),'-i',video,'-frames:v','1',path.join(stillDir,`${c.id}.png`)],{encoding:'utf8'});
  assert.equal(frame.status,0,frame.stderr);
}
const digest=filename=>crypto.createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
const apkSha=digest(path.join(root,'Field-Assist-Android-Test.apk'));
assert.equal(apkSha,'c0c001d3d5226df2efbcf9f90294c2e565e480a44371544fa742273f04fa9108');
const player=JSON.parse(fs.readFileSync(path.join(project,'out/player-check.json'),'utf8'));
const report={
  title:'THBS Field Assist — narrated product demonstration',verifiedAt:new Date().toISOString(),
  file:'THBS-Field-Assist-Demo.mp4',bytes:fs.statSync(video).size,sha256:digest(video),durationSeconds:Number(info.format.duration),width:1920,height:1080,fps:30,frames:4861,
  videoCodec:'h264',audioCodec:'aac',burnedInCaptions:true,subtitles:`Visible English captions and adjacent SRT; ${player.captionCues} shared frame-based cues. No duplicate embedded track.`,
  framework:'Remotion 4.0.536',components:['Snapcn Orb Swarm','Snapcn Channel Thread','Snapcn Phone Frame','Snapcn Word Wheel'],
  chapters:chapters.chapters.map(({id,title,fromSeconds,durationSeconds})=>({id,title,fromSeconds,durationSeconds})),
  verification:{typecheckAndProductionBuild:'Passed; use-client directives ignored by Vite as expected in this client-only project',player,allMediaDecodedWithoutErrors:true,exportedFrameForEveryChapter:true},
  provenance:'Existing product screenshots with synthetic records; illustrative time/chat/workflow scenes. Narration synthesized locally from story text. Open-licensed fonts and avatar notices retained.',
  delivery:{localPreview:'http://localhost:3001/',loopbackOnly:true,source:'apps/product-demo/',published:false,apkGenerated:false,existingApkVersionCode:2014,existingApkSha256:apkSha},
  scope:'A narrated feature explainer and reusable composition, not a new live end-to-end application or physical-device acceptance test.'
};
fs.writeFileSync(path.join(project,'out/media-probe.json'),JSON.stringify(info,null,2)+'\n');
fs.writeFileSync(path.join(root,'docs/evidence/product-demo.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({file:report.file,duration:report.durationSeconds,bytes:report.bytes,sha256:report.sha256,chapters:report.chapters.length,decode:'PASS',subtitles:'English',apk:'Unchanged 2014'}));
