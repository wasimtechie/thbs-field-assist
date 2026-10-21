'use client';
import Link from 'next/link';
import {useState,type FormEvent} from 'react';
import {useRouter} from 'next/navigation';
import {GitBranch,Save} from 'lucide-react';
import {avatarStyles,avatarOptions} from '@field-assist/contracts/workspace';
import {api,useResource} from '@/lib/api';
import {Avatar} from './avatar';
import {PageHead,Loading,ErrorBanner} from './ui';
import s from './organisation.module.css';
export function Profile(){
 const r=useResource('me'),router=useRouter(),[choice,setChoice]=useState<string|null>(null),[name,setName]=useState<string|null>(null),[style,setStyle]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[saved,setSaved]=useState('');
 if(r.loading&&!r.data)return <Loading/>;if(!r.data)return <ErrorBanner message={r.error}/>;
 const id=choice??r.data.avatarId??'',options=[{id:'',label:'Initials',style:''},...avatarOptions.filter(a=>!style||a.style===style)],fullName=name??r.data.name;
 async function save(data:{name?:string;avatarId?:string},message:string){
  if(busy)return;setBusy(true);setError('');setSaved('');
  try{const updated=await api('me/profile',{method:'PATCH',body:JSON.stringify({...data,expectedRevision:r.data.revision})});r.setData({...r.data,...updated});if(data.name!==undefined)setName(null);setSaved(message);router.refresh();}
  catch(e){setError((e as Error).message);}finally{setBusy(false);}
 }
 function saveName(event:FormEvent<HTMLFormElement>){event.preventDefault();void save({name:fullName},'Your name is saved. Your colleagues will see it in the directory and on your profile.');}
 return <><PageHead eyebrow="MAKE IT YOURS" title="Your profile" description={`Edit your display name and choose from ${avatarOptions.length} avatars across ${avatarStyles.length} styles.`} actions={<Link className="button secondary" href="/organisation"><GitBranch size={16}/>Explore organisation</Link>}/>
  <section className="panel profile-panel"><div className="account-profile"><Avatar person={{...r.data,avatarId:id}} size={76}/><div><h2>{r.data.name}</h2><p>{r.data.email}</p></div></div>
   <form className={s.form} onSubmit={saveName}><label>Full name<input name="displayName" required minLength={1} maxLength={100} value={fullName} autoComplete="name" disabled={busy} onChange={e=>{setName(e.target.value);setSaved('');}}/><small>This is the name colleagues see across the organisation. Your sign-in email, department and squad are managed by an administrator.</small></label><div className={s.actions}><button type="submit" className="button primary" disabled={busy||!fullName.trim()||fullName.trim()===r.data.name}><Save size={15}/>{busy?'Saving…':'Save name'}</button><Link className="text-link" href={`/people/${r.data.id}`}>View your organisation profile</Link></div></form>
   <ErrorBanner message={error||r.error} retry={r.reload}/>{saved&&<p role="status" className="success-banner">{saved}</p>}
   <fieldset className="avatar-fieldset"><legend>Choose your style</legend><div className="avatar-style-filters" role="group" aria-label="Avatar styles"><button type="button" aria-pressed={!style} onClick={()=>setStyle('')}>All styles · {avatarOptions.length}</button>{avatarStyles.map(s=><button type="button" key={s.id} aria-pressed={style===s.id} onClick={()=>setStyle(s.id)}>{s.label} · {s.count}</button>)}</div><div className="avatar-grid" role="group" aria-label="Profile avatar choices">{options.map(value=><label key={value.id} className={`avatar-choice ${id===value.id?'selected':''}`}><input type="radio" name="avatar" aria-label={value.label} checked={id===value.id} disabled={busy} onChange={()=>{setChoice(value.id);setSaved('');}}/><Avatar person={{name:r.data.name,avatarId:value.id}} size={60}/></label>)}</div></fieldset>
   <div className="avatar-save-bar"><div><strong>Your avatar</strong><small>{id===r.data.avatarId?'Current profile avatar':'Preview · save to apply'}</small></div><button className="button primary" disabled={busy} onClick={()=>save({avatarId:id},'Your profile avatar is saved.')}>{busy?'Saving…':'Save avatar'}</button></div>
  </section></>;
}
