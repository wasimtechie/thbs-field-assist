import {matches,type Expression} from './closure/policy';
import type {Field,Values} from './index';
export function isVisible(field:Field,values:Values,fields?:Field[],seen=new Set<string>()):boolean{
  if(field.activation){
    const active=(e:Expression):boolean=>{if('all'in e)return e.all.every(active);if('any'in e)return e.any.some(active);const parent=fields?.find(f=>f.id===e.field);return (!parent||isVisible(parent,values,fields,new Set([...seen,field.id])))&&matches(e,values);};
    if(seen.has(field.id))return false;
    if(!active(field.activation))return false;
  }
  if(!field.condition)return true;
  if(seen.has(field.id))return false;seen.add(field.id);
  const parent=fields?.find(f=>f.id===field.condition!.fieldId);
  if(parent&&!isVisible(parent,values,fields,seen))return false;
  const value=values[field.condition.fieldId];
  return field.condition.operator==='equals'?value===field.condition.value:typeof value==='string'&&field.condition.value.includes(value);
}
export function isMissing(value:unknown){return value===null||value===undefined||typeof value==='string'&&!value.trim();}
