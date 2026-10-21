import type {Field,Values} from './index';
export function isVisible(field:Field,values:Values,fields?:Field[],seen=new Set<string>()):boolean{
  if(!field.condition)return true;
  if(seen.has(field.id))return false;seen.add(field.id);
  const parent=fields?.find(f=>f.id===field.condition!.fieldId);
  if(parent&&!isVisible(parent,values,fields,seen))return false;
  const value=values[field.condition.fieldId];
  return field.condition.operator==='equals'?value===field.condition.value:typeof value==='string'&&field.condition.value.includes(value);
}
export function isMissing(value:unknown){return value===null||value===undefined||typeof value==='string'&&!value.trim();}
