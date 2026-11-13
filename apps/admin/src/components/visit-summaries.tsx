'use client';
import Link from 'next/link';
import {useParams} from 'next/navigation';
import {ArrowLeft,ArrowUpRight,Download} from 'lucide-react';
import {visitSummaryLabels} from '../../../../packages/contracts/src/visit-summary';
import {formatTime,useResource} from '@/lib/api';
import {PageHead,ErrorBanner,Loading,Empty,Badge} from './ui';

export function VisitSummaries(){
  const res=useResource('admin/visit-summaries?limit=100',5000);
  return <>
    <div className="panel-heading"><div><h2>Visit summaries</h2><p>Visit summaries reviewed and submitted by engineers. Updated automatically.</p></div></div>
    <ErrorBanner message={res.error} retry={res.reload}/>
    <section className="panel">{res.loading?<Loading/>:!res.data?.items.length?<Empty title="No visit summaries submitted yet" detail="In the phone app, review your answers and press Submit visit summary."/>:
      <div className="table-scroll"><table><thead><tr><th>VISIT</th><th>ENGINEER</th><th>WORK DONE</th><th>RECEIVED</th><th>STATUS</th><th/></tr></thead><tbody>
      {res.data.items.map((r:any)=><tr key={r.id}><td><Link className="report-id" href={`/submissions/visit-summaries/${r.id}`}>{r.workOrder?.title??`Visit ${r.clientReportId.slice(0,8)}`}</Link><small className="block muted">{r.workOrder?.site}</small></td><td>{r.engineer.name}</td><td style={{maxWidth:380}}>{r.values.actual_work.slice(0,160)}</td><td>{formatTime(r.receivedAt)}</td><td><Badge tone="success">Summary received</Badge><small className="block muted">Operational closure pending</small></td><td><Link className="icon-button" aria-label="View visit summary" href={`/submissions/visit-summaries/${r.id}`}><ArrowUpRight size={17}/></Link></td></tr>)}
      </tbody></table></div>}</section>
  </>;
}
export function VisitSummaryDetail(){
  const {id}=useParams<{id:string}>(),res=useResource(`admin/visit-summaries/${id}`);
  if(res.loading)return <Loading/>;
  if(res.error)return <ErrorBanner message={res.error} retry={res.reload}/>;
  const r=res.data;if(!r)return null;
  return <>
    <Link className="editor-back" href="/submissions?view=visits"><ArrowLeft size={16}/>All visit summaries</Link>
    <PageHead title={r.workOrder?.title??'Visit summary'} description={`${r.engineer.name} · ${r.workOrder?.site??'Visit summary'}`} actions={<><Badge tone="success">Summary received</Badge><button className="button secondary" onClick={()=>{const url=URL.createObjectURL(new Blob([JSON.stringify(r,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download=`visit-summary-${r.id}.json`;a.click();URL.revokeObjectURL(url);}}><Download size={16}/>Export JSON</button></>}/>
    <div className="detail-layout"><section className="panel report-values">
    {Object.entries(visitSummaryLabels).filter(([id])=>['actual_work','claimed_outcome','optical_rx_dbm','operational_test','next_action'].includes(id)||Object.hasOwn(r.values,id)).map(([id,label])=><div key={id} className="report-value"><span>{label}</span><div><strong>{r.values[id]==null?'Not recorded':typeof r.values[id]==='boolean'?(r.values[id]?'Yes':'No'):String(r.values[id]).replaceAll('_',' ')}</strong>{r.sources[id]?.sourceSpan&&<details><summary>Engineer source · {r.sources[id].sourceType}</summary><p style={{whiteSpace:'pre-wrap'}}>{r.sources[id].sourceSpan}</p></details>}</div></div>)}
    </section><aside><section className="panel" style={{padding:24}}><h3>Submission receipt</h3><code>{r.id}</code><dl><dt>Engineer reviewed</dt><dd>{formatTime(r.confirmedAt)}</dd><dt>Received</dt><dd>{formatTime(r.receivedAt)}</dd></dl><p>Visit summary received. Full operational closure checks remain separate; this submission does not close the work order.</p><small>Synthetic demonstration workflow</small></section></aside></div>
  </>;
}
