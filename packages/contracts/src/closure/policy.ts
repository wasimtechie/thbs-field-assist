import {z} from 'zod';
export type Expression={field:string;op:'eq'|'neq'|'in'|'present'|'missing';value?:string|number|boolean|string[]}|{all:Expression[]}|{any:Expression[]};
const atom=z.object({field:z.string().regex(/^[a-zA-Z0-9_-]{1,100}$/),op:z.enum(['eq','neq','in','present','missing']),value:z.union([z.string(),z.number().finite(),z.boolean(),z.array(z.string()).max(20)]).optional()}).strict();
export const expressionSchema:z.ZodType<Expression>=z.lazy(()=>z.union([atom,z.object({all:z.array(expressionSchema).min(1).max(20)}).strict(),z.object({any:z.array(expressionSchema).min(1).max(20)}).strict()]));
export function matches(expression:Expression,values:Record<string,unknown>):boolean{
 if('all'in expression)return expression.all.every(e=>matches(e,values));
 if('any'in expression)return expression.any.some(e=>matches(e,values));
 const v=values[expression.field];
 if(expression.op==='missing')return v===undefined||v===null||v==='';
 if(expression.op==='present')return v!==undefined&&v!==null&&v!=='';
 if(v===undefined||v===null||v==='')return false;
 return expression.op==='eq'?v===expression.value:expression.op==='neq'?v!==expression.value:Array.isArray(expression.value)&&expression.value.includes(String(v));
}
export function dependencies(e:Expression):string[]{return 'field'in e?[e.field]:('all'in e?e.all:e.any).flatMap(dependencies);}
export const closurePolicySchema=z.object({
 id:z.literal('fttp-closure-mvp'),version:z.number().int().min(1).max(100),
 banks:z.array(z.object({id:z.enum(['S1','S2','S3','S4','S5']),version:z.literal(1),title:z.string(),questions:z.array(z.object({questionId:z.string(),fieldId:z.string(),question:z.string(),sourceShowWhen:z.string(),status:z.string()})).length(25)})).length(5),
 rules:z.array(z.object({id:z.string(),when:expressionSchema,assert:expressionSchema,message:z.string(),code:z.string()})).max(100),
 dispositions:z.array(z.object({when:expressionSchema,outcome:z.enum(['hold','blocked','referred','partial','stage_completed','network_ready','completed'])})).max(30),
 holdRequired:z.array(z.string()).max(20),
}).strict();
export type ClosurePolicy=z.infer<typeof closurePolicySchema>;
export const CLOSURE_TEMPLATE_ID='40000000-0000-4000-8000-000000000006';
export function closureRequired(field:{id:string;required:boolean},values:Record<string,unknown>,policy?:ClosurePolicy){return field.required&&(!policy||values.claimed_outcome!=='hold'||policy.holdRequired.includes(field.id));}
export function closureChecks(schema:{closurePolicy?:ClosurePolicy;fields:{id:string;label:string;required:boolean;activation?:Expression;capture?:'evidence';evidenceStage?:string}[]},values:Record<string,unknown>,photos:{stage:string}[]){
 const p=schema.closurePolicy;if(!p)return {issues:[] as string[],recommendation:'incomplete',serviceLive:false};
 const byId=new Map(schema.fields.map(f=>[f.id,f]));
 const visible=(id:string,seen=new Set<string>()):boolean=>{
  if(seen.has(id))return false;const f=byId.get(id);if(!f?.activation)return true;
  const test=(e:Expression):boolean=>'all'in e?e.all.every(test):'any'in e?e.any.some(test):(!byId.has(e.field)||visible(e.field,new Set([...seen,id])))&&matches(e,values);
  return test(f.activation);
 };
 const active=schema.fields.filter(f=>visible(f.id));
 values=Object.fromEntries(active.filter(f=>f.id in values).map(f=>[f.id,values[f.id]]));
 const issues:string[]=[];
 if(values.claimed_outcome!=='hold'&&photos.length===0)issues.push('Attach work-order evidence or record an explicit hold.');
 for(const f of active){if(closureRequired(f,values,p)&&(values[f.id]===null||values[f.id]===undefined||values[f.id]===''))issues.push(`${f.label} is required.`);if(closureRequired(f,values,p)&&f.capture==='evidence'&&(values[f.id]!==true||!photos.some(e=>e.stage===f.evidenceStage)))issues.push(`Attach ${f.label.toLowerCase()}.`);}
 for(const r of p.rules)if(matches(r.when,values)&&!matches(r.assert,values))issues.push(r.message);
 const recommendation=p.dispositions.find(d=>matches(d.when,values))?.outcome??'incomplete';
 if(values.claimed_outcome==='completed'&&recommendation!=='completed')issues.push('This visit is not eligible for completed provision. Resolve the branch or select an honest hold, partial or referral outcome.');
 if(values.claimed_outcome==='stage_completed'&&!['stage_completed','network_ready'].includes(recommendation))issues.push('This build stage has not met its acceptance checks.');
 if(values.claimed_outcome==='network_ready'&&recommendation!=='network_ready')issues.push('Network readiness has not been established.');
 return {issues:[...new Set(issues)],recommendation,serviceLive:values.work_stage==='final_provision'&&values.claimed_outcome==='completed'&&recommendation==='completed'&&values.service_live===true&&issues.length===0};
}
