import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame} from 'remotion';
import {ArrowLeft, Check, ChevronRight, FileCheck2, Mic, Pause, Radio, ShieldCheck, Sparkles, X} from 'lucide-react';

const ink='#252b40', violet='#7054d9', muted='#7b849b';
const clamp={extrapolateLeft:'clamp',extrapolateRight:'clamp'} as const;
export type PhoneMode='capture'|'followup'|'review'|'repair';

export const PhoneScreen:React.FC<{mode?:PhoneMode;duration?:number;frameOverride?:number}>=({mode='capture',duration=480,frameOverride})=>{
  const current=useCurrentFrame(),f=frameOverride??current;
  const p=f/duration;
  const review=mode==='review'||(mode==='followup'&&p>.66);
  const entries=[
    {label:'Work done',value:'ONT installed in the living room using the existing duct.',at:.25},
    {label:'Visit outcome',value:'Work completed',at:.88},
    {label:'Optical reading (dBm)',value:mode==='repair'?'−18.19':'−18.2',at:.66},
    {label:'Test result',value:'Passed',at:.79},
    {label:'Follow-up / next action',value:'No further work required',at:2},
  ];
  const words='I installed the ONT in the living room. I used the existing duct. Optical receive was minus eighteen point two dBm. The service test passed. The job is complete.'.split(' ');
  const transcript=words.slice(0,Math.floor(Math.max(0,(p-.04)/.90)*words.length)).join(' ');
  if(mode==='followup'&&!review)return <AbsoluteFill style={{background:'#080e21',color:'white',fontFamily:'Inter',padding:48}}>
    <div style={{display:'flex',justifyContent:'space-between',paddingTop:30,fontSize:23}}><span>9:41</span><span>▰</span></div>
    <div style={{marginTop:88,display:'flex',alignItems:'center',justifyContent:'space-between'}}><ArrowLeft size={32}/><span style={{fontSize:27,fontWeight:600}}>Voice assistant</span><ShieldCheck size={29}/></div>
    <div style={{marginTop:52,fontSize:20,letterSpacing:3,color:'#c5b9fa'}}>S1 · FTTP VISIT</div>
    <div style={{margin:'115px auto 80px',width:210,height:210,borderRadius:'50%',background:'radial-gradient(circle at 35% 26%,#dad2ff,#8c6aef 32%,#4b37a9 65%,#191a44)',boxShadow:'0 0 100px #9674ff54',display:'grid',placeItems:'center'}}><Radio size={92} strokeWidth={1.2}/></div>
    <div style={{display:'flex',justifyContent:'center',gap:10,height:85,alignItems:'center'}}>{Array.from({length:31},(_,i)=><div key={i} style={{width:7,borderRadius:10,height:15+Math.abs(Math.sin(f*.16+i*.8))*55,background:'#bba6ff'}}/>)}</div>
    <div style={{fontSize:43,lineHeight:1.32,textAlign:'center',fontWeight:500,marginTop:54}}>{p<.38?'Is any follow-up work required?':'No further work required.'}</div>
    <div style={{fontSize:24,color:'#a9b2cb',textAlign:'center',marginTop:38}}>{p<.38?'Assistant speaking':'Answer captured'}</div>
    <div style={{position:'absolute',left:48,right:48,bottom:164,display:'flex',gap:16}}>{['No follow-up','Further work'].map(s=><div key={s} style={{flex:1,border:'1px solid #ffffff2e',padding:'24px 16px',borderRadius:28,textAlign:'center',fontSize:23}}>{s}</div>)}</div>
    <div style={{position:'absolute',bottom:58,left:145,right:145,display:'flex',justifyContent:'space-between'}}><Pause size={30}/><Mic size={40} color='#bba6ff'/><X size={32}/></div>
  </AbsoluteFill>;
  return <AbsoluteFill style={{background:'#f7f7fc',fontFamily:'Inter',color:ink}}>
    <div style={{position:'absolute',left:43,right:43,top:54,display:'flex',justifyContent:'space-between',fontSize:23,fontWeight:600}}><span>9:41</span><span>▰</span></div>
    <div style={{position:'absolute',left:40,right:40,top:103,display:'flex',alignItems:'center',justifyContent:'space-between'}}><ArrowLeft size={34}/><span style={{fontSize:32,fontWeight:650}}>{review?'Review visit summary':'Visit summary'}</span><FileCheck2 size={32}/></div>
    <div style={{position:'absolute',left:36,right:36,top:194,padding:'27px 29px',background:'white',borderRadius:32,border:'1px solid #ececf4'}}>
      <div style={{fontSize:24,fontWeight:650}}>S1 · Standard FTTP provision</div><div style={{fontSize:19,color:muted,marginTop:9}}>Synthetic demonstration · five fields</div>
    </div>
    <div style={{position:'absolute',top:312,left:40,right:40,display:'flex',alignItems:'center',gap:12,color:violet,fontSize:24,fontWeight:600}}>{review?<ShieldCheck size={27}/>:<Mic size={27}/>} {review?'Your answers. Your confirmation.':'Listening · filling as you speak'}</div>
    <div style={{position:'absolute',top:368,left:35,right:35,display:'flex',flexDirection:'column',gap:17}}>
      {entries.map((e,i)=>{const filled=review||mode==='repair'||p>=e.at;const enter=interpolate(p,[e.at,e.at+.045],[0,1],clamp);return <div key={e.label} style={{background:'white',borderRadius:29,padding:'22px 25px',minHeight:i===0?184:148,border:`1px solid ${filled?'#ddd4fa':'#e9eaf0'}`,boxShadow:filled?'0 5px 14px #6346b006':'none'}}>
        <div style={{display:'flex',alignItems:'center',justifyContent:'space-between',fontSize:23,fontWeight:600}}><span>{i+1}. {e.label}</span>{filled&&<Check size={23} color={violet}/>}</div>
        <div style={{marginTop:17,padding:'15px 18px',background:'#f7f7fc',borderRadius:19,fontSize:i===2?36:24,lineHeight:1.4,color:filled?ink:muted,opacity:filled?.85+enter*.15:1}}>{filled?e.value:i===0?(transcript||'Tell us what happened…'):'Waiting for your answer…'}</div>
      </div>;})}
    </div>
    <div style={{position:'absolute',left:36,right:36,bottom:45,background:violet,color:'white',borderRadius:37,padding:'26px 24px',fontSize:27,fontWeight:650,display:'flex',justifyContent:'center',alignItems:'center',gap:15}}>{review?<FileCheck2 size={29}/>:<Sparkles size={28}/>} {review?'Confirm & submit':'Voice capture active'} {review&&<ChevronRight size={25}/>}</div>
  </AbsoluteFill>;
};

export const DemoCapture=()=> <PhoneScreen/>;
