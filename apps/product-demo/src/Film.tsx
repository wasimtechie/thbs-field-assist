import React from 'react';
import {AbsoluteFill, Audio, Composition, Img, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {BatteryFull, Bell, CalendarClock, Camera, Check, CheckCheck, ClipboardCheck, CloudUpload, FileCheck2, FileText, GitBranch, Layers3, LockKeyhole, MapPin, MessageSquare, Mic, Network, ScanLine, Search, ShieldCheck, Sparkles, Timer, UserCheck, Users, Wifi, WifiOff} from 'lucide-react';
import {OrbSwarm} from './components/snap-cn/orb-swarm';
import {PhoneFrame} from './components/snap-cn/phone-frame';
import {ChannelThread} from './components/snap-cn/channel-thread';
import {WordWheel} from './components/snap-cn/word-wheel';
import {SnapCnUIProvider} from './lib/snap-cn-ui';
import {chapters, DURATION, FPS, HEIGHT, WIDTH, type Chapter} from './timeline';
import {Badge, Brand, BrowserShot, Callout, color, Copy, ease, font, Note, Point, snapTheme, Stage} from './visuals';
import {createCaptionCues} from './caption-cues.mjs';
import {Captions} from './Captions';
import timings from './narration-timings.json';

function Phone({asset,x=1030,y=135,scale=1.18,variant='tilt',angle=-12}:{asset:string;x?:number;y?:number;scale?:number;variant?:'flat'|'tilt'|'showcase';angle?:number}) {
  const dark=asset==='scan'||asset==='voice';
  return <div style={{position:'absolute',left:x,top:y,width:600,height:790}}><PhoneFrame scale={scale} variant={variant} tiltAngle={angle} entrance="rise" floatAmplitude={3} showDynamicIsland bezelColor="#777384" screenColor={dark?'#10111b':'#f8f8fc'} shadow="0 35px 75px #0008"><div style={{height:'100%',width:'100%',background:dark?'#10111b':'#f8f8fc'}}><div style={{height:37,padding:'9px 14px 0',display:'flex',justifyContent:'space-between',fontSize:10,fontWeight:600,color:dark?'#efedf7':'#252333'}}><span>9:41</span><span style={{display:'flex',gap:4}}><Wifi size={11}/><BatteryFull size={15}/></span></div><Img src={staticFile(`screens/${asset}.png`)} style={{display:'block',height:'calc(100% - 37px)',width:'100%',objectFit:'contain',objectPosition:'center top'}}/></div></PhoneFrame></div>;
}

function Intro({chapter}:{chapter:Chapter}) {
  const f=useCurrentFrame();
  return <><OrbSwarm script="Every request | every visit | every answer | every team | connected by | THBS Field Assist" background={color.bg} ink={color.ink} orbColor={color.primary} softness={0} speed={.49} fontFamily="Inter" mode="dark"/>
  <div style={{position:'absolute',top:885,left:0,right:0,textAlign:'center',fontSize:28,color:color.muted,opacity:ease(f,295,30)}}>One journey. From client request to reviewed field evidence.</div></>;
}

function Dispatch() {
  return <><Copy eyebrow="Client → squad → engineer" title={<>Give every job<br/><span style={{color:color.purple}}>a clear owner.</span></>} description="Connect client intake with delivery, without losing the brief.">
    <Point icon={Users} title="Route clients to the right squad"/>
    <Point icon={CalendarClock} title="Assign priority, engineer and due date" delay={55}/>
    <Point icon={Layers3} title="Organise projects on named boards" delay={85}/>
  </Copy><BrowserShot asset="board" label="THBS Field Assist / Project board" height={650} pan={80}/><Callout x={1090} y={760} title="The brief follows the job" sub="Client · squad · engineer · asset" delay={105}/></>;
}

function Mobile() {
  return <><Copy eyebrow="An engineer's workspace" title={<>Know the visit.<br/><span style={{color:color.purple}}>Own the next step.</span></>} description="A focused home for assigned work, reports and team conversations.">
    <Point icon={Bell} title="See assignment alerts in the app"/>
    <Point icon={UserCheck} title="Accept, or decline with a reason" delay={65}/>
    <div style={{marginTop:32,display:'flex',gap:12}}><Badge active>Accepted</Badge><Badge>Visible to the lead</Badge></div>
  </Copy><Phone asset="home" x={895} y={127} scale={1.12} angle={-15}/><Phone asset="jobs" x={1282} y={153} scale={1.04} angle={8}/><Note>Engineers see their own work. New alerts refresh while the app is open and connected.</Note></>;
}

function Time() {
  const f=useCurrentFrame();
  const steps=[['09:41','Checked in','Arrival location recorded'],['10:12','Break started','Pause the work clock'],['10:20','Work resumed','Continue the same visit'],['11:09','Checked out','Departure location recorded']];
  return <><Copy eyebrow="Site time & location" title={<>See the visit,<br/><span style={{color:color.purple}}>beyond the report.</span></>} description="Check-in, breaks and check-out add context to the time spent on site."><Point icon={Timer} title="Work and break durations"/><Point icon={MapPin} title="Arrival and departure snapshots" delay={65}/></Copy>
  <div style={{position:'absolute',left:850,top:202,width:890,background:'#1c1b2b',border:`1px solid ${color.line}`,borderRadius:28,padding:40,boxShadow:'0 30px 75px #0005'}}>
    <div style={{display:'flex',justifyContent:'space-between',alignItems:'center',marginBottom:35}}><span style={{fontSize:27,fontWeight:600}}>Fibre installation · Orion site</span><Badge>Sample visit</Badge></div>
    {steps.map(([time,title,detail],i)=><div key={title} style={{display:'flex',alignItems:'center',gap:25,padding:'19px 0',opacity:ease(f,28+i*45),borderTop:i?'1px solid #ffffff0b':'none',transform:`translateY(${15*(1-ease(f,28+i*45))}px)`}}>
      <span style={{fontSize:22,color:color.purple,width:74,fontVariantNumeric:'tabular-nums'}}>{time}</span><div style={{height:41,width:41,borderRadius:24,background:'#159c8b25',display:'grid',placeItems:'center',color:color.teal}}><Check size={22}/></div>
      <div><div style={{fontSize:25}}>{title}</div><div style={{fontSize:18,color:color.muted,marginTop:5}}>{detail}</div></div>
    </div>)}
    <div style={{marginTop:25,paddingTop:25,borderTop:`1px solid ${color.line}`,display:'flex',gap:55,opacity:ease(f,190)}}>{[['1h 28m','On site'],['1h 20m','Working'],['8m','Break']].map(([v,l])=><div key={l}><div style={{fontSize:38,letterSpacing:-1,color:l==='Working'?color.teal:color.ink}}>{v}</div><div style={{fontSize:17,color:color.muted,marginTop:5}}>{l}</div></div>)}</div>
  </div><Note>Deliberate location snapshots at visit events. No continuous location tracking.</Note></>;
}

function Scan() {
  const f=useCurrentFrame();
  return <><Copy eyebrow="Camera → reviewed fields" title={<>Scan the label.<br/><span style={{color:color.purple}}>Keep control.</span></>} description="On-device OCR extracts printed cable details for correction and confirmation.">
    <Point icon={Camera} title="Cable, drum, maker and batch"/>
    <Point icon={ScanLine} title="Review suggested values before Apply" delay={70}/>
    <div style={{marginTop:32}}><Badge>Manual entry stays available</Badge></div>
  </Copy><Phone asset="scan" x={1150} y={130} scale={1.15} angle={-9}/>
  <div style={{position:'absolute',left:810,top:320,width:300,padding:25,background:'#252139',border:`1px solid ${color.line}`,borderRadius:19,transform:`rotate(-4deg) translateY(${18*(1-ease(f,20))}px)`,opacity:ease(f,20)}}>
    <div style={{fontSize:13,letterSpacing:2,color:color.muted}}>SAMPLE CABLE LABEL</div><div style={{fontSize:28,fontWeight:650,margin:'22px 0 15px'}}>CBL-2026-0042</div><div style={{fontSize:19,lineHeight:1.8,color:'#d7d3e6'}}>Drum · DR-0017<br/>Maker · Demo Cable Works<br/>Fibre count · 24 cores</div>
    <div style={{height:40,marginTop:22,background:'repeating-linear-gradient(90deg,#bbb3cf 0 2px,transparent 2px 5px,#bbb3cf 5px 6px,transparent 6px 10px)'}}/>
  </div><Callout x={935} y={784} title="Review → Apply to form" delay={115}/></>;
}

function Voice() {
  const f=useCurrentFrame();
  return <><Copy eyebrow="Guided, local voice" title={<>Talk through<br/><span style={{color:color.purple}}>the work.</span></>} description="The assistant speaks first, then asks the relevant questions for the job.">
    <Point icon={Mic} title="Full, partial or not completed"/>
    <Point icon={FileCheck2} title="Validated answers fill the form" delay={65}/>
    <Point icon={LockKeyhole} title="Saved on the device before continuing" delay={105}/>
  </Copy><Phone asset="voice" x={1130} y={135} scale={1.17} variant="flat"/>
  <div style={{position:'absolute',left:814,top:453,display:'flex',alignItems:'center',gap:6,height:105,color:color.purple}}>{Array.from({length:24},(_,i)=><div key={i} style={{width:5,borderRadius:5,height:12+Math.abs(Math.sin(f*.085+i*.7))*65,background:`linear-gradient(${color.purple},${color.teal})`,opacity:.7}}/>)}</div>
  <Note>Local voice works after provisioning. Exact identifiers can still use scan or touch. Review before sending.</Note></>;
}

function Sync() {
  const f=useCurrentFrame();
  const nodes=[{icon:LockKeyhole,title:'Draft saved',sub:'Encrypted on device',tag:'LOCAL'},{icon:ClipboardCheck,title:'Review + confirm',sub:'Validated with location',tag:'CONFIRMED'},{icon:CloudUpload,title:'Queued → received',sub:'Retry the same report',tag:'DELIVERED'},{icon:UserCheck,title:'Supervisor review',sub:'Approve or follow up',tag:'HUMAN DECISION'}];
  return <><div style={{position:'absolute',left:96,top:200}}><div style={{fontSize:18,letterSpacing:3,color:color.teal,marginBottom:24}}>OFFLINE CAPTURE · CONNECTED DELIVERY</div><h1 style={{fontSize:70,letterSpacing:-2.5,lineHeight:1.07,margin:0}}>Keep the work.<br/><span style={{color:color.purple}}>Reconnect the journey.</span></h1></div>
    <div style={{position:'absolute',top:470,left:96,right:96,display:'flex',gap:25}}>{nodes.map((node,i)=>{const Icon=node.icon;const p=ease(f,20+i*60);return <React.Fragment key={node.title}><div style={{flex:1,padding:30,height:262,borderRadius:23,border:`1px solid ${i<2?'#a99afb44':'#45d0bc44'}`,background:i<2?'#262136':'#172e2e',opacity:p,transform:`translateY(${20*(1-p)}px)`}}><Icon size={36} color={i<2?color.purple:color.teal}/><div style={{fontSize:28,fontWeight:550,margin:'25px 0 13px'}}>{node.title}</div><div style={{fontSize:21,color:color.muted}}>{node.sub}</div><div style={{fontSize:13,letterSpacing:2,marginTop:25,color:i<2?color.purple:color.teal}}>{node.tag}</div></div>{i<3&&<span style={{alignSelf:'center',fontSize:28,color:color.muted,opacity:p}}>→</span>}</React.Fragment>;})}</div>
    <div style={{position:'absolute',left:98,top:798,right:98,display:'flex',alignItems:'center',gap:14,fontSize:23,color:color.muted,opacity:ease(f,110)}}><WifiOff size={25} color={color.purple}/>Offline after initial setup <span style={{margin:'0 18px',color:'#5f596c'}}>•</span><CloudUpload size={25} color={color.teal}/>Retry with the app open, unlocked and server reachable</div>
    <Note>Saved, queued, received and approved are separate states.</Note></>;
}

function Messages() {
  const people={engineer:{author:'Engineer',time:'09:48',avatar:staticFile('avatars/teams_1.png')},lead:{author:'Team Lead',time:'09:49',avatar:staticFile('avatars/teams_2.png')}};
  const messages=[{...people.engineer,text:'At the Orion site.',at:15,opens:0},{...people.engineer,text:'Cable label checked.',at:60,opens:45},{...people.engineer,text:'Access delayed. Advice?',at:110,opens:85},{...people.lead,text:'Use the east entrance.',at:190,opens:140},{...people.lead,text:'The contact is ready.',at:235,opens:220},{...people.engineer,time:'09:50',text:'Thanks. Resuming work.',at:320,opens:275}];
  return <><Copy eyebrow="App ↔ dashboard" title={<>Reach the<br/><span style={{color:color.purple}}>right person.</span></>} description="Find colleagues across departments, understand who they report to, and keep the team informed.">
    <Point icon={Search} title="Fuzzy colleague search"/>
    <Point icon={MessageSquare} title="Direct messages and squad channels" delay={70}/>
    <Point icon={CheckCheck} title="Queued mobile messages with retry" delay={105}/>
  </Copy><div style={{position:'absolute',left:810,top:204,width:1030,height:658,borderRadius:26,overflow:'hidden',border:`1px solid ${color.line}`,background:color.bg,boxShadow:'0 30px 100px #0004'}}><div style={{height:59,padding:'20px 29px',background:'#262235',fontSize:18,color:'#c9c4d9'}}># Fibre Delivery <span style={{float:'right',color:color.muted,fontSize:14}}>Illustrative sample thread</span></div><div style={{position:'absolute',left:0,top:59,width:1030,height:599}}><Sequence from={0} width={1030} height={599}><ChannelThread messages={messages} mode="dark" fontFamily="Inter" theme={{...snapTheme,mutedForeground:'#aaa8bd'}}/></Sequence></div></div></>;
}

function Review() {
  return <><Copy eyebrow="A receipt is not an approval" title={<>Inspect evidence.<br/><span style={{color:color.purple}}>Decide the outcome.</span></>} description="Supervisors review the original answers and location before closing the job.">
    <Point icon={Check} title="Approve completed work"/>
    <Point icon={GitBranch} title="Request follow-up with a clear note" delay={65}/>
    <Point icon={FileText} title="Trace visits through asset history" delay={105}/>
  </Copy><BrowserShot asset="review" label="THBS Field Assist / Report review" height={650}/><Callout x={1070} y={763} title="Original evidence stays intact" delay={135}/></>;
}

function AI() {
  const f=useCurrentFrame();
  const items=[['Priorities','What needs attention today?','Source-linked operational summary'],['Visit instructions','Prepare an editable job brief.','Engineer form provides context'],['Evidence review','What needs a follow-up?','Review gaps before a human decision']];
  return <><Copy eyebrow="AI that supports decisions" title={<>Turn records<br/>into <span style={{color:color.purple}}>next steps.</span></>} description="Summaries and editable drafts help the team act on the information already in the system.">
    <Point icon={Sparkles} title="On-demand dashboard assistance"/>
    <Point icon={ShieldCheck} title="Scoped to the signed-in user's access" delay={70}/>
  </Copy><div style={{position:'absolute',left:850,top:215,width:885}}>{items.map(([title,prompt,detail],i)=><div key={title} style={{display:'flex',gap:24,alignItems:'flex-start',padding:30,marginBottom:19,borderRadius:23,border:`1px solid ${color.line}`,background:i===0?'linear-gradient(120deg,#31264b,#222237)':'#1e1c2d',opacity:ease(f,25+i*65),transform:`translateY(${20*(1-ease(f,25+i*65))}px)`}}><div style={{width:47,height:47,borderRadius:16,display:'grid',placeItems:'center',background:'#5b51d844',color:color.purple}}><Sparkles size={25}/></div><div><div style={{fontSize:16,letterSpacing:2,color:color.teal,marginBottom:12}}>{title.toUpperCase()}</div><div style={{fontSize:30,fontWeight:550}}>{prompt}</div><div style={{fontSize:20,color:color.muted,marginTop:12}}>{detail}</div></div></div>)}</div><Note>Dashboard AI requires internet and a configured server key. Suggestions never approve, send messages or modify field evidence.</Note></>;
}

function People() {
  return <><Copy eyebrow="People, teams & access" title={<>Know the team.<br/><span style={{color:color.purple}}>See the connection.</span></>} description="A shared organisation view explains departments, squads, reporting lines and colleague details.">
    <Point icon={Network} title="Understand who works under whom"/>
    <Point icon={ShieldCheck} title="Role-based actions and data scope" delay={65}/>
    <div style={{display:'flex',gap:10,flexWrap:'wrap',maxWidth:540,marginTop:30}}>{['Administrator','Sales','Team lead','Engineer'].map(s=><Badge key={s}>{s}</Badge>)}</div>
  </Copy><BrowserShot asset="organisation" label="THBS Field Assist / Organisation" height={650}/></>;
}

function Features() {
  return <><Copy eyebrow="Designed around the field" title={<>One experience.<br/><span style={{color:color.purple}}>Many ways to work.</span></>} description="Reusable forms and clear project structure connect the workspace, from setup to delivery."><Point icon={FileText} title="Versioned forms and relevant questions"/><Point icon={Users} title="Profiles, avatars and organisation lookup" delay={65}/><Point icon={Layers3} title="Light, dark and system theme" delay={105}/></Copy>
    <div style={{position:'absolute',left:780,top:215,width:1040,height:610,borderRadius:28,border:`1px solid ${color.line}`,overflow:'hidden'}}><Sequence from={0} width={1040} height={610}><WordWheel headline="Built for" words="Field teams, Voice capture, Cable scans, Client boards, Team chat, Site time, Human review" fontFamily="Inter" mode="dark" theme={snapTheme}/></Sequence></div>
    <div style={{position:'absolute',left:905,top:838,fontSize:20,color:color.muted}}>Capture · Coordinate · Review</div>
  </>;
}

function Outro() {
  const f=useCurrentFrame();
  return <><div style={{position:'absolute',left:0,right:0,top:292,display:'flex',flexDirection:'column',alignItems:'center',opacity:ease(f,8,35),transform:`translateY(${25*(1-ease(f,8,35))}px)`}}><Brand large/><h1 style={{margin:'57px 0 28px',fontSize:65,fontWeight:550,letterSpacing:-2,textAlign:'center',lineHeight:1.13}}>Clear ownership. Connected teams.<br/><span style={{color:color.purple}}>Field evidence you can follow.</span></h1><div style={{color:color.muted,fontSize:25}}>From capture to review — presented by the Torry Harris team.</div></div><div style={{position:'absolute',left:0,right:0,top:818,display:'flex',gap:15,justifyContent:'center',opacity:ease(f,60)}}><Badge active>Flutter app</Badge><Badge active>Operations dashboard</Badge><Badge active>One connected journey</Badge></div></>;
}

const scenes:Record<string, React.ComponentType<{chapter:Chapter}>>={intro:Intro,dispatch:Dispatch,mobile:Mobile,time:Time,scan:Scan,voice:Voice,sync:Sync,messages:Messages,review:Review,ai:AI,people:People,features:Features,outro:Outro};

export function ProductFilm() {
  return <SnapCnUIProvider theme={{...snapTheme,fontFamily:'Inter'}} mode="dark"><AbsoluteFill style={{background:color.bg,fontFamily:font}}>{chapters.map(chapter=>{
    return <Sequence key={chapter.id} from={chapter.from} durationInFrames={chapter.durationInFrames} name={chapter.label}><ChapterScene chapter={chapter}/></Sequence>;
  })}</AbsoluteFill></SnapCnUIProvider>;
}

function ChapterScene({chapter}:{chapter:Chapter}) {
  const frame=useCurrentFrame();
  const cues=React.useMemo(()=>createCaptionCues(chapter.narration,timings[chapter.id as keyof typeof timings].seconds,FPS),[chapter]);
  const cue=cues.find(c=>frame>=c.startFrame&&frame<c.endFrame)??null;
  const Scene=scenes[chapter.id];
  return <><Stage chapter={chapter} captionActive={!!cue}><Scene chapter={chapter}/></Stage><Captions cue={cue}/><Sequence from={18} layout="none"><Audio src={staticFile(`audio/${chapter.id}.wav`)} volume={.95}/></Sequence></>;
}

export function RemotionRoot() {
  return <Composition id="THBS-Field-Assist" component={ProductFilm} width={WIDTH} height={HEIGHT} fps={FPS} durationInFrames={DURATION}/>;
}
