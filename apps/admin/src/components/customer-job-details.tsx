'use client';
import {useState,type FormEvent} from 'react';
import {api} from '@/lib/api';
import {ErrorBanner} from './ui';
import {customerTime,customerVisitWindow} from '../../../../packages/contracts/src/customer-jobs';
import s from './customer-job-details.module.css';

type Details={customerEmail:string;appointmentStartAt:string|null;appointmentEndAt:string|null;appointmentTimezone:string;
  activationStatus:string;activationAt:string|null;activationNote:string;revision:number};
const local=(v:string|null|undefined)=>v?new Date(new Date(v).getTime()-new Date(v).getTimezoneOffset()*60000).toISOString().slice(0,16):'';
export function CustomerJobDetails({jobId,initial,canEdit,onSaved}:{jobId:string;initial:Details|null;canEdit:boolean;onSaved():void}) {
  const [editing,setEditing]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState('');
  const [activation,setActivation]=useState(initial?.activationStatus??'not_confirmed');
  async function save(e:FormEvent<HTMLFormElement>) {
    e.preventDefault();if(busy)return;setBusy(true);setError('');
    const form=new FormData(e.currentTarget);
    const instant=(key:string)=>form.get(key)?new Date(String(form.get(key))).toISOString():null;
    try {
      await api(`admin/work-orders/${jobId}/customer-status`,{method:'PUT',body:JSON.stringify({
        expectedRevision:initial?.revision??0,customerEmail:form.get('customerEmail'),
        appointmentStartAt:instant('appointmentStartAt'),appointmentEndAt:instant('appointmentEndAt'),
        appointmentTimezone:form.get('appointmentTimezone'),activationStatus:activation,
        activationAt:['scheduled','active'].includes(activation)?instant('activationAt'):null,activationNote:form.get('activationNote'),
      })});
      setEditing(false);onSaved();
    } catch(e){setError((e as Error).message);} finally{setBusy(false);}
  }
  return <section className={s.panel}><h3>Customer updates for Chatm</h3>
    <p className="body-copy">Link this job to the customer’s verified email. Record confirmed appointment and provider activation details here.</p>
    {!editing?<><dl className="job-brief-grid">
      <div><dt>Customer email</dt><dd>{initial?.customerEmail??'Not linked'}</dd></div>
      <div><dt>Confirmed visit</dt><dd>{initial?.appointmentStartAt?customerVisitWindow(initial.appointmentStartAt,initial.appointmentEndAt,initial.appointmentTimezone):'Not confirmed'}</dd></div>
      <div><dt>Broadband activation</dt><dd>{initial?.activationStatus.replaceAll('_',' ')??'Not confirmed'}{initial?.activationAt?' · '+customerTime(initial.activationAt,initial.appointmentTimezone)+` (${initial.appointmentTimezone})`:''}</dd></div>
    </dl>{initial?.activationNote&&<p className="body-copy">{initial.activationNote}</p>}
    {canEdit&&<button className="button secondary" onClick={()=>{setActivation(initial?.activationStatus??'not_confirmed');setEditing(true);}}>Edit customer updates</button>}</>:
    <form onSubmit={save} className={s.form}>
      <label>Customer email<input name="customerEmail" type="email" required defaultValue={initial?.customerEmail??''} maxLength={254}/></label>
      <label>Confirmed visit starts<input name="appointmentStartAt" type="datetime-local" defaultValue={local(initial?.appointmentStartAt)}/></label>
      <label>Visit window ends<input name="appointmentEndAt" type="datetime-local" defaultValue={local(initial?.appointmentEndAt)}/></label>
      <label>Site time zone<input name="appointmentTimezone" defaultValue={initial?.appointmentTimezone??'Europe/London'} required/></label>
      <p className={`${s.wide} ${s.hint}`}>Enter dates in this browser’s time zone ({Intl.DateTimeFormat().resolvedOptions().timeZone}). Chatm presents the saved visit in the site time zone. A job’s due date is not a confirmed appointment.</p>
      <label>Provider-confirmed broadband status<select value={activation} onChange={e=>setActivation(e.target.value)}><option value="not_confirmed">Not confirmed</option><option value="scheduled">Scheduled</option><option value="active">Active</option><option value="blocked">Blocked</option></select></label>
      {['scheduled','active'].includes(activation)&&<label>Provider-confirmed activation time<input name="activationAt" type="datetime-local" required={activation==='scheduled'} defaultValue={local(initial?.activationAt)}/></label>}
      <label className={s.wide}>Customer-facing activation update<textarea name="activationNote" maxLength={1500} defaultValue={initial?.activationNote??''}/></label>
      {error&&<div className={s.wide}><ErrorBanner message={error}/></div>}<div className={`${s.wide} ${s.actions}`}><button className="button primary" disabled={busy}>{busy?'Saving…':'Save customer updates'}</button> <button type="button" className="button secondary" disabled={busy} onClick={()=>setEditing(false)}>Cancel</button></div>
    </form>}
  </section>;
}
