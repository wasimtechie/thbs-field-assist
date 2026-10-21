import {describe,it,expect} from 'vitest';
import {readFileSync} from 'node:fs';
import {templateSchema,validateValues,schemaHash,schemaBytes,transition,convertQuantity,type TemplateSchema,type Values} from './index';
import {canonicalize} from 'json-canonicalize';
const load=(name:string)=>templateSchema.parse(JSON.parse(readFileSync(`fixtures/templates/${name}.json`,'utf8')));
describe('published schema semantics',()=>{
 for(const name of ['fibre','repair','business','survey'])it(`accepts the ${name} fixture`,()=>expect(load(name).fields.length).toBeGreaterThan(0));
 it('preserves false and numeric zero',()=>{const s=load('survey');const r=validateValues(s,{access_available:false,survey_outcome:'feasible',power_available:false,follow_up:false,estimated_route:{amount:0,unit:'m'}});expect(r.valid).toBe(true);expect(r.values.power_available).toBe(false);});
 it.each(['partial','unable'])('requires membership-dependent reason for %s',outcome=>{const r=validateValues(load('fibre'),{installation_outcome:outcome});expect(r.errors.some(e=>e.fieldId==='exception_reason'&&e.code==='REQUIRED')).toBe(true);expect(r.errors.some(e=>e.fieldId==='ont_serial')).toBe(false);});
 it('hides and omits old values without destroying draft input',()=>{const values:Values={installation_outcome:'partial',ont_serial:'retained draft value'};const r=validateValues(load('fibre'),values,false);expect(r.values.ont_serial).toBeUndefined();expect(r.excluded).toEqual(['ont_serial']);expect(values.ont_serial).toBe('retained draft value');});
 it('requires equals-dependent fields',()=>expect(validateValues(load('repair'),{follow_up:true}).errors.some(e=>e.fieldId==='follow_up_details')).toBe(true));
 it('does not require a hidden field',()=>expect(validateValues(load('repair'),{follow_up:false}).errors.some(e=>e.fieldId==='follow_up_details')).toBe(false));
 it('rejects labels at the enum boundary',()=>expect(validateValues(load('repair'),{line_test:'Passed'},false).errors[0].code).toBe('INVALID_OPTION'));
 it.each([{amount:-1,unit:'m'},{amount:12,unit:'ft'},{amount:1.234,unit:'m'}])('validates quantities %j',v=>expect(validateValues(load('repair'),{cable_replaced:v},false).valid).toBe(false));
 it('rejects unknown field IDs',()=>expect(validateValues(load('repair'),{admin_role:'ADMIN'},false).errors[0].code).toBe('UNKNOWN_FIELD'));
 it('rejects cyclic dependencies',()=>{const s=structuredClone(load('repair'));s.fields.find(f=>f.id==='service_restored')!.condition={fieldId:'follow_up',operator:'equals',value:true};s.fields.find(f=>f.id==='follow_up')!.condition={fieldId:'service_restored',operator:'equals',value:true};expect(templateSchema.safeParse(s).success).toBe(false);});
 it('rejects unsupported structures',()=>{const s:any=structuredClone(load('repair'));s.fields[0].script='eval()';expect(templateSchema.safeParse(s).success).toBe(false);});
 it('field IDs are unique',()=>{const s=structuredClone(load('repair'));s.fields[1].id=s.fields[0].id;expect(templateSchema.safeParse(s).success).toBe(false);});
 it('hash excludes transport metadata, preserves array order',()=>{const s=load('fibre');expect(schemaHash({...s,versionId:'transport'} as TemplateSchema)).toBe(schemaHash(s));expect(schemaHash({...s,fields:[...s.fields].reverse()})).not.toBe(schemaHash(s));});
 it('has canonical key ordering',()=>expect(schemaBytes(load('repair')).startsWith('{"engineerTypeId":')).toBe(true));
 it('uses allowlisted unit conversion',()=>{expect(convertQuantity({amount:2,unit:'Gbps'},'Mbps')).toEqual({amount:2000,unit:'Mbps'});expect(()=>convertQuantity({amount:2,unit:'ft'},'m')).toThrow('UNSUPPORTED_UNIT');});
 it('accepted reports cannot transition to draft',()=>expect(()=>transition('accepted','fenced_reopen')).toThrow('INVALID_TRANSITION'));
 it('uncertain upload returns to queued',()=>expect(transition('syncing','transient')).toBe('queued'));
 it('cannot reopen without a fence event',()=>expect(()=>transition('queued','confirm')).toThrow());
});
describe('shared Dart and TypeScript fixtures',()=>{
 const fixture=JSON.parse(readFileSync('fixtures/contracts.json','utf8'));
 for(const [name,raw] of Object.entries(fixture.templates)){const t=raw as any;it(`canonical fixture: ${name}`,()=>{expect(schemaBytes(t.schema)).toBe(t.canonicalBytes);expect(schemaHash(t.schema)).toBe(t.schemaHash);});}
 for(const c of fixture.cases)it(`shared outcome: ${c.name}`,()=>{const r=validateValues(fixture.templates[c.template].schema,c.values);expect({valid:r.valid,errors:r.errors.map(e=>({fieldId:e.fieldId,code:e.code})),values:r.values,excluded:r.excluded}).toEqual(c.expected);});
 for(const v of JSON.parse(readFileSync('fixtures/canonical-vectors.json','utf8')))it(`RFC 8785 ${v.expected}`,()=>expect(canonicalize(v.value)).toBe(v.expected));
});
