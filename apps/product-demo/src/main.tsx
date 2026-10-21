import React, {useRef,useState,useEffect} from 'react';
import {createRoot} from 'react-dom/client';
import {Player,type PlayerRef} from '@remotion/player';
import {ArrowRight, Film, Maximize, Play, RotateCcw} from 'lucide-react';
import {ProductFilm} from './Film';
import {chapters,DURATION,FPS,WIDTH,HEIGHT} from './timeline';
import './style.css';

const mmss=(frame:number)=>`${Math.floor(frame/FPS/60)}:${String(Math.floor(frame/FPS)%60).padStart(2,'0')}`;
function DemoPage() {
  const player=useRef<PlayerRef>(null);const [active,setActive]=useState(0);const [ready,setReady]=useState(false);
  useEffect(()=>{const instance=player.current;if(!instance)return;const update=({detail}:{detail:{frame:number}})=>setActive(chapters.findIndex(c=>c.from+c.durationInFrames>detail.frame));instance.addEventListener('frameupdate',update);setReady(true);return()=>instance.removeEventListener('frameupdate',update);},[]);
  return <main className="demo-page">
    <header className="demo-header"><a href="http://localhost:3000/" className="demo-brand"><span>THBS</span> Field Assist<span className="brand-dot">.</span></a><span className="presentation-tag"><Film size={15}/> PRODUCT FILM</span></header>
    <div className="demo-intro"><div><p className="demo-kicker">THE TORRY HARRIS TEAM PRESENTS</p><h1>From request to <span>review.</span></h1><p>A connected journey through the dashboard and engineer app.</p></div><div className="demo-meta"><span>{mmss(DURATION)} · 1080p · narrated</span><button onClick={()=>player.current?.requestFullscreen()}><Maximize size={16}/> Present fullscreen</button></div></div>
    <section className="demo-player" aria-label="THBS Field Assist product demo">
      <Player ref={player} component={ProductFilm} durationInFrames={DURATION} fps={FPS} compositionWidth={WIDTH} compositionHeight={HEIGHT} controls showVolumeControls style={{width:'100%',aspectRatio:'16/9'}} acknowledgeRemotionLicense autoPlay={false} showPosterWhenUnplayed showPosterWhenEnded renderPoster={()=><img src="/poster.jpg" alt="THBS Field Assist — one connected client-to-field journey" style={{width:'100%',height:'100%',objectFit:'cover'}}/>}/>
    </section>
    <div className="demo-tools"><span>{String(Math.max(active,0)+1).padStart(2,'0')} / {chapters.length} · {chapters[Math.max(active,0)].label}</span><button disabled={!ready} onClick={()=>{player.current?.seekTo(0);player.current?.play();}}><RotateCcw size={15}/> Play from start</button></div>
    <nav className="chapter-grid" aria-label="Jump to a feature">{chapters.map((c,i)=><button key={c.id} className={i===active?'selected':''} aria-current={i===active?'step':undefined} onClick={()=>{player.current?.seekTo(c.from+1);player.current?.play();}}><small>{String(i+1).padStart(2,'0')} <span>{mmss(c.from)}</span></small><strong>{c.label}</strong><Play size={15}/></button>)}</nav>
    <footer className="demo-footer"><p>Actual product screens with synthetic demo data and illustrative workflow scenes.</p><a href="http://localhost:3000/dashboard">Open the dashboard <ArrowRight size={15}/></a></footer>
  </main>;
}
createRoot(document.getElementById('root')!).render(<DemoPage/>);
