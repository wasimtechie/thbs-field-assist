import React, {useRef,useState,useEffect} from 'react';
import {createRoot} from 'react-dom/client';
import {Player,type PlayerRef} from '@remotion/player';
import {ArrowRight, Film, Maximize, Play, RotateCcw} from 'lucide-react';
import {ProductFilm} from './Film';
import {chapters,DURATION,FPS,WIDTH,HEIGHT} from './timeline';
import './style.css';
import {VoicePromo,PROMO_DURATION,promoScenes} from './voice-promo/VoicePromo';

const mmss=(frame:number)=>`${Math.floor(frame/FPS/60)}:${String(Math.floor(frame/FPS)%60).padStart(2,'0')}`;
function LegacyDemoPage() {
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
function VoicePromoPage(){
  const player=useRef<PlayerRef>(null);const [active,setActive]=useState(0);
  useEffect(()=>{const instance=player.current;if(!instance)return;const update=({detail}:{detail:{frame:number}})=>setActive(Math.max(0,promoScenes.findIndex(s=>s.from+s.durationInFrames>detail.frame)));instance.addEventListener('frameupdate',update);return()=>instance.removeEventListener('frameupdate',update);},[]);
  return <main className="demo-page promo-page">
    <header className="demo-header"><a href="/" className="demo-brand"><span>THBS</span> Field Assist<span className="brand-dot">.</span></a><span className="presentation-tag"><Film size={15}/> VOICE PROMO</span></header>
    <div className="demo-intro"><div><p className="demo-kicker">VOICE-ASSISTED JOB COMPLETION</p><h1>Speak the visit.<br/><span>Complete the record.</span></h1><p>A voice journey designed for the applications engineers already use.</p></div><div className="demo-meta"><span>{mmss(PROMO_DURATION)} · 1080p · narrated + captioned</span><button onClick={()=>player.current?.requestFullscreen()}><Maximize size={16}/> Present fullscreen</button></div></div>
    <section className="demo-player" aria-label="Field Assist voice promo">
      <Player ref={player} component={VoicePromo} durationInFrames={PROMO_DURATION} fps={30} compositionWidth={1920} compositionHeight={1080} controls showVolumeControls style={{width:'100%',aspectRatio:'16/9'}} acknowledgeRemotionLicense showPosterWhenUnplayed showPosterWhenEnded renderPoster={()=><img src="/voice-promo/poster.jpg" alt="Speak the visit. Complete the record. — Field Assist voice promo" style={{width:'100%',height:'100%',objectFit:'cover'}}/>}/>
    </section>
    <div className="demo-tools"><span>{String(active+1).padStart(2,'0')} / {promoScenes.length} · {promoScenes[active].label}</span><button onClick={()=>{player.current?.seekTo(0);player.current?.play();}}><RotateCcw size={15}/> Play from start</button></div>
    <nav className="chapter-grid" aria-label="Jump to a voice promo scene">{promoScenes.map((s,i)=><button key={s.id} className={i===active?'selected':''} aria-current={i===active?'step':undefined} onClick={()=>{player.current?.seekTo(s.from+1);player.current?.play();}}><small>{String(i+1).padStart(2,'0')} <span>{mmss(s.from)}</span></small><strong>{s.label}</strong><Play size={15}/></button>)}</nav>
    <footer className="demo-footer"><p>Illustrative synthetic workflow. Recognition benchmark scope is shown in the film. Integration and fine-tuning are proposed engagements.</p><div style={{display:'flex',gap:25}}><a href="/voice-promo/Field-Assist-Voice-Promo.mp4" download>Download MP4 <ArrowRight size={15}/></a><a href="?film=product">Full product walkthrough <ArrowRight size={15}/></a></div></footer>
  </main>;
}
createRoot(document.getElementById('root')!).render(new URLSearchParams(location.search).get('film')==='product'?<LegacyDemoPage/>:<VoicePromoPage/>);
