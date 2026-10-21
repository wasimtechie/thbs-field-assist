'use client';

import {useId, useRef, useState} from 'react';
import {motion, useMotionValue, useReducedMotion, useScroll, useSpring, useTransform} from 'motion/react';
import {ArrowRight, ArrowUpRight, Blocks, Cloud, Database, GitBranch, Layers, Network, Radio, Server, Sparkles} from 'lucide-react';
import styles from './company-story.module.css';

// Company capabilities are paraphrased from the linked Torry Harris service pages.
const capabilities = [
  {title:'Integration & APIs', text:'Connect legacy applications, cloud services and partners through reusable APIs, orchestration and governance.', outcome:'Connected systems.', detail:'Bring the right services together through an integration architecture built for reuse.', href:'https://www.torryharris.com/services/application-integration-and-orchestration', icon:GitBranch, nodes:[0,2]},
  {title:'Cloud & modernization', text:'Modernize applications and manage hybrid cloud environments with security, reliability and operational governance.', outcome:'Resilient operations.', detail:'Evolve the technology estate while keeping business continuity in view.', href:'https://www.torryharris.com/services/managed-cloud-and-governance', icon:Cloud, nodes:[0,1]},
  {title:'Data & intelligent automation', text:'Bring fragmented data together and create governed foundations for analytics, intelligent automation and agentic AI.', outcome:'Trusted intelligence.', detail:'Connect data to the systems and decisions that need it.', href:'https://www.torryharris.com/services/data-intelligence-and-agentic-ai', icon:Sparkles, nodes:[2,3]},
  {title:'Digital platforms & ecosystems', text:'Design digital marketplaces and partner ecosystems that connect services, simplify onboarding and support new business models.', outcome:'New possibilities.', detail:'Create connected experiences for customers, partners and the people who serve them.', href:'https://www.torryharris.com/services/digital-marketplace-implementation', icon:Blocks, nodes:[4,5]},
];
const nodes = [
  {x:100,y:157,label:'Enterprise systems',icon:Server},
  {x:100,y:302,label:'Cloud',icon:Cloud},
  {x:500,y:157,label:'APIs',icon:GitBranch},
  {x:500,y:302,label:'Data & AI',icon:Database},
  {x:300,y:70,label:'Platforms',icon:Layers},
  {x:300,y:394,label:'People',icon:Network},
];
const paths = ['M100 157H185L255 197','M100 302H185L255 263','M500 157H415L345 197','M500 302H415L345 263','M300 70V184','M300 394V278'];
const delivery = [
  {title:'Understand',text:'Start with the business challenge, users and constraints. Agree what success should look like.'},
  {title:'Architect',text:'Map the systems, data and interfaces. Design for security, reuse and the client’s existing estate.'},
  {title:'Engineer',text:'Build the experience, connect the services and validate the complete journey with the client.'},
  {title:'Evolve',text:'Support operations, monitor service quality and improve the solution as business needs change.'},
];

export default function CompanyStory() {
  const [active,setActive] = useState(0);
  const reduced = useReducedMotion();
  const root = useRef<HTMLElement>(null);
  const id = useId();
  const {scrollYProgress} = useScroll({target:root,offset:['start 85%','end 35%']});
  const draw = useTransform(scrollYProgress,[0,.55],[.15,1]);
  const pointerX = useMotionValue(0), pointerY = useMotionValue(0);
  const rotateX = useSpring(pointerX,{stiffness:100,damping:24});
  const rotateY = useSpring(pointerY,{stiffness:100,damping:24});
  const selected = capabilities[active];

  return <>
    <section id="thbs" className={`${styles.company} landing-container`} aria-labelledby={`${id}-about`}>
      <div className={styles.companyIdentity}>
        <span className={styles.eyebrow}>THE TEAM BEHIND THE DEMO</span>
        <p className={styles.companyName}>Torry Harris<br/>Business Solutions<span>.</span></p>
        <a href="https://www.torryharris.com/about-us/corporate-overview" target="_blank" rel="noopener noreferrer" className={styles.sourceLink}>Get to know Torry Harris <ArrowUpRight size={16}/></a>
      </div>
      <div className={styles.companyIntroduction}>
        <h2 id={`${id}-about`}>Built on integration.<br/>Focused on your business.</h2>
        <p>We connect enterprise systems, modernize technology and build digital ecosystems. From integration and API management to cloud, data and AI, Torry Harris helps clients turn existing technology into connected business capabilities.</p>
        <div className={styles.industries}><span>EXPERTISE ACROSS</span><p>Telecommunications <i/> Financial services <i/> Manufacturing <i/> Public sector <i/> Energy & utilities</p></div>
      </div>
    </section>

    <section id="solutions" ref={root} className={styles.solutions} aria-labelledby={`${id}-solutions`}>
      <div className="landing-container">
        <div className={styles.sectionHeading}>
          <div><span className={styles.eyebrow}>WHAT WE HELP CLIENTS DO</span><h2 id={`${id}-solutions`}>Turn complexity<br/>into connection.</h2></div>
          <p>One connected view of your technology.<br/>More ways to move your business forward.</p>
        </div>
        <div className={styles.capabilityLayout}>
          <div className={styles.capabilities} aria-label="Explore Torry Harris capabilities">
            {capabilities.map((item,index) => {
              const Icon = item.icon;
              return <button type="button" key={item.title} className={styles.capability} aria-pressed={active===index} aria-controls={`${id}-illustration`} onClick={()=>setActive(index)}>
                <span className={styles.capabilityNumber}>0{index+1}</span>
                <span className={styles.capabilityCopy}><span className={styles.capabilityTitle}><Icon size={19} strokeWidth={1.6}/><strong>{item.title}</strong></span><span className={styles.capabilityText}>{item.text}</span></span>
                <ArrowUpRight size={18} className={styles.capabilityArrow}/>
              </button>;
            })}
          </div>
          <figure id={`${id}-illustration`} className={styles.figure} onPointerMove={event=>{
            if(reduced || event.pointerType!=='mouse') return;
            const rect=event.currentTarget.getBoundingClientRect();
            pointerX.set((.5-(event.clientY-rect.top)/rect.height)*5);
            pointerY.set(((event.clientX-rect.left)/rect.width-.5)*5);
          }} onPointerLeave={()=>{pointerX.set(0);pointerY.set(0);}}>
            <div className={styles.figureTopline}><span><i/>CONNECTED ENTERPRISE</span><span>0{active+1} / 04</span></div>
            <motion.svg viewBox="0 0 600 470" className={styles.network} aria-hidden="true" style={{rotateX,rotateY,transformPerspective:1000}}>
              <g className={styles.grid} fill="none"><path d="M300 105 565 250 300 405 35 250Z"/><path d="M100 285 365 140M165 325 430 175M235 365 500 210M100 215 365 365M165 175 435 325M235 140 500 285"/></g>
              {paths.map((path,index)=><g key={path}><path d={path} className={styles.connectionBase}/><motion.path d={path} className={styles.connection} data-highlighted={selected.nodes.includes(index)} style={{pathLength:draw}}/></g>)}
              {nodes.map((node,index)=>{
                const Icon=node.icon, highlighted=selected.nodes.includes(index);
                return <g key={node.label} transform={`translate(${node.x} ${node.y})`} className={styles.node} data-highlighted={highlighted}>
                  <motion.g initial={{y:0}} animate={{y:reduced?0:highlighted?-5:0}} transition={{type:'spring',stiffness:170,damping:22}}>
                    <path d="M-43 0 0 23 43 0V15L0 39-43 15Z" className={styles.nodeSide}/>
                    <path d="M-43 0 0-24 43 0 0 24Z" className={styles.nodeTop}/>
                    <Icon x={-12} y={-17} width={24} height={24} strokeWidth={1.5}/>
                  </motion.g>
                  <text y={61} textAnchor="middle">{node.label}</text>
                </g>;
              })}
              <g className={styles.hub}>
                <path d="M214 218 300 266 386 218V245L300 294 214 245Z" className={styles.hubSide}/>
                <path d="M214 218 300 170 386 218 300 267Z" className={styles.hubTop}/>
                <text x={300} y={224} textAnchor="middle">THBS</text>
                <path d="M256 242 300 267 344 242" fill="none"/>
              </g>
            </motion.svg>
            <figcaption className={styles.figureCaption} aria-live="polite">
              <div><span className={styles.eyebrow}>THE CLIENT OPPORTUNITY</span><h3>{selected.outcome}</h3><p>{selected.detail}</p></div>
              <a href={selected.href} target="_blank" rel="noopener noreferrer" aria-label={`Explore ${selected.title} at Torry Harris`}><ArrowUpRight size={21}/></a>
            </figcaption>
            <span className={styles.figureNote}>An illustration of Torry Harris capabilities</span>
          </figure>
        </div>
      </div>
    </section>

    <section className={`${styles.delivery} landing-container`} aria-labelledby={`${id}-delivery`}>
      <div className={styles.sectionHeading}><div><span className={styles.eyebrow}>HOW WE WORK WITH CLIENTS</span><h2 id={`${id}-delivery`}>From the challenge<br/>to the everyday.</h2></div><p>Business context first. Connected engineering next.<br/>A solution that keeps working after launch.</p></div>
      <div className={styles.deliveryJourney}>
        <motion.div className={styles.deliveryLine} aria-hidden="true" initial={{scaleX:0}} whileInView={{scaleX:1}} viewport={{once:true,amount:.8}} transition={{duration:reduced?0:1,ease:'easeOut'}}/>
        {delivery.map((item,index)=><article key={item.title}><span className={styles.deliveryNumber}>0{index+1}</span><h3>{item.title}</h3><p>{item.text}</p></article>)}
      </div>
      <div className={styles.deliveryLinks}><span>Built around your business, your systems and your teams.</span><a href="https://www.torryharris.com/global-capability-center/conceptualization-build" target="_blank" rel="noopener noreferrer">Explore our approach <ArrowUpRight size={15}/></a></div>
    </section>

    <section className={`${styles.demoContext} landing-container`} aria-labelledby={`${id}-demo`}>
      <span className={styles.demoMark} aria-hidden="true"><Radio size={31} strokeWidth={1.4}/></span>
      <div><span className={styles.eyebrow}>THBS FIELD ASSIST · THIS DEMO</span><h2 id={`${id}-demo`}>Connected thinking.<br/>Out in the field.</h2></div>
      <div className={styles.demoCopy}><p>For teams working beyond reliable connectivity, this demo brings offline forms, local voice assistance and captured report locations into one operations workspace.</p><a href="#workflow">Follow the reporting journey <ArrowRight size={17}/></a><small>Reports in this demo flow into the THBS Field Assist workspace.</small></div>
    </section>
  </>;
}
