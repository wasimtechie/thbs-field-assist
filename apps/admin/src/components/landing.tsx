'use client';

import Link from 'next/link';
import {useState} from 'react';
import {ArrowRight,ArrowUpRight,Check,CheckCheck,ChevronRight,FileCheck2,Layers,LockKeyhole,Mic,Radio,ShieldCheck,Smartphone,WifiOff} from 'lucide-react';
import {Brand} from './shell';
import RobotMascot from './robot-mascot';
import mascotStyles from './robot-mascot.module.css';
import CompanyStory from './company-story';
import entrance from './landing-motion.module.css';

const steps=[
 {title:'Make it fit your team.',label:'01 / CONFIGURE',text:'Build and publish the right form for each engineer type. Change questions, units, and required fields from your dashboard.',icon:Layers,heading:'The right form. Every time.',detail:'Fibre, repairs, business, and surveys — each team gets its assigned template.'},
 {title:'Capture it in the field.',label:'02 / CAPTURE',text:'Open an installed form without a signal. Speak naturally or use touch, check the answers, and keep a saved draft as you go.',icon:Mic,heading:'A little less typing.',detail:'Voice proposes answers. The engineer stays in control and reviews every report.'},
 {title:'Bring the work together.',label:'03 / CONNECT',text:'Confirm the report on the device. When connectivity returns, sync it to a shared workspace with a receipt you can trace.',icon:FileCheck2,heading:'From saved to received.',detail:'See accepted reports, their original form version, and the last status reported by each device.'},
];

export default function Landing(){
 const [active,setActive]=useState(0);const StepIcon=steps[active].icon;
 return <div className="landing">
  <a className="landing-skip" href="#main">Skip to content</a>
  <header className="landing-header landing-container">
   <Link href="/" aria-label="THBS Field Assist home"><Brand/></Link>
   <nav aria-label="Main navigation"><a href="#thbs">About THBS</a><a href="#solutions">Our expertise</a><a href="#workflow">How it works</a><a href="#platforms">Built for the field</a></nav>
   <Link href="/login" className="landing-signin">Workspace sign in <ArrowUpRight size={17}/></Link>
  </header>
  <main id="main">
   <section className="landing-hero landing-container">
    <div className={`landing-hero-copy ${entrance.copy}`}>
     <div className="landing-kicker"><span/>TORRY HARRIS BUSINESS SOLUTIONS · TEAM DEMO</div>
     <h1><span className={`landing-title-line ${entrance.line}`}>Less paperwork.</span>{' '}<span className={`landing-title-line ${entrance.line}`}>More <em>fieldwork.</em></span></h1>
     <p>Good work deserves a simpler way to report it. Give your engineers an offline companion and your operations team a clear view of the day.</p>
     <div className="landing-hero-actions"><Link href="/login" className="landing-cta">Open your workspace <ArrowRight size={19}/></Link><a href="#workflow" className="landing-explore">See how it works <ChevronRight size={17}/></a></div>
     <div className="landing-hero-proof"><span><Smartphone size={16}/>Available for iOS & Android</span><span><WifiOff size={16}/>Offline reporting</span></div>
    </div>
    <div className={`landing-scene ${mascotStyles.landingScene} ${entrance.scene}`}>
     <div className="landing-scene-grid"/>
     <svg className="landing-cable" viewBox="0 0 560 620" fill="none" aria-hidden="true"><defs><linearGradient id="cable" x1="70" y1="110" x2="530" y2="540" gradientUnits="userSpaceOnUse"><stop stopColor="#c3b8f5"/><stop offset=".45" stopColor="#7663cd"/><stop offset="1" stopColor="#dfd9f5"/></linearGradient></defs><path d="M-30 415C67 432 109 346 99 238C83 65 366 35 444 167C529 310 395 497 251 468C94 436 140 279 288 300C441 322 359 592 596 542" stroke="#b6a5df" strokeOpacity=".12" strokeWidth="34"/><path d="M-30 404C67 421 109 335 99 227C83 54 366 24 444 156C529 299 395 486 251 457C94 425 140 268 288 289C441 311 359 581 596 531" stroke="url(#cable)" strokeWidth="23"/><path d="M-30 400C67 417 109 331 99 223C83 50 366 20 444 152C529 295 395 482 251 453C94 421 140 264 288 285C441 307 359 577 596 527" stroke="white" strokeOpacity=".3" strokeWidth="3"/></svg>
     <div className="landing-floating-tag"><span className="landing-signal"><WifiOff size={16}/></span><div><strong>No signal? Keep going.</strong><span>Installed forms work offline.</span></div></div>
     <div className="landing-phone" aria-label="Illustrative preview of a fibre engineer report">
      <div className="landing-phone-top"><span>9:41</span><span className="landing-phone-island"/><span>••• ▰</span></div>
      <div className="landing-phone-app"><div className="landing-phone-nav"><Radio size={18}/><span>fieldassist.</span><span className="landing-offline-dot"/></div><div className="landing-phone-label">FIBRE ENGINEER</div><h2>A job well done.<br/>A report made easy.</h2><div className="landing-form-preview"><div className="landing-form-heading"><span>Fibre installation</span><span>2 of 4</span></div><div className="landing-preview-progress"><i/></div><label>Cable installed</label><div className="landing-preview-input"><strong>12</strong><span>metres</span><Check size={14}/></div><label>Line test</label><div className="landing-preview-input"><span>Not tested</span><ChevronRight size={14}/></div><div className="landing-preview-saved"><ShieldCheck size={12}/>Draft saved on device</div></div><div className="landing-voice-preview"><Mic size={17}/><span>Fill by voice</span><div aria-hidden="true">{[8,15,23,12,19,27,13,21,10].map((h,i)=><i key={i} style={{height:h}}/>)}</div></div><div className="landing-illustration-label">ILLUSTRATIVE APP PREVIEW</div></div>
      <span className="landing-home-indicator"/>
     </div>
     <div className="landing-receipt-preview"><span className="landing-receipt-check"><CheckCheck size={20}/></span><div><strong>Reviewed. Ready to sync.</strong><span>Your work, safely on your device.</span></div></div>
     <div className={mascotStyles.landingSlot}><RobotMascot size="100%"/></div>
     <span className={`landing-scene-caption ${mascotStyles.landingCaption}`}>MADE FOR THE PEOPLE WHO KEEP THINGS MOVING</span>
    </div>
   </section>
   <div className="landing-teams landing-container"><span>ONE WORKSPACE.<br/><strong>EVERY KIND OF FIELDWORK.</strong></span><div>Fibre installation</div><div>Repairs & maintenance</div><div>Business services</div><div>Site surveys</div></div>
   <CompanyStory/>
   <section id="workflow" className="landing-workflow landing-container">
    <div className="landing-section-heading"><div><span className="landing-section-label">A CLEARER WAY TO WORK</span><h2>From the first question<br/>to the final receipt.</h2></div><p>A practical flow for engineers on the move<br/>and the team keeping everything connected.</p></div>
    <div className="landing-workflow-layout"><div className="landing-step-list" role="tablist" aria-label="Reporting workflow" aria-orientation="vertical">{steps.map((step,index)=><button key={step.label} role="tab" id={`workflow-tab-${index}`} aria-selected={active===index} aria-controls="workflow-panel" tabIndex={active===index?0:-1} className={active===index?'selected':''} onClick={()=>setActive(index)} onKeyDown={event=>{if(['ArrowDown','ArrowUp','Home','End'].includes(event.key)){event.preventDefault();const next=event.key==='Home'?0:event.key==='End'?2:(active+(event.key==='ArrowDown'?1:2))%3;setActive(next);document.getElementById(`workflow-tab-${next}`)?.focus();}}}><span className="landing-step-number">0{index+1}</span><div><h3>{step.title}</h3><p>{step.text}</p></div><ArrowUpRight size={19}/></button>)}</div><div className={`landing-workflow-panel step-${active}`} role="tabpanel" id="workflow-panel" aria-labelledby={`workflow-tab-${active}`} tabIndex={0}><div className="landing-panel-orbit" aria-hidden="true"/><span className="landing-panel-icon"><StepIcon size={39} strokeWidth={1.5}/></span><div className="landing-panel-copy"><span>{steps[active].label}</span><h3>{steps[active].heading}</h3><p>{steps[active].detail}</p></div><div className="landing-mini-flow"><span><Layers size={15}/>Form</span><i/><span><Smartphone size={15}/>Engineer</span><i/><span><CheckCheck size={15}/>Workspace</span></div></div></div>
   </section>
   <section id="platforms" className="landing-field-section"><div className="landing-container"><div className="landing-section-heading"><div><span className="landing-section-label">OUT THERE IS WHERE IT MATTERS</span><h2>Built around the real<br/>conditions of fieldwork.</h2></div><span className="landing-platform-pill"><Smartphone size={17}/>One app. iOS & Android.</span></div><div className="landing-principles"><article><WifiOff size={25}/><h3>Signal optional.</h3><p>Provision online, then open installed forms and save reports offline within your access period.</p></article><article><Mic size={25}/><h3>Your voice. Your call.</h3><p>Local speech assistance suggests answers. Touch editing and a final review keep you in control.</p></article><article><LockKeyhole size={25}/><h3>Keep work protected.</h3><p>Encrypted local reports, device authentication, and account access managed by your administrator.</p></article></div></div></section>
   <section className="landing-final landing-container"><span className="landing-section-label">LESS FRICTION. MORE FORWARD.</span><h2>Your next good day<br/>in the field starts here.</h2><Link href="/login" className="landing-cta">Sign in to your workspace <ArrowRight size={19}/></Link><p>Already provisioned? Open your field reporting app on your device.</p></section>
  </main>
  <footer className="landing-footer landing-container"><Link href="/" aria-label="THBS Field Assist home"><Brand/></Link><span>A Torry Harris team demonstration.</span><div><span className="landing-demo-label">Synthetic demo environment</span><a href="/avatars/LICENSE.txt">Legal notices</a><a href="https://www.torryharris.com/" target="_blank" rel="noopener noreferrer">Torry Harris <ArrowUpRight size={14}/></a><Link href="/login">Admin sign in <ArrowUpRight size={14}/></Link></div></footer>
 </div>;
}
