import {isVisible,isMissing} from './field-values';
import { z } from 'zod';
import { canonicalize } from 'json-canonicalize';
import { createHash } from 'node:crypto';

export const fieldTypes = ['short_text','long_text','integer','decimal','quantity','boolean','single_select','date'] as const;
export const cableScanTargets = ['cable_id','drum_id','manufacturer','batch','specification','fibre_count','declared_length','manufactured_date'] as const;
const id = z.string().min(1).max(100).regex(/^[a-zA-Z0-9_-]+$/);
const condition = z.discriminatedUnion('operator', [
  z.object({fieldId:id,operator:z.literal('equals'),value:z.union([z.boolean(),z.string(),z.number()])}).strict(),
  z.object({fieldId:id,operator:z.literal('in'),value:z.array(z.string()).min(1).max(20)}).strict(),
]);
export const fieldSchema = z.object({
  id, sectionId:id, order:z.number().int().min(0), type:z.enum(fieldTypes),
  label:z.string().trim().min(1).max(120), required:z.boolean(),
  constraints:z.object({min:z.number().optional(),max:z.number().optional(),precision:z.number().int().min(0).max(6).optional(),maxLength:z.number().int().min(1).max(5000).optional(),minDate:z.iso.date().optional(),maxDate:z.iso.date().optional()}).strict().optional(),
  options:z.array(z.object({id,label:z.string().trim().min(1).max(100)}).strict()).max(20).optional(),
  units:z.object({allowed:z.array(z.string().min(1)).min(1).max(10),canonical:z.string().min(1)}).strict().optional(),
  condition:condition.optional(),
  scan:z.object({kind:z.literal('cable_label'),target:z.enum(cableScanTargets)}).strict().optional(),
  voice:z.object({enabled:z.boolean(),description:z.string().max(500),question:z.string().max(300),synonyms:z.array(z.string().max(100)).max(20)}).strict(),
}).strict();
export const templateSchema = z.object({
  schemaFormatVersion:z.literal(1),templateId:z.uuid(),engineerTypeId:z.uuid(),title:z.string().trim().min(1).max(120),
  sections:z.array(z.object({id,label:z.string().trim().min(1).max(100),order:z.number().int().min(0)}).strict()).min(1).max(6),
  fields:z.array(fieldSchema).max(30),
}).strict().superRefine((schema,ctx)=>{
  const fail=(message:string,path:(string|number)[]=[])=>ctx.addIssue({code:'custom',message,path});
  const ids=new Set(schema.fields.map(f=>f.id));
  if(ids.size!==schema.fields.length)fail('Field IDs must be unique.');
  if(new Set(schema.sections.map(s=>s.id)).size!==schema.sections.length)fail('Section IDs must be unique.');
  const scanTargets=new Set<string>();
  for(const [i,f] of schema.fields.entries()){
    const at=['fields',i];
    if(f.scan){
      if(scanTargets.has(f.scan.target))fail('Use each cable scan target only once.',at);scanTargets.add(f.scan.target);
      const expected=f.scan.target==='fibre_count'?'integer':f.scan.target==='declared_length'?'quantity':f.scan.target==='manufactured_date'?'date':'short_text';
      if(f.type!==expected)fail(`This scan target requires a ${expected} field.`,at);
      if(f.scan.target==='declared_length'&&(!f.units||f.units.allowed.some(u=>!['m','km'].includes(u))))fail('Printed cable length supports metres or kilometres.',at);
    }
    if(!schema.sections.some(s=>s.id===f.sectionId))fail('Select an existing section.',at);
    if(f.type==='single_select'&&(!f.options?.length||new Set(f.options.map(o=>o.id)).size!==f.options.length))fail('Select fields need unique options.',at);
    if(f.type==='quantity'&&(!f.units||!f.units.allowed.includes(f.units.canonical)))fail('Quantity fields need a canonical allowed unit.',at);
    if(f.voice.enabled&&(!f.voice.question.trim()||!f.voice.description.trim()))fail('Voice fields need a question and description.',at);
    if(f.constraints?.min!==undefined&&f.constraints.max!==undefined&&f.constraints.min>f.constraints.max)fail('Minimum exceeds maximum.',at);
    if(f.condition){
      const parent=schema.fields.find(p=>p.id===f.condition!.fieldId);
      if(!parent||parent.id===f.id)fail('Condition references an unknown field or itself.',at);
      else if(f.condition.operator==='in'&&(parent.type!=='single_select'||!f.condition.value.every(v=>parent.options?.some(o=>o.id===v))))fail('Membership conditions need allowed select option IDs.',at);
      else if(f.condition.operator==='equals'){
        const val=f.condition.value;
        if(parent.type==='boolean'?typeof val!=='boolean':parent.type==='single_select'?!parent.options?.some(o=>o.id===val):true)fail('Equality conditions require a boolean or allowed select option.',at);
      }
      let current:Field|undefined=f;const visited=new Set<string>();
      while(current?.condition){if(visited.has(current.id)){fail('Visibility conditions cannot form a cycle.',at);break;}visited.add(current.id);current=schema.fields.find(p=>p.id===current!.condition!.fieldId);}
    }
  }
});
export type Field=z.infer<typeof fieldSchema>;
export type TemplateSchema=z.infer<typeof templateSchema>;
export type Value=string|number|boolean|{amount:number;unit:string}|null;
export type Values=Record<string,Value>;
export type FieldError={fieldId:string;code:string;message:string};
export {isVisible,isMissing} from './field-values';
export function validateValues(schema:TemplateSchema,values:Values,required=true){
  const errors:FieldError[]=[];const included:Values={};const excluded:string[]=[];
  for(const key of Object.keys(values))if(!schema.fields.some(f=>f.id===key))errors.push({fieldId:key,code:'UNKNOWN_FIELD',message:'Unknown field.'});
  for(const f of schema.fields){
    if(!isVisible(f,values,schema.fields)){if(!isMissing(values[f.id]))excluded.push(f.id);continue;}
    let v=values[f.id];const err=(code:string,message:string)=>errors.push({fieldId:f.id,code,message});
    if(isMissing(v)){if(required&&f.required)err('REQUIRED',`${f.label} is required.`);continue;}
    if(typeof v==='string')v=v.trim();
    let numeric:number|undefined;
    switch(f.type){
      case 'short_text':case 'long_text':
        if(typeof v!=='string')err('INVALID_TYPE','Enter text.');
        else if(v.length>(f.constraints?.maxLength??(f.type==='short_text'?160:500)))err('TOO_LONG','Text exceeds the maximum length.');break;
      case 'integer':case 'decimal':
        if(typeof v!=='number'||!Number.isFinite(v)||f.type==='integer'&&!Number.isInteger(v))err('INVALID_TYPE','Enter a valid number.');else numeric=v;break;
      case 'quantity':
        if(!v||typeof v!=='object'||Array.isArray(v)||typeof v.amount!=='number'||!Number.isFinite(v.amount)||typeof v.unit!=='string'||Object.keys(v).some(k=>!['amount','unit'].includes(k)))err('INVALID_TYPE','Enter an amount and unit.');
        else if(!f.units?.allowed.includes(v.unit))err('UNSUPPORTED_UNIT','Select an allowed unit.');else numeric=v.amount;break;
      case 'boolean':if(typeof v!=='boolean')err('INVALID_TYPE','Choose yes or no.');break;
      case 'single_select':if(typeof v!=='string'||!f.options?.some(o=>o.id===v))err('INVALID_OPTION','Choose an allowed option.');break;
      case 'date':
        if(typeof v!=='string'||!z.iso.date().safeParse(v).success)err('INVALID_DATE','Use a valid YYYY-MM-DD date.');
        else if(f.constraints?.minDate&&v<f.constraints.minDate||f.constraints?.maxDate&&v>f.constraints.maxDate)err('OUT_OF_RANGE','Date is outside the allowed range.');break;
    }
    if(numeric!==undefined){
      if(f.constraints?.min!==undefined&&numeric<f.constraints.min||f.constraints?.max!==undefined&&numeric>f.constraints.max)err('OUT_OF_RANGE','Number is outside the allowed range.');
      if(f.constraints?.precision!==undefined&&Math.abs(numeric*10**f.constraints.precision-Math.round(numeric*10**f.constraints.precision))>1e-7)err('INVALID_PRECISION',`Use at most ${f.constraints.precision} decimal places.`);
    }
    included[f.id]=v;
  }
  return {valid:errors.length===0,errors,values:included,excluded};
}
export function convertQuantity(value:{amount:number;unit:string},canonical:string){
  if(value.unit===canonical)return value;
  const factors:Record<string,number>={'Gbps:Mbps':1000,'Mbps:Gbps':0.001};
  const factor=factors[`${value.unit}:${canonical}`];
  if(!factor)throw new Error('UNSUPPORTED_UNIT');return {amount:value.amount*factor,unit:canonical};
}
export function schemaBytes(s:TemplateSchema){return canonicalize({schemaFormatVersion:s.schemaFormatVersion,templateId:s.templateId,engineerTypeId:s.engineerTypeId,title:s.title,sections:s.sections,fields:s.fields});}
export function sha256(bytes:string|Buffer){return createHash('sha256').update(bytes).digest('hex');}
export function schemaHash(s:TemplateSchema){return sha256(schemaBytes(s));}
export const reportLocationSchema=z.object({
  latitude:z.number().finite().min(-90).max(90),
  longitude:z.number().finite().min(-180).max(180),
  accuracyMeters:z.number().finite().min(0).max(100000),
  capturedAt:z.iso.datetime(),
  isMocked:z.boolean(),
}).strict();
export type ReportLocation=z.infer<typeof reportLocationSchema>;
export const frozenReportSchema=z.object({
  clientReportId:z.uuid(),submissionAttemptId:z.uuid(),revision:z.number().int().min(1),templateId:z.uuid(),versionId:z.uuid(),schemaHash:z.string().regex(/^[a-f0-9]{64}$/),
  entitlementId:z.uuid(),values:z.record(z.string(),z.unknown()),confirmedAt:z.iso.datetime(),originatingTimezone:z.string().min(1).max(100),
  // Older installed apps and already frozen queues have no location metadata.
  location:reportLocationSchema.optional(),
  workOrderId:z.uuid().optional(),
  workOrderAssignmentRevision:z.number().int().min(1).optional(),
}).strict().superRefine((report,ctx)=>{
  if(!report.location)return;
  const age=Date.parse(report.confirmedAt)-Date.parse(report.location.capturedAt);
  if(age < -30000 || age > 120000)ctx.addIssue({code:'custom',path:['location','capturedAt'],message:'Capture a fresh location when confirming the report.'});
});
export const reportStates=['draft','queued','syncing','accepted','needs_attention'] as const;
export type ReportState=typeof reportStates[number];
export function transition(state:ReportState,event:'confirm'|'upload'|'receipt'|'transient'|'rejected'|'retry'|'fenced_reopen'):ReportState{
  const table:Record<string,ReportState>={'draft:confirm':'queued','queued:upload':'syncing','syncing:receipt':'accepted','syncing:transient':'queued','syncing:rejected':'needs_attention','needs_attention:retry':'queued','needs_attention:fenced_reopen':'draft','queued:fenced_reopen':'draft'};
  const next=table[`${state}:${event}`];if(!next)throw new Error('INVALID_TRANSITION');return next;
}
export * from './operations';
export * from './access';
export * from './accounts';

export * from './collaboration';

export * from './workspace';

export * from './ai';
