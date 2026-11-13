import {describe,it,expect} from 'vitest';
import {visitSummarySchema} from './visit-summary';
import {randomUUID} from 'node:crypto';
const payload=()=>({clientSummaryId:randomUUID(),clientReportId:randomUUID(),workOrderId:null,confirmedAt:new Date().toISOString(),values:{actual_work:'Installed ONT',claimed_outcome:'completed'},sources:{}});
describe('visit summary contract',()=>{
 it('accepts all five summary answers without an asset reference and keeps legacy payload compatibility',()=>{
  const p={...payload(),values:{actual_work:'Installed ONT',claimed_outcome:'completed',optical_rx_dbm:-18.2,operational_test:'passed',next_action:'No further work required'}};
  const parsed=visitSummarySchema.parse(p);
  expect(Object.keys(parsed.values)).toHaveLength(5);
  expect(parsed.values.serving_asset).toBeUndefined();
  expect(visitSummarySchema.safeParse({...p,values:{...p.values,serving_asset:'CBT-SYN-10'}}).success).toBe(true);
 });
 it('retains edited-transcript provenance in a submitted five-field summary',()=>{
  const source={sourceType:'text',sourceSpan:'The service test failed.',inputMethod:'transcript_edit',
   originalSpeech:{sourceType:'speech',sourceSpan:'The service test past.'},
   previousTranscript:'The service test past.',editedAt:new Date().toISOString()};
  const result=visitSummarySchema.parse({...payload(),sources:{operational_test:source}});
  expect(result.sources.operational_test).toEqual(source);
  expect(visitSummarySchema.safeParse({...payload(),sources:{operational_test:{...source,originalSpeech:{...source.originalSpeech,approvedByAI:true}}}}).success).toBe(false);
 });
 it('accepts partial optional fields without approving operational closure',()=>{expect(visitSummarySchema.safeParse(payload()).success).toBe(true);expect(visitSummarySchema.safeParse({...payload(),operationalClosureApproved:true}).success).toBe(false);});
 it('requires a follow-up for incomplete work',()=>{const p=payload();expect(visitSummarySchema.safeParse({...p,values:{...p.values,claimed_outcome:'blocked'}}).success).toBe(false);expect(visitSummarySchema.safeParse({...p,values:{...p.values,claimed_outcome:'blocked',next_action:'Civils referral'}}).success).toBe(true);});
 it('rejects invented extra fields and nonfinite readings',()=>{for(const values of [{assumed_approved:true},{optical_rx_dbm:Infinity},{operational_test:'assumed_passed'}])expect(visitSummarySchema.safeParse({...payload(),values:{...payload().values,...values}}).success).toBe(false);});
 it('accepts the fifteen-field S1 summary, preserves no answers and checks types',()=>{
  const values={actual_work:'Installed ONT',claimed_outcome:'completed',access_permission:true,
   location_agreed:true,drop_route:'existing',external_connection:true,internal_fibre:true,
   ont_fitted:true,ont_status_checked:true,optical_rx_dbm:-18.2,operational_test:'passed',
   service_live:false,customer_handover:false,site_handover_safe:true,next_action:'Provider activation required'};
  const parsed=visitSummarySchema.parse({...payload(),values,sources:{access_permission:{sourceType:'speech',sourceSpan:'The customer granted access.'}}});
  expect(Object.keys(parsed.values)).toHaveLength(15);
  expect(parsed.values.service_live).toBe(false);
  expect(parsed.values.customer_handover).toBe(false);
  for(const change of [{access_permission:'yes'},{drop_route:'assumed'},{ont_fitted:1}])
   expect(visitSummarySchema.safeParse({...payload(),values:{...values,...change}}).success).toBe(false);
 });
 it('preserves the original speech, corrected interpretation and bounded repair trace',()=>{
  const raw='The optical reading was 18.2 dBm, no no sorry the reading was -18.19 dBm.';
  const source={sourceType:'speech',sourceSpan:raw,rawTranscript:raw,interpretedSpan:'The reading was -18.19 dBm.',
   derivedFrom:'actual_work',derivedSummary:raw,requiresConfirmation:false,
   speechRepairs:[{discarded:'18.2 dBm',cue:'no no sorry',replacement:'-18.19 dBm'}]};
  const p={...payload(),sources:{optical_rx_dbm:source}};
  const result=visitSummarySchema.parse(p);
  expect(result.sources.optical_rx_dbm).toEqual(source);
  expect(visitSummarySchema.safeParse({...p,sources:{optical_rx_dbm:{...source,rawTranscript:'x'.repeat(8001)}}}).success).toBe(false);
  expect(visitSummarySchema.safeParse({...p,sources:{optical_rx_dbm:{...source,approvedByAI:true}}}).success).toBe(false);
 });
});
