import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {project,root,timing,ffmpeg,ffprobe,mediaEnv} from './promo-project.mjs';

const video=path.join(root,'Field-Assist-Voice-Promo.mp4');
const run=(tool,args)=>{const r=spawnSync(tool,args,{env:mediaEnv,encoding:'utf8',maxBuffer:8*1024*1024});assert.equal(r.status,0,r.stderr);return r;};
const probe=JSON.parse(run(ffprobe,['-v','error','-show_streams','-show_format','-of','json',video]).stdout);
const picture=probe.streams.find(s=>s.codec_type==='video'),sound=probe.streams.find(s=>s.codec_type==='audio');
assert.equal(picture.width,1920);assert.equal(picture.height,1080);assert.equal(picture.r_frame_rate,'30/1');
assert.equal(picture.codec_name,'h264');assert.equal(sound.codec_name,'aac');
assert.equal(Number(picture.nb_frames),timing.durationInFrames);
assert.ok(Math.abs(Number(probe.format.duration)-timing.durationSeconds)<.12);
assert.ok(!probe.streams.some(s=>s.codec_type==='subtitle'),'Avoid duplicate automatic subtitles over burned-in text.');
const decode=run(ffmpeg,['-v','error','-i',video,'-c:v','rawvideo','-c:a','pcm_s16le','-f','null','-']);assert.equal(decode.stderr,'');
const levels=run(ffmpeg,['-hide_banner','-nostats','-i',video,'-vn','-af','loudnorm=I=-14:TP=-1:LRA=9:print_format=json','-c:a','pcm_s16le','-f','null','-']).stderr;
const loudness=JSON.parse(levels.slice(levels.lastIndexOf('{'),levels.indexOf('}',levels.lastIndexOf('{'))+1));
assert.ok(Number(loudness.input_i)>-16&&Number(loudness.input_i)<-12,'Master must be near −14 LUFS.');
assert.ok(Number(loudness.input_tp)<0,'True peak must remain below digital clipping.');
// Remotion's compact FFmpeg omits blackdetect; inspect every decoded frame
// at 160×90 instead. This detects blank exports, not scene brightness changes.
const raw=spawnSync(ffmpeg,['-v','error','-i',video,'-an','-vf','scale=160:90','-pix_fmt','gray','-c:v','rawvideo','-f','rawvideo','-'],{env:mediaEnv,maxBuffer:256*1024*1024});
assert.equal(raw.status,0,raw.stderr?.toString());
const pixels=160*90;assert.equal(raw.stdout.length,timing.durationInFrames*pixels);
const blackEvents=[];
for(let frame=0;frame<timing.durationInFrames;frame++){let dark=0;for(let p=frame*pixels;p<(frame+1)*pixels;p++)if(raw.stdout[p]<=3)dark++;if(dark/pixels>.98)blackEvents.push(frame);}
assert.equal(blackEvents.length,0,`Unexpected blank frames: ${blackEvents.join(',')}`);
for(const cue of timing.captions){assert.ok(cue.to>cue.from);assert.ok(cue.from>=0&&cue.to<=timing.durationInFrames);}
const components=['word-gather','phone-frame','screen-recording','portal-intro','dot-bloom','channel-thread','capture-reveal','announce-title','reel-collage'];
const source=fs.readFileSync(path.join(project,'src/voice-promo/VoicePromo.tsx'),'utf8');
for(const name of components)assert.ok(source.includes(`snap-cn/${name}`));
const digest=crypto.createHash('sha256').update(fs.readFileSync(video)).digest('hex');
fs.writeFileSync(video+'.sha256',`${digest}  ${path.basename(video)}\n`);
const report={title:'Field Assist — voice promo',verifiedAt:new Date().toISOString(),file:path.basename(video),bytes:fs.statSync(video).size,sha256:digest,durationSeconds:Number(probe.format.duration),width:1920,height:1080,fps:30,frames:timing.durationInFrames,videoCodec:'h264',audioCodec:'aac',captions:timing.captions.length,components,decode:'passed',blackFrameEvents:blackEvents,loudness,claimsSource:'voice-promo/FACTS.md',scope:'Illustrative synthetic UI and locally synthesized dialogue; edited pacing is not a live app benchmark. The 0.45 s number is separately scoped Android-emulator recognition evidence.',limits:['Full-app phone speed, RAM, battery and thermals remain pending.','Integration and fine-tuning are proposed scoped engagements.'],published:false};
report.soundtrack={revision:timing.musicRevision,timedAccents:timing.soundEvents?.length??0,speechToMusic:timing.musicBalance};
fs.writeFileSync(path.join(project,'out/voice-promo/verification.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify(report,null,2));
