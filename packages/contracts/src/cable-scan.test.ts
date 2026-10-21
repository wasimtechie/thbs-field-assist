import {describe,it,expect} from 'vitest';
import {readFileSync} from 'node:fs';
import {templateSchema,schemaHash,validateValues} from './index';
const schema=JSON.parse(readFileSync('fixtures/templates/fibre-cable-label.json','utf8'));
describe('schema-driven cable label capture',()=>{
 it('accepts all eight optional, typed mappings',()=>{
  const parsed=templateSchema.parse(schema);
  expect(parsed.fields.filter(f=>f.scan)).toHaveLength(8);
  expect(parsed.fields.filter(f=>f.scan).every(f=>!f.required&&!f.voice.enabled)).toBe(true);
 });
 it('preserves legacy schemas without scan configuration',()=>{
  expect(templateSchema.safeParse(JSON.parse(readFileSync('fixtures/templates/fibre.json','utf8'))).success).toBe(true);
 });
 it('rejects duplicate mapping and the wrong field type',()=>{
  for(const mutation of [(s:any)=>s.fields[1].scan.target='cable_id',(s:any)=>s.fields[0].scan.target='fibre_count']){
   const copy=structuredClone(schema);mutation(copy);expect(templateSchema.safeParse(copy).success).toBe(false);
  }
 });
 it('rejects incompatible printed length units',()=>{
  const copy=structuredClone(schema);copy.fields.find((f:any)=>f.scan?.target==='declared_length').units.allowed=['ft'];
  expect(templateSchema.safeParse(copy).success).toBe(false);
 });
 it('includes field camera mapping in the immutable schema hash',()=>{
  const copy=structuredClone(schema);delete copy.fields[0].scan;
  expect(schemaHash(copy)).not.toBe(schemaHash(schema));
 });
 it('validates printed length separately from installed cable length',()=>{
  const result=validateValues(schema,{label_declared_length:{amount:1000,unit:'m'},cable_installed:{amount:12,unit:'m'},label_fibre_count:24},false);
  expect(result.valid).toBe(true);expect(result.values.cable_installed).toEqual({amount:12,unit:'m'});
 });
});
