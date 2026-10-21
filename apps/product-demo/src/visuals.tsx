import React from 'react';
import {AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {ArrowUpRight, Check, Radio, type LucideIcon} from 'lucide-react';
import type {Chapter} from './timeline';

export const color = {bg:'#10111b', ink:'#f6f5ff', muted:'#aaa8bd', purple:'#a99afb', primary:'#5b51d8', teal:'#45d0bc', line:'#ffffff19'};
export const font = 'Inter, Arial, Helvetica, sans-serif';
export const snapTheme = {primary: '#5b51d8', background:'#10111b', foreground:'#f6f5ff'};
export const ease = (frame:number, start:number, duration=22) => interpolate(frame,[start,start+duration],[0,1],{extrapolateLeft:'clamp',extrapolateRight:'clamp',easing:t=>1-Math.pow(1-t,3)});

export function Brand({large=false}:{large?:boolean}) {
  return <div style={{display:'flex',alignItems:'center',gap:large?22:14,fontFamily:font}}>
    <div style={{height:large?84:46,width:large?84:46,borderRadius:large?25:14,background:color.primary,display:'grid',placeItems:'center',boxShadow:'inset 0 1px 0 #ffffff55'}}><Radio size={large?49:27} strokeWidth={1.8}/></div>
    <span style={{fontSize:large?62:28,letterSpacing:large?-2:-.7}}><strong style={{fontWeight:750}}>THBS</strong><span style={{fontWeight:400,color:'#d6d2e8'}}> Field Assist</span><span style={{color:color.purple}}>.</span></span>
  </div>;
}

export function Stage({chapter,children,captionActive=false}:{chapter:Chapter;children:React.ReactNode;captionActive?:boolean}) {
  const frame=useCurrentFrame();
  const opacity=interpolate(frame,[0,14,chapter.durationInFrames-12,chapter.durationInFrames],[0,1,1,0],{extrapolateLeft:'clamp',extrapolateRight:'clamp'});
  return <AbsoluteFill style={{background:color.bg,color:color.ink,fontFamily:font,overflow:'hidden'}}>
    {chapter.id!=='intro'&&<><AbsoluteFill style={{background:'radial-gradient(ellipse at 79% 21%, #5b51d828, transparent 52%), radial-gradient(ellipse at 16% 90%, #159c8b15, transparent 52%)'}}/>
    <div style={{position:'absolute',inset:0,opacity:.1,backgroundImage:'linear-gradient(#9690bd44 1px, transparent 1px),linear-gradient(90deg,#9690bd44 1px, transparent 1px)',backgroundSize:'120px 120px',maskImage:'linear-gradient(120deg,transparent,#000,transparent)'}}/></>}
    <div style={{position:'absolute',left:86,top:58,zIndex:3}}><Brand/></div>
    <div style={{position:'absolute',right:90,top:74,zIndex:3,fontSize:17,letterSpacing:2.4,color:color.muted}}>PRODUCT WALKTHROUGH</div>
    <AbsoluteFill style={{opacity}}>{children}</AbsoluteFill>
    <div style={{position:'absolute',left:90,right:90,bottom:57,zIndex:3,display:'flex',alignItems:'center',gap:26,fontSize:17,color:color.muted,visibility:captionActive?'hidden':'visible'}}>
      <span style={{color:color.purple,fontVariantNumeric:'tabular-nums'}}>{String(chapter.index+1).padStart(2,'0')} / 13</span><span>{chapter.label}</span>
      <div style={{flex:1,height:1,background:color.line}}/>
      <span style={{fontSize:15}}>TORRY HARRIS TEAM</span>
    </div>
    <div style={{position:'absolute',left:0,bottom:0,height:4,width:`${((chapter.index+frame/chapter.durationInFrames)/13)*100}%`,background:`linear-gradient(90deg,${color.primary},${color.teal})`}}/>
  </AbsoluteFill>;
}

export function Copy({eyebrow,title,description,children}:{eyebrow:string;title:React.ReactNode;description:string;children?:React.ReactNode}) {
  const f=useCurrentFrame();const p=ease(f,5);
  return <div style={{position:'absolute',left:96,top:221,width:620,opacity:p,transform:`translateY(${24*(1-p)}px)`}}>
    <div style={{color:color.teal,fontSize:17,fontWeight:650,letterSpacing:3,marginBottom:25}}>{eyebrow.toUpperCase()}</div>
    <h1 style={{fontSize:68,fontWeight:650,lineHeight:1.08,letterSpacing:-2.7,margin:'0 0 29px'}}>{title}</h1>
    <p style={{fontSize:25,lineHeight:1.55,color:color.muted,margin:0,maxWidth:550}}>{description}</p>
    <div style={{marginTop:35}}>{children}</div>
  </div>;
}

export function Point({icon:Icon,title,detail,delay=30}:{icon:LucideIcon;title:string;detail?:string;delay?:number}) {
  const f=useCurrentFrame();const p=ease(f,delay);
  return <div style={{display:'flex',gap:16,alignItems:'center',marginBottom:23,opacity:p,transform:`translateX(${20*(1-p)}px)`}}>
    <div style={{width:45,height:45,borderRadius:14,color:color.teal,background:'#159c8b20',display:'grid',placeItems:'center',flexShrink:0}}><Icon size={23}/></div>
    <div><div style={{fontSize:24,color:color.ink}}>{title}</div>{detail&&<div style={{fontSize:18,color:color.muted,marginTop:5}}>{detail}</div>}</div>
  </div>;
}

export function BrowserShot({asset,label,width=1010,height=650,x=825,y=204,pan=0}:{asset:string;label:string;width?:number;height?:number;x?:number;y?:number;pan?:number}) {
  const frame=useCurrentFrame();const p=ease(frame,12,35);const {durationInFrames}=useVideoConfig();
  return <div style={{position:'absolute',left:x,top:y,width,height,borderRadius:22,overflow:'hidden',border:'1px solid #b8a9ff33',background:'#f7f8fb',boxShadow:'0 45px 110px #00000065',transform:`perspective(1800px) rotateY(${-3*(1-p)}deg) translateY(${28*(1-p)}px)`,opacity:p}}>
    <div style={{height:43,background:'#232232',display:'flex',alignItems:'center',gap:7,padding:'0 18px',color:'#b0aabd',fontSize:13}}>
      {['#ad91e6','#696177','#4a4557'].map(c=><span key={c} style={{height:8,width:8,borderRadius:9,background:c}}/>)}
      <span style={{margin:'0 auto',paddingRight:40}}>{label}</span>
    </div>
    <div style={{height:height-43,overflow:'hidden'}}><Img src={staticFile(`screens/${asset}.png`)} style={{width:'100%',display:'block',transform:`translateY(${-pan*ease(frame,65,Math.max(60,durationInFrames-100))}px)`}}/></div>
  </div>;
}

export function Badge({children,active=false}:{children:React.ReactNode;active?:boolean}) {
  return <span style={{display:'inline-flex',alignItems:'center',gap:8,border:`1px solid ${active?'#45d0bc66':color.line}`,borderRadius:40,padding:'11px 17px',background:active?'#159c8b22':'#ffffff06',fontSize:18,color:active?color.teal:'#d1cce2'}}>{active&&<Check size={17}/>} {children}</span>;
}

export function Note({children}:{children:React.ReactNode}) {
  return <div data-demo-note style={{position:'absolute',left:98,bottom:135,maxWidth:630,fontSize:18,lineHeight:1.45,color:'#9996ad'}}>{children}</div>;
}

export function Callout({x,y,title,sub,delay=50}:{x:number;y:number;title:string;sub?:string;delay?:number}) {
  const frame=useCurrentFrame();const p=spring({frame:frame-delay,fps:30,config:{damping:22,stiffness:150}});
  return <div style={{position:'absolute',left:x,top:y,padding:'18px 25px',border:'1px solid #c4b4ff3a',borderRadius:18,background:'#29243ef5',boxShadow:'0 15px 50px #0005',transform:`translateY(${20*(1-p)}px)`,opacity:Math.min(1,p),display:'flex',alignItems:'center',gap:15}}>
    <div style={{background:'#159c8b33',color:color.teal,borderRadius:20,height:35,width:35,display:'grid',placeItems:'center'}}><Check size={20}/></div>
    <div><div style={{fontSize:24}}>{title}</div>{sub&&<div style={{fontSize:17,color:color.muted,marginTop:5}}>{sub}</div>}</div><ArrowUpRight size={20} style={{marginLeft:12,color:color.purple}}/>
  </div>;
}
