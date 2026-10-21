'use client';
import Link from 'next/link';
import {useEffect,useState} from 'react';
import {ArrowLeft,ArrowUpRight,Building2,GitBranch,MessageCircle,Users} from 'lucide-react';
import {roleLabels,type AccountRole} from '@field-assist/contracts/access';
import {api,useResource} from '@/lib/api';
import {Avatar} from './avatar';
import {PageHead,Loading,ErrorBanner,Empty} from './ui';
import s from './organisation.module.css';

type Person={id:string;name:string;email:string;avatarId:string;role:string;department:string;jobTitle:string;employeeCode:string;baseLocation?:string;teamId:string|null};
type Team={id:string;name:string;department:string;leadId:string;lead?:Person|null;members:Person[];memberCount:number};
type OrganisationData={organisation:{id:string;name:string};counts:{people:number;teams:number;departments:number;unassigned:number};departments:{name:string;people:number}[];teams:Team[];limited:boolean};
const role=(p:Person)=>roleLabels[p.role as AccountRole]??p.role;
const squadUrl=(id:string)=>`/people?teamId=${encodeURIComponent(id)}`;

export function ColleagueLink({person,subtitle}:{person:Person;subtitle?:string}){
 return <Link className={s.person} href={`/people/${person.id}`}><Avatar person={person} size={36}/><span><strong>{person.name}</strong><small>{subtitle??(person.jobTitle||role(person))}</small></span><ArrowUpRight size={14} aria-hidden="true"/></Link>;
}
function MessageButton({id,onError}:{id:string;onError:(error:string)=>void}){
 const [busy,setBusy]=useState(false);
 return <button className="button secondary" disabled={busy} onClick={async()=>{setBusy(true);onError('');try{const c=await api('conversations',{method:'POST',body:JSON.stringify({recipientId:id})});window.location.assign(`/messages?conversation=${c.id}`);}catch(e){onError((e as Error).message);setBusy(false);}}}><MessageCircle size={15}/>{busy?'Opening…':'Message'}</button>;
}

export function Organisation(){
 const r=useResource<OrganisationData>('organisation',30000),[search,setSearch]=useState(''),[department,setDepartment]=useState('');
 if(r.loading&&!r.data)return <Loading/>;
 if(!r.data)return <ErrorBanner message={r.error} retry={r.reload}/>;
 const data=r.data,q=search.toLowerCase().trim(),teams=data.teams.filter(t=>(!department||t.department===department)&&(!q||`${t.name} ${t.department} ${t.lead?.name??''}`.toLowerCase().includes(q)));
 return <><PageHead eyebrow="PEOPLE. TEAMS. CONNECTIONS." title="Organisation" description="See how your organisation works together. Open any colleague to explore their team and responsible lead." actions={<Link className="button secondary" href="/people"><Users size={16}/>People directory</Link>}/>
  <div className={s.intro}><div><h2>{data.organisation.name}</h2><p>Start with a department, find its squads, then meet the people doing the work. Team connections are visible to everyone in this workspace.</p></div><GitBranch size={34} color="var(--primary)" aria-hidden="true"/></div>
  <div className={s.stats}>{[[data.counts.people,'Active colleagues'],[data.counts.departments,'Departments'],[data.counts.teams,'Active squads'],[data.counts.unassigned,'Without a primary squad']].map(([value,label])=><div className={`panel ${s.stat}`} key={label}><strong>{value}</strong><span>{label}</span></div>)}</div>
  <div className={s.toolbar}><label>Find a squad or lead<input type="search" value={search} onChange={e=>setSearch(e.target.value)} placeholder="Squad, lead or department"/></label><label>Squad department<select value={department} onChange={e=>setDepartment(e.target.value)}><option value="">All departments</option>{data.departments.filter(d=>d.name).map(d=><option key={d.name}>{d.name}</option>)}</select></label></div>
  {department&&<p style={{marginBottom:20}}><Link className="text-link" href={`/people?department=${encodeURIComponent(department)}`}>Browse colleagues in {department} <ArrowUpRight size={14}/></Link></p>}
  <ErrorBanner message={r.error} retry={r.reload}/>
  {teams.length?<div className={s.grid}>{teams.map(t=><section key={t.id} className={`panel ${s.team}`}><span className={s.tag}><Building2 size={13}/>{t.department}</span><h2>{t.name}</h2><div className={s.relationTitle}>Responsible team lead</div>{t.lead?<ColleagueLink person={t.lead} subtitle="Team lead"/>:<p className={s.muted}>No active lead available. An administrator can update this squad.</p>}<div className={s.tree}>{t.members.map(p=><ColleagueLink key={p.id} person={p}/>)}{!t.memberCount&&<p className={s.emptyTeam}>No other members assigned yet.</p>}</div><div className={s.teamFoot}><span className={s.muted}>{t.memberCount} {t.memberCount===1?'member':'members'}{t.memberCount>t.members.length?` · showing ${t.members.length}`:''}</span><Link className="text-link" href={squadUrl(t.id)}>View squad people <ArrowUpRight size={14}/></Link></div></section>)}</div>:<Empty title="No squads match" detail="Try another department or look up a colleague in the people directory." action={<Link className="button secondary" href="/people">Find people</Link>}/>}
  {data.limited&&<p className={s.note}>Showing the first 200 squads. Use the people directory to find colleagues across the full organisation.</p>}
  <section className={`panel ${s.unassigned}`}><div><h2>Every colleague has a place here.</h2><p>People without a primary squad remain visible in the directory. Administrators can set squad membership from the employee’s account.</p></div><Link className="text-link" href="/people?unassigned=true">View unassigned colleagues <ArrowUpRight size={14}/></Link></section>
  <p className={s.note}>Reporting connections come from primary squad membership and its responsible lead. Dashboard access levels control permissions; they do not imply a management relationship.</p>
 </>;
}

export function PeopleDirectory(){
 const [query,setQuery]=useState(''),[search,setSearch]=useState(''),[department,setDepartment]=useState(''),[team,setTeam]=useState(''),[unassigned,setUnassigned]=useState(false),[offset,setOffset]=useState(0),[error,setError]=useState('');
 useEffect(()=>{const p=new URLSearchParams(window.location.search);setTeam(p.get('teamId')??'');setDepartment(p.get('department')??'');setUnassigned(p.get('unassigned')==='true');},[]);
 useEffect(()=>{const timer=window.setTimeout(()=>{setSearch(query);setOffset(0);},250);return()=>window.clearTimeout(timer);},[query]);
 const org=useResource<OrganisationData>('organisation'),me=useResource('me'),params=new URLSearchParams({search,limit:'30',offset:String(offset),...(department?{department}:{}),...(team?{teamId:team}:{}),...(unassigned?{unassigned:'true'}:{})}),r=useResource(`directory?${params}`);
 const selectedTeam=org.data?.teams.find(t=>t.id===team);
 return <><PageHead eyebrow="KNOW WHO TO REACH" title="People directory" description="Find colleagues by name, email, employee ID, department or squad. Approximate spellings work too." actions={<Link className="button secondary" href="/organisation"><GitBranch size={16}/>Explore organisation</Link>}/>
  <div className={s.toolbar}><label>Search the organisation<input type="search" value={query} onChange={e=>{setQuery(e.target.value);setOffset(0);}} placeholder="Name, department or squad—even with a typo"/></label><label>Department<select value={department} onChange={e=>{setDepartment(e.target.value);setOffset(0);}}><option value="">All departments</option>{org.data?.departments.filter(d=>d.name).map(d=><option key={d.name}>{d.name}</option>)}</select></label></div>
  {(team||unassigned)&&<div className={s.intro}><div><h2>{unassigned?'Without a primary squad':selectedTeam?.name??'Selected squad'}</h2><p>{selectedTeam?.lead?`Team lead: ${selectedTeam.lead.name}`:'Showing colleagues in this selection.'}</p></div><button className="button secondary" onClick={()=>{setTeam('');setUnassigned(false);setOffset(0);window.history.replaceState(null,'','/people');}}>Show all colleagues</button></div>}
  <ErrorBanner message={error||r.error} retry={r.reload}/>{r.loading?<Loading/>:!r.data?.items.length?<Empty title="No matching colleagues" detail="Try another name or department, or clear the squad selection."/>:<div className={s.contactGrid}>{r.data.items.map((p:any)=><article key={p.id} className={`panel ${s.contactCard}`}><Link href={`/people/${p.id}`} aria-label={`View ${p.name}'s profile`}><Avatar person={p} size={48}/><h2>{p.name}</h2></Link><p>{p.jobTitle||role(p)}</p><p>{p.department||'Department not supplied'}</p><p>{p.email}</p><div className={s.leadLine}><p><strong>{p.teamName??'No primary squad'}</strong></p>{p.leadName&&<p>Lead: {p.leadId===p.id?'This colleague':<Link href={`/people/${p.leadId}`}>{p.leadName}</Link>}</p>}</div><div className={s.actions} style={{marginTop:16}}><Link className="text-link" href={`/people/${p.id}`}>View profile & organisation <ArrowUpRight size={14}/></Link>{p.id!==me.data?.id&&<MessageButton id={p.id} onError={setError}/>}</div></article>)}</div>}
  <div className={s.pagination}><span className={s.muted}>Active colleagues in your organisation</span><div className={s.actions}>{offset>0&&<button className="button secondary" onClick={()=>setOffset(Math.max(0,offset-30))}>Previous</button>}{r.data?.nextOffset!==null&&r.data?.nextOffset!==undefined&&<button className="button secondary" onClick={()=>setOffset(r.data.nextOffset)}>More people</button>}</div></div>
 </>;
}

export function ColleagueProfile({id}:{id:string}){
 const r=useResource(`directory/${id}`,30000),me=useResource('me'),[tab,setTab]=useState<'organisation'|'about'>('organisation'),[error,setError]=useState('');
 if(r.loading&&!r.data)return <Loading/>;
 if(!r.data||r.data.person.id!==id)return <><Link className="text-link" href="/people">Back to people</Link><ErrorBanner message={r.error} retry={r.reload}/></>;
 const {person:p,primaryTeam:team,teamsLed,reports,reportCount,peers,peerCount}=r.data;
 return <><Link className={`text-link ${s.back}`} href="/people"><ArrowLeft size={14}/>People directory</Link><PageHead eyebrow="YOUR COLLEAGUE" title="Employee profile" description="A little context makes it easier to reach the right person." actions={<Link className="button secondary" href="/organisation"><GitBranch size={16}/>Full organisation</Link>}/>
  <section className={`panel ${s.profileHero}`}><div className={s.identity}><Avatar person={p} size={76}/><div><h2>{p.name}</h2><p>{p.jobTitle||role(p)}</p><p>{p.department||'Department not supplied'} · {r.data.organisation.name}</p></div></div><div className={s.actions}>{p.id===me.data?.id?<Link className="button secondary" href="/profile">Edit your profile</Link>:<MessageButton id={p.id} onError={setError}/>}</div></section><ErrorBanner message={error||r.error} retry={r.reload}/>
  <div className={s.tabs} role="group" aria-label="Employee profile views"><button aria-pressed={tab==='organisation'} onClick={()=>setTab('organisation')}><GitBranch size={14} style={{verticalAlign:'middle',marginRight:7}}/>Organisation</button><button aria-pressed={tab==='about'} onClick={()=>setTab('about')}>About</button></div>
  {tab==='about'?<dl className={`panel ${s.details}`}>{[['Work email',p.email],['Department',p.department],['Job title',p.jobTitle],['Employee ID',p.employeeCode],['Work location',p.baseLocation],['Primary squad',team?.name]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value||'Not supplied'}</dd></div>)}</dl>:<div className={s.grid}>
   <section className={`panel ${s.section}`}><h2>Team reporting</h2><div className={s.relationTitle}>Reports to · primary squad lead</div>{team?.lead?<><ColleagueLink person={team.lead} subtitle={`${team.name} · Team lead`}/><div className={s.connector}/></>:<p className={s.muted} style={{marginBottom:16}}>{team?.leadId===p.id?'This colleague leads their primary squad.':team?'No active lead available for this squad.':'No primary squad assigned.'}</p>}<div className={s.focusPerson}><Avatar person={p} size={42}/><div><strong>{p.name}</strong><small>{p.jobTitle||role(p)}</small></div></div>{team&&<Link className="text-link" style={{marginTop:16}} href={squadUrl(team.id)}>Meet {team.name} <ArrowUpRight size={14}/></Link>}<p className={s.note}>{r.data.reportingBasis}. Organisation connections do not change data-access permissions.</p></section>
   <section className={`panel ${s.section}`}><h2>Squads they lead · {teamsLed.length}</h2>{teamsLed.length?<div className={s.stack}>{teamsLed.map((t:Team)=><Link key={t.id} className={s.person} href={squadUrl(t.id)}><Users size={21}/><span><strong>{t.name}</strong><small>{t.department}</small></span><ArrowUpRight size={14}/></Link>)}</div>:<p className={s.muted}>No lead responsibility assigned.</p>}</section>
   <section className={`panel ${s.section}`}><h2>People they lead · {reportCount}</h2>{reports.length?<div className={s.stack}>{reports.map((person:Person)=><ColleagueLink key={person.id} person={person}/>)}</div>:<p className={s.muted}>No colleagues assigned under this person’s squads.</p>}{reportCount>reports.length&&<p className={s.note}>Showing {reports.length} of {reportCount}. Open a squad above to browse all its people.</p>}</section>
   <section className={`panel ${s.section}`}><h2>Works with · {peerCount}</h2>{peers.length?<div className={s.stack}>{peers.map((person:Person)=><ColleagueLink key={person.id} person={person}/>)}</div>:<p className={s.muted}>No other primary-squad colleagues to show.</p>}{team&&peerCount>peers.length&&<Link className="text-link" style={{marginTop:15}} href={squadUrl(team.id)}>View all squad colleagues <ArrowUpRight size={14}/></Link>}</section>
  </div>}
 </>;
}
