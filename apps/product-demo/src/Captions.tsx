import React from 'react';
import type {CaptionCue} from './caption-cues.mjs';
import {font} from './visuals';

export function Captions({cue}:{cue:CaptionCue|null}) {
  if(!cue)return null;
  return <div data-demo-captions="visible" style={{position:'absolute',bottom:32,left:120,right:120,zIndex:10,display:'flex',justifyContent:'center',pointerEvents:'none',fontFamily:font}}>
    <div style={{maxWidth:1640,padding:'8px 25px',borderRadius:13,background:'rgba(6,8,15,0.94)',border:'1px solid #a99afb3d',boxShadow:'0 8px 25px #0004',color:'#fff',fontSize:32,fontWeight:500,lineHeight:1.18,textAlign:'center',whiteSpace:'pre-line',letterSpacing:.05}}>{cue.lines.join('\n')}</div>
  </div>;
}
