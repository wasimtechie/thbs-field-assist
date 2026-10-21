'use client';

import Image from 'next/image';
import {useEffect,useId,useRef,useState,type CSSProperties} from 'react';
import {Pause,Play} from 'lucide-react';
import styles from './robot-mascot.module.css';

export type RobotMascotProps={
 size?:number|string;
 placement?:'inline'|'bottom-left'|'bottom-right';
 colors?:{eyes?:string;glow?:string;halo?:string};
 /** Rotate the body accents while preserving the rendered material. */
 bodyHue?:number;
 className?:string;
 label?:string;
 animate?:boolean;
};

/** Decorative companion. The eyeless raster body and live SVG eyes share a
 * square coordinate system, so responsive resizing cannot detach the face. */
export default function RobotMascot({
 size=240,placement='inline',colors,bodyHue=0,className='',
 label='THBS Field Assist’s friendly waving robot',animate=true,
}:RobotMascotProps){
 const host=useRef<HTMLDivElement>(null);
 const face=useRef<HTMLDivElement>(null);
 const eyes=useRef<(SVGSVGElement|null)[]>([]);
 const pupils=useRef<(SVGGElement|null)[]>([]);
 const [paused,setPaused]=useState(false);
 const id=useId().replaceAll(':','');

 useEffect(()=>{
  const node=host.current;
  if(!node)return;
  const preference=window.matchMedia('(prefers-reduced-motion: reduce)');
  let reduced=preference.matches;
  let visible=false;
  let frame=0,lastTime=0,blinkTimer=0,blinkEnd=0;
  let point:{x:number;y:number}|null=null;
  let tilt=0;
  const current=[{x:0,y:0},{x:0,y:0}];
  const enabled=()=>animate&&!paused&&!reduced&&visible&&!document.hidden;
  const reset=()=>{
   current.forEach((p,index)=>{p.x=0;p.y=0;pupils.current[index]?.setAttribute('transform','translate(0 0)');});
   tilt=0;
   face.current?.style.setProperty('--mascot-tilt','0deg');
  };
  const clearBlink=()=>{
   window.clearTimeout(blinkTimer);window.clearTimeout(blinkEnd);
   delete node.dataset.blinking;
  };
  const scheduleBlink=()=>{
   clearBlink();
   if(!enabled())return;
   blinkTimer=window.setTimeout(()=>{
    if(!enabled())return;
    node.dataset.blinking='true';
    blinkEnd=window.setTimeout(()=>{delete node.dataset.blinking;scheduleBlink();},190);
   },3800+Math.random()*3900);
  };
  const tick=(time:number)=>{
   frame=0;
   if(!enabled())return;
   const easing=1-Math.exp(-Math.min(40,lastTime?time-lastTime:16)/85);
   lastTime=time;
   // Read all bounds before writing any transforms. Each eye has its own
   // center, rather than sharing one global pupil offset.
   const rect=node.getBoundingClientRect();
   const eyeRects=eyes.current.map(eye=>eye?.getBoundingClientRect());
   const targets=eyeRects.map(eye=>{
    if(!eye||!point)return {x:0,y:0};
    const dx=point.x-eye.left-eye.width/2,dy=point.y-eye.top-eye.height/2;
    const distance=Math.hypot(dx,dy),angle=Math.atan2(dy,dx);
    const strength=distance/(distance+65);
    // Each LED eye moves inside its own padded visor region. The
    // highlight plus its maximum travel stays within the clipping ellipse.
    return {x:Math.cos(angle)*9*strength,y:Math.sin(angle)*8*strength};
   });
   let targetTilt=0;
   if(point){
    const dx=point.x-rect.left-rect.width/2,dy=point.y-rect.top-rect.height*.43;
    const near=Math.max(0,1-Math.hypot(dx,dy)/(rect.width*1.8));
    targetTilt=Math.max(-1,Math.min(1,dx/(rect.width*.45)))*near*3;
   }
   let unsettled=false;
   targets.forEach((target,index)=>{
    const pupil=current[index];
    pupil.x+=(target.x-pupil.x)*easing;pupil.y+=(target.y-pupil.y)*easing;
    pupils.current[index]?.setAttribute('transform',`translate(${pupil.x.toFixed(3)} ${pupil.y.toFixed(3)})`);
    unsettled ||=Math.abs(target.x-pupil.x)+Math.abs(target.y-pupil.y)>.015;
   });
   tilt+=(targetTilt-tilt)*easing;
   face.current?.style.setProperty('--mascot-tilt',`${tilt.toFixed(3)}deg`);
   unsettled ||=Math.abs(targetTilt-tilt)>.005;
   // Stop once settled; idle breathing/blinks use CSS. No permanent JS loop.
   if(unsettled)frame=requestAnimationFrame(tick);
  };
  const wake=()=>{if(enabled()&&!frame){lastTime=0;frame=requestAnimationFrame(tick);}};
  const sync=()=>{
   cancelAnimationFrame(frame);frame=0;
   node.dataset.active=String(enabled());
   if(enabled()){scheduleBlink();wake();}else{clearBlink();reset();}
  };
  const move=(event:PointerEvent)=>{
   if(event.pointerType==='touch'&&event.type==='pointermove'&&!event.buttons)return;
   point={x:event.clientX,y:event.clientY};wake();
  };
  const release=(event:PointerEvent)=>{if(event.pointerType!=='mouse'){point=null;wake();}};
  const leave=(event:PointerEvent)=>{if(!event.relatedTarget){point=null;wake();}};
  const blur=()=>{point=null;reset();};
  const change=()=>{reduced=preference.matches;point=null;sync();};
  const scroll=()=>wake();
  const observer=new IntersectionObserver(entries=>{
   visible=entries[0]?.isIntersecting??false;sync();
  },{threshold:.12});
  observer.observe(node);
  preference.addEventListener('change',change);
  document.addEventListener('visibilitychange',sync);
  window.addEventListener('pointermove',move,{passive:true});
  window.addEventListener('pointerdown',move,{passive:true});
  window.addEventListener('pointerup',release,{passive:true});
  window.addEventListener('pointercancel',release,{passive:true});
  window.addEventListener('pointerout',leave,{passive:true});
  window.addEventListener('blur',blur);
  window.addEventListener('resize',scroll,{passive:true});
  window.addEventListener('scroll',scroll,{passive:true,capture:true});
  sync();
  return ()=>{
   cancelAnimationFrame(frame);clearBlink();observer.disconnect();
   preference.removeEventListener('change',change);
   document.removeEventListener('visibilitychange',sync);
   window.removeEventListener('pointermove',move);
   window.removeEventListener('pointerdown',move);
   window.removeEventListener('pointerup',release);
   window.removeEventListener('pointercancel',release);
   window.removeEventListener('pointerout',leave);
   window.removeEventListener('blur',blur);
   window.removeEventListener('resize',scroll);
   window.removeEventListener('scroll',scroll,true);
   node.dataset.active='false';reset();
  };
 },[animate,paused]);

 const variables={
  '--mascot-size':typeof size==='number'?`${size}px`:size,
  '--mascot-eyes':colors?.eyes??'#b1ffe6',
  '--mascot-glow':colors?.glow??'#159c8b',
  '--mascot-halo':colors?.halo??'#dcd5f5',
  '--mascot-hue':`${bodyHue}deg`,
 } as CSSProperties;
 return <div ref={host} className={`${styles.mascot} ${styles[placement]} ${className}`} style={variables} data-mascot data-active="false">
  <span className={styles.shadow} aria-hidden="true"/>
  <div className={styles.breathe}>
   <div ref={face} className={styles.face} role="img" aria-label={label}>
    <Image className={styles.body} src="/mascot/field-assist-robot.png" alt="" width={1024} height={1024} sizes="(max-width:800px) 180px, 260px" loading="eager" draggable={false}/>
    {[0,1].map(index=><svg key={index} ref={element=>{eyes.current[index]=element;}} className={`${styles.eye} ${index===0?styles.left:styles.right}`} viewBox="0 0 100 80" aria-hidden="true" data-mascot-eye={index}>
     <defs>
      <clipPath id={`${id}-eye-${index}`}><ellipse cx="50" cy="40" rx="46" ry="36"/></clipPath>
     </defs>
     <g clipPath={`url(#${id}-eye-${index})`}>
      <g ref={element=>{pupils.current[index]=element;}} data-mascot-pupil={index}>
       <path className={styles.eyeGlow} d="M24 46 Q50 18 76 46"/>
       <path className={styles.eyeLight} d="M24 46 Q50 18 76 46"/>
       <path className={styles.eyeHighlight} d="M28 43 Q50 22 72 43"/>
      </g>
     </g>
    </svg>)}
   </div>
  </div>
  {animate&&<button className={styles.pause} type="button" onClick={()=>setPaused(value=>!value)} aria-pressed={paused} aria-label={paused?'Resume mascot animation':'Pause mascot animation'} title={paused?'Resume mascot':'Pause mascot'}>{paused?<Play size={12}/>:<Pause size={12}/>}</button>}
 </div>;
}
