import React from 'react';
import {AbsoluteFill, Audio, Composition, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {ArrowRight, AudioLines, Check, CheckCheck, ClipboardCheck, CloudUpload, FileCheck2, FileText, GitBranch, Layers, LockKeyhole, Mic, PlugZap, Radio, ShieldCheck, SlidersHorizontal, Sparkles, Volume2, WifiOff} from 'lucide-react';
import {WordGather} from '../components/snap-cn/word-gather';
import {PhoneFrame} from '../components/snap-cn/phone-frame';
import {ScreenRecording} from '../components/snap-cn/screen-recording';
import {PortalIntro} from '../components/snap-cn/portal-intro';
import {DotBloom,DOT_BLOOM_CUT,DOT_BLOOM_FRAMES} from '../components/snap-cn/dot-bloom';
import {ChannelThread} from '../components/snap-cn/channel-thread';
import {CaptureReveal} from '../components/snap-cn/capture-reveal';
import {AnnounceTitle} from '../components/snap-cn/announce-title';
import {ReelCollage} from '../components/snap-cn/reel-collage';
import {PhoneScreen,DemoCapture,type PhoneMode} from './PhoneScreen';
import timing from './timing.json';

export const PROMO_FPS=30;
export const PROMO_DURATION=timing.durationInFrames;
export const promoScenes=timing.scenes;
const c={bg:'#0a0d16',surface:'#121725',raised:'#1b2234',ink:'#f3f1fc',muted:'#a5adbf',accent:'#b49aff',line:'#ffffff18'};
const theme={background:c.bg,foreground:c.ink,primary:c.accent,card:c.surface,mutedForeground:c.muted,border:c.line};
const clamp={extrapolateLeft:'clamp',extrapolateRight:'clamp'} as const;
const settle=(f:number,delay=0)=>spring({frame:f-delay,fps:30,config:{damping:22,stiffness:135}});

const VoiceMark=({size=35}:{size?:number})=><div style={{width:size,height:size,display:'flex',alignItems:'center',justifyContent:'center',gap:size*.065}}>{[.32,.65,1,.65,.32].map((h,i)=><span key={i} style={{height:size*h*.7,width:size*.09,borderRadius:10,background:'currentColor'}}/>)}</div>;
const Brand=()=> <div style={{display:'flex',alignItems:'center',gap:14,fontSize:25,letterSpacing:-.8}}><span style={{color:c.accent}}><VoiceMark/></span><span><b>THBS</b> <span style={{color:'#c6c9d7',fontWeight:400}}>Field Assist</span><span style={{color:c.accent}}>.</span></span></div>;
const Label=({children}:{children:React.ReactNode})=><div style={{fontSize:19,letterSpacing:3.3,fontWeight:600,color:c.accent,textTransform:'uppercase'}}>{children}</div>;

const Backdrop=()=> <AbsoluteFill style={{background:c.bg}}><AbsoluteFill style={{background:'radial-gradient(ellipse at 72% 38%,#7d62d619,transparent 55%),radial-gradient(ellipse at 18% 10%,#b6b4fa08,transparent 50%)'}}/><AbsoluteFill style={{backgroundImage:'linear-gradient(#ffffff05 1px,transparent 1px),linear-gradient(90deg,#ffffff05 1px,transparent 1px)',backgroundSize:'80px 80px',maskImage:'radial-gradient(ellipse at 55% 50%,black,transparent 75%)'}}/></AbsoluteFill>;

const Stage=({id,children}:{id:string;children:React.ReactNode})=>{
  const f=useCurrentFrame();const {durationInFrames}=useVideoConfig();
  const p=interpolate(f,[0,12,durationInFrames-8,durationInFrames],[0,1,1,1],clamp);
  return <AbsoluteFill style={{fontFamily:'Inter',color:c.ink,overflow:'hidden'}}><Backdrop/>
    <AbsoluteFill style={{opacity:p}}>{children}</AbsoluteFill>
    {id!=='reveal'&&id!=='close'&&<div style={{position:'absolute',left:90,top:55,zIndex:10}}><Brand/></div>}
    {id!=='reveal'&&id!=='close'&&<div style={{position:'absolute',right:90,top:66,fontSize:16,letterSpacing:2.4,color:c.muted}}>VOICE-ASSISTED JOB COMPLETION</div>}
    {['capture','followup','repair'].includes(id)&&<div style={{position:'absolute',right:95,bottom:151,fontSize:17,color:c.muted,zIndex:10}}>Illustrative flow · synthetic data · edited for pacing</div>}
  </AbsoluteFill>;
};

const ToastCaptions=()=>{
  const frame=useCurrentFrame();const cue=timing.captions.find(c=>frame>=c.from&&frame<c.to);
  if(!cue||cue.scene==='speed')return null;
  const p=interpolate(frame,[cue.from,cue.from+5],[0,1],clamp);
  return <div data-promo-caption style={{position:'absolute',left:125,right:125,bottom:47,zIndex:30,display:'flex',justifyContent:'center',opacity:p,transform:`translateY(${7*(1-p)}px)`,pointerEvents:'none'}}>
    <div style={{display:'flex',alignItems:'center',gap:14,padding:'19px 31px',background:'#111623f2',border:'1px solid #ffffff24',boxShadow:'0 12px 35px #0005',borderRadius:22,maxWidth:1650,fontSize:32,fontWeight:500,lineHeight:1.25,textAlign:'center',fontFamily:'Inter',color:'#faf9ff'}}>
      <span style={{width:7,height:7,borderRadius:9,background:c.accent,flexShrink:0}}/>
      <span>{cue.role&&<span style={{fontSize:16,letterSpacing:1.7,color:c.accent,marginRight:13}}>{cue.role}</span>}{cue.text}</span>
    </div>
  </div>;
};

const Header=({eyebrow,title,sub}:{eyebrow:string;title:string;sub?:string})=>{
  const f=useCurrentFrame(),p=settle(f,3);
  return <div style={{position:'absolute',left:100,top:202,maxWidth:1650,opacity:p,transform:`translateY(${23*(1-p)}px)`}}><Label>{eyebrow}</Label><h1 style={{fontWeight:620,fontSize:86,letterSpacing:-4.5,lineHeight:1.06,margin:'26px 0 20px'}}>{title}</h1>{sub&&<p style={{fontSize:29,color:c.muted,maxWidth:1110,lineHeight:1.45,margin:0}}>{sub}</p>}</div>;
};

const Phone=({mode='review',recording=false,angle=0}:{mode?:PhoneMode;recording?:boolean;angle?:number})=> {const {durationInFrames}=useVideoConfig();return <div style={{position:'absolute',left:1155,top:111,width:620,height:800}}>
  <PhoneFrame scale={1.15} variant={angle?'tilt':'flat'} tiltAngle={angle} entrance="rotate-in" floatLoop={false} bezelColor="#6b6980" screenColor="#f7f7fc" shadow="0 40px 110px #0009" mode="dark" theme={theme} fontFamily="Inter">
    {recording?<ScreenRecording src={staticFile('voice-promo/visit-capture.mp4')} camera={[]} crop={{top:.018,bottom:.015}} entrance="none" mode="dark" theme={theme}/>:<div style={{position:'absolute',left:0,top:0,width:720,height:1536,transform:'scale(0.411111)',transformOrigin:'0 0'}}><PhoneScreen mode={mode} duration={durationInFrames}/></div>}
  </PhoneFrame>
</div>;};

const Waveform=({width=680,height=110,active=true}:{width?:number;height?:number;active?:boolean})=>{
 const f=useCurrentFrame();
 return <div style={{width,height,display:'flex',alignItems:'center',justifyContent:'center',gap:7}}>{Array.from({length:63},(_,i)=>{const envelope=Math.sin(Math.PI*i/62)**1.4;const level=active?Math.abs(Math.sin(i*.63+f*.12)):.16;return <span key={i} style={{width:5,height:7+envelope*(height-10)*level,background:c.accent,borderRadius:5,opacity:.28+.72*envelope,boxShadow:level>.8?'0 0 15px #b49aff45':'none'}}/>;})}</div>;
};

function Hook(){return <><div style={{position:'absolute',inset:'50px 0 60px'}}><WordGather text="Speak the visit. Complete the record." maxWidth={480} accent={c.accent} fontFamily="Inter" theme={theme} mode="dark" speed={.58}/></div><div style={{position:'absolute',top:204,left:0,right:0,textAlign:'center',zIndex:2}}><Label>Less interaction. Clearer records.</Label></div><div style={{position:'absolute',top:750,left:620}}><Waveform active={false}/></div></>;}

function Reveal(){const f=useCurrentFrame();const clean=interpolate(f,[104,116],[0,1],clamp);return <><PortalIntro lead="What if" trail="your voice did the reporting?" image={staticFile('voice-promo/portal-stage.svg')} chipImage={staticFile('voice-promo/portal.svg')} title="Field Assist" brand="THBS" logo={<VoiceMark size={60}/>} overlay="#ffffff" fontFamily="Inter" theme={theme} mode="dark" speed={1.1}/>{f>=104&&<AbsoluteFill style={{opacity:clean}}><Backdrop/><div style={{position:'absolute',left:200,right:200,top:290,textAlign:'center',transform:`translateY(${12*(1-clean)}px)`}}><Label>Voice-assisted job completion</Label><div style={{display:'flex',alignItems:'center',justifyContent:'center',gap:30,marginTop:75,fontSize:112,letterSpacing:-5}}><span style={{color:c.accent}}><VoiceMark size={94}/></span><span><b style={{fontWeight:750}}>THBS</b><span style={{fontWeight:450}}> Field Assist</span><span style={{color:c.accent}}>.</span></span></div><div style={{fontSize:32,color:c.muted,marginTop:47}}>A voice journey for the applications engineers already use.</div><div style={{fontSize:23,color:'#d2c8ee',marginTop:53,letterSpacing:1}}>Speak naturally. Fill the gaps. Review with confidence.</div></div></AbsoluteFill>}</>;}

function Capture(){
  const f=useCurrentFrame(),{durationInFrames}=useVideoConfig();const p=f/durationInFrames;
  const facts=[['Work done','ONT installed · existing duct',.25],['Optical receive','−18.2 dBm',.65],['Service test','Passed',.80],['Visit outcome','Work completed',.91]] as const;
  return <><Header eyebrow="One natural summary" title="Speak once." sub="Your words become proposed form answers."/><div style={{position:'absolute',left:100,top:432,width:900}}>{facts.map(([label,value,at])=>{const ready=p>=at;const reveal=settle(f,at*durationInFrames);return <div key={label} style={{display:'flex',alignItems:'center',justifyContent:'space-between',borderBottom:`1px solid ${c.line}`,padding:'23px 0',opacity:ready?1:.35}}><div><div style={{fontSize:17,color:c.muted,letterSpacing:1.2,marginBottom:8}}>{label.toUpperCase()}</div><div style={{fontSize:label==='Optical receive'?48:31,fontWeight:550,letterSpacing:-1,color:ready?c.ink:c.muted}}>{ready?value:'Listening…'}</div></div>{ready&&<div style={{transform:`scale(${reveal})`,color:c.accent}}><Check size={30}/></div>}</div>;})}</div><Phone recording angle={-9}/></>;
}

function Followup(){const f=useCurrentFrame(),{durationInFrames}=useVideoConfig();const lines=promoScenes.find(s=>s.id==='followup')!.lines;
 const messages=[{author:'Assistant',time:'VOICE',avatar:staticFile('voice-promo/assistant-avatar.svg'),text:'Any follow-up work required?',at:Math.round(lines[0].start*30),opens:0},{author:'Engineer',time:'VOICE',avatar:staticFile('avatars/teams_1.png'),text:'No further work required.',at:Math.round(lines[1].start*30),opens:Math.round(lines[1].start*30)-12}];
 return f<150?<><Header eyebrow="The next useful question" title="Only what’s missing."/><div style={{position:'absolute',left:100,top:390,width:980,height:420,borderRadius:27,background:c.surface,border:`1px solid ${c.line}`,overflow:'hidden'}}><Sequence width={980} height={420}><ChannelThread messages={messages} theme={theme} mode="dark" fontFamily="Inter"/></Sequence></div><div style={{position:'absolute',left:104,top:839,fontSize:23,color:c.muted}}>One spoken answer. Automatic progression.</div><Phone mode="followup"/></>:<Sequence from={150} durationInFrames={durationInFrames-150}><CaptureReveal headline="Your answers.|Your confirmation." capturing="Preparing review…" copied="Ready for your review." src={staticFile('voice-promo/review.png')} theme={theme} mode="dark" fontFamily="Inter"/></Sequence>;}

function Repair(){const f=useCurrentFrame();const fixed=f>115;
 return <><Header eyebrow="Natural spoken corrections" title="Say it. Correct it." sub="The corrected value stays linked to what was said."/><div style={{position:'absolute',left:101,top:440,width:910,padding:35,borderRadius:27,background:c.surface,border:`1px solid ${c.line}`}}><div style={{fontSize:18,color:c.muted,letterSpacing:2}}>OPTICAL RECEIVE · dBm</div><div style={{display:'flex',alignItems:'center',gap:39,marginTop:30}}><span style={{fontFamily:'Inter Tight, Inter',fontSize:110,letterSpacing:-7,color:fixed?'#777f94':c.ink,textDecorationLine:fixed?'line-through':'none',textDecorationThickness:3}}>18.2</span><ArrowRight size={42} color={c.muted}/><span style={{fontFamily:'Inter Tight, Inter',fontSize:115,letterSpacing:-7,color:c.accent,opacity:settle(f,110),transform:`translateY(${18*(1-settle(f,110))}px)`}}>−18.19</span></div><div style={{fontSize:26,lineHeight:1.5,color:c.muted,marginTop:27}}>“No, sorry. The reading is<br/><span style={{color:c.ink}}>minus eighteen point one nine.</span>”</div></div><div style={{position:'absolute',left:104,top:808,color:c.muted,fontSize:23,display:'flex',gap:13,alignItems:'center'}}><FileCheck2 size={26} color={c.accent}/> Proposed answer · editable before submission</div><Phone mode="repair" angle={-6}/></>;
}

function Speed(){const f=useCurrentFrame();return <><div style={{position:'absolute',left:100,top:215}}><Label>Early recognition benchmark</Label><div style={{fontSize:55,fontWeight:500,letterSpacing:-2.5,marginTop:25}}>Short-answer recognition</div><div style={{display:'flex',alignItems:'baseline',marginTop:10,opacity:settle(f,8)}}><span style={{fontFamily:'Inter Tight, Inter',fontWeight:650,fontSize:300,letterSpacing:-22,color:c.accent,lineHeight:1.15}}>≈0.45</span><span style={{fontSize:77,marginLeft:37}}>seconds</span></div><div style={{display:'flex',alignItems:'center',gap:15,marginTop:12,fontSize:28,color:c.muted}}><AudioLines size={29} color={c.accent}/> On-device speech recognition</div></div><div style={{position:'absolute',left:102,right:102,top:745,paddingTop:27,borderTop:`1px solid ${c.line}`,fontSize:24,lineHeight:1.65,color:c.muted}}><div><b style={{color:c.ink}}>Android ARM64 emulator · synthetic audio · 2 short-answer samples.</b></div><div>Includes a configured 450 ms pause. Excludes microphone, natural endpoint detection,</div><div>form extraction, voice synthesis and playback. Full-bot and physical-phone timings remain pending.</div></div></>;}

function Offline(){const f=useCurrentFrame();const nodes=[{icon:Mic,title:'Capture',sub:'On-device speech',tag:'OFFLINE'},{icon:LockKeyhole,title:'Keep',sub:'Local saved work',tag:'ON THE PHONE'},{icon:CloudUpload,title:'Deliver',sub:'Confirmed records',tag:'WHEN CONNECTED'}];return <><Header eyebrow="Built around the field" title="Keep the work moving." sub="Offline capture after provisioning. Connected delivery when available."/><div style={{position:'absolute',left:101,right:101,top:480,display:'flex',gap:29}}>{nodes.map((n,i)=>{const Icon=n.icon,p=settle(f,18+i*18);return <div key={n.title} style={{flex:1,padding:37,height:294,borderRadius:28,border:`1px solid ${i===1?'#b49aff66':c.line}`,background:c.surface,opacity:p,transform:`translateY(${32*(1-p)}px)`}}><Icon size={44} color={c.accent}/><div style={{fontSize:40,marginTop:29,fontWeight:550,letterSpacing:-1}}>{n.title}</div><div style={{fontSize:26,color:c.muted,marginTop:14}}>{n.sub}</div><div style={{fontSize:15,letterSpacing:2,color:c.accent,marginTop:30}}>{n.tag}</div></div>;})}</div><div style={{position:'absolute',left:104,top:832,fontSize:22,color:c.muted,display:'flex',alignItems:'center',gap:12}}><WifiOff size={25}/> Authorized offline access · sync needs connectivity</div></>;}

function Integration(){const f=useCurrentFrame();const nodes=[{icon:FileText,title:'Job context',sub:'Existing work order'},{icon:Mic,title:'Voice journey',sub:'Narrative + clarification'},{icon:ClipboardCheck,title:'Proposed answers',sub:'Structured + source-linked'},{icon:ShieldCheck,title:'Your application',sub:'Review + approved submission'}];return <><Header eyebrow="Designed for integration" title="Your app. Voice enabled." sub="Adapted through agreed SDK, native-bridge or API interfaces."/><div style={{position:'absolute',left:101,right:101,top:493,display:'flex',alignItems:'center',gap:20}}>{nodes.map((n,i)=>{const Icon=n.icon,p=settle(f,10+i*18);return <React.Fragment key={n.title}><div style={{flex:1,minWidth:0,height:245,padding:26,borderRadius:23,background:i===1?'#241c3c':c.surface,border:`1px solid ${i===1?'#b49aff80':c.line}`,opacity:p,transform:`translateY(${25*(1-p)}px)`}}><Icon size={37} color={i===1?c.accent:c.muted}/><div style={{fontSize:29,fontWeight:550,marginTop:29,letterSpacing:-.7}}>{n.title}</div><div style={{fontSize:21,lineHeight:1.5,color:c.muted,marginTop:12}}>{n.sub}</div></div>{i<3&&<ArrowRight size={24} color={c.muted} style={{flexShrink:0,opacity:p}}/>}</React.Fragment>;})}</div><div style={{position:'absolute',left:104,top:811,fontSize:23,color:c.muted}}>Host interfaces, identity and validation agreed with each application owner.</div></>;}

function Adapt(){const f=useCurrentFrame();const images=['portal.svg','forms.svg','terms.svg','voices.svg','review.png','reading.svg'].map(x=>staticFile(`voice-promo/${x}`));
 if(f<150)return <ReelCollage topLine="Your forms." bottomLine="Your voice." swapTop="Your terminology." swapBottom="Your workflow." slides={images} collage={images} background={c.bg} glowColor="#16152c" flushColor="#30233f" textColor={c.ink} theme={theme} mode="dark" fontFamily="Inter" speed={.7}/>;
 return <Sequence from={150}><Header eyebrow="Adapted to your requirements" title="Domain-specific fine-tuning" sub="Scoped to approved recordings and your field requirements."/><div style={{position:'absolute',left:101,right:101,top:480,display:'flex',gap:28}}>{[{icon:AudioLines,title:'Approved data',sub:'Engineer recordings + transcripts'},{icon:SlidersHorizontal,title:'Scoped training',sub:'Vocabulary, accents and measurements'},{icon:ShieldCheck,title:'Validation',sub:'Accuracy, safety and device performance'}].map((n,i)=>{const Icon=n.icon;return <div key={n.title} style={{flex:1,padding:30,height:240,background:c.surface,border:`1px solid ${i===1?'#b49aff66':c.line}`,borderRadius:24}}><Icon color={c.accent} size={38}/><div style={{fontSize:33,fontWeight:550,marginTop:24}}>{n.title}</div><div style={{fontSize:23,lineHeight:1.5,color:c.muted,marginTop:17}}>{n.sub}</div></div>;})}</div><div style={{position:'absolute',left:104,top:797,fontSize:23,color:c.muted}}>Scoped engagement · approved data · measured validation</div></Sequence>;}

function Close(){const f=useCurrentFrame();return <>{f>155&&<div style={{position:'absolute',left:90,top:55,zIndex:10}}><Brand/></div>}<AnnounceTitle eyebrow="Voice-enabled" title="THBS Field Assist" tagline="Speak the visit. Complete the record." voidColor={c.bg} fieldColor="#6d4acb" paperColor="#efedf6" titleColor="#19152d" nightColor={c.bg} glowColor="#463476" taglineColor={c.ink} symbolPath="M12 42H22V62H12Z M30 28H40V76H30Z M48 12H58V92H48Z M66 28H76V76H66Z M84 42H94V62H84Z" symbolColors={[c.accent,'#e3d8ff']} symbolScale={.7} fontFamily="Inter" speed={1.25}/>{f>155&&<div style={{position:'absolute',top:804,left:0,right:0,display:'flex',justifyContent:'center',gap:19,alignItems:'center',fontSize:28,color:c.muted}}><span>One workflow.</span><span>Your engineers.</span><span style={{color:c.accent}}>A measured pilot.</span><ArrowRight size={28} color={c.accent}/></div>}</>;}

const scenes:Record<string,React.FC>={hook:Hook,reveal:Reveal,capture:Capture,followup:Followup,repair:Repair,speed:Speed,offline:Offline,integration:Integration,adapt:Adapt,close:Close};
export const VoicePromo=()=> <AbsoluteFill style={{background:c.bg}}>
  <Audio src={staticFile('voice-promo/mix.wav')}/>
  {promoScenes.map(s=>{const Scene=scenes[s.id];return <Sequence key={s.id} from={s.from} durationInFrames={s.durationInFrames}><Stage id={s.id}><Scene/></Stage></Sequence>;})}
  {promoScenes.filter(s=>['capture','speed','integration','close'].includes(s.id)).map(s=><Sequence key={`transition-${s.id}`} from={s.from-DOT_BLOOM_CUT} durationInFrames={DOT_BLOOM_FRAMES}><DotBloom/></Sequence>)}
  <ToastCaptions/>
</AbsoluteFill>;

export const VoicePromoRoot=()=> <>
  <Composition id="Field-Assist-Voice-Promo" component={VoicePromo} durationInFrames={PROMO_DURATION} fps={30} width={1920} height={1080}/>
  <Composition id="Voice-Demo-Capture" component={DemoCapture} durationInFrames={promoScenes.find(s=>s.id==='capture')!.durationInFrames} fps={30} width={720} height={1536}/>
  <Composition id="Voice-Review-Still" component={()=> <PhoneScreen mode="review"/>} durationInFrames={1} fps={30} width={720} height={1536}/>
</>;
