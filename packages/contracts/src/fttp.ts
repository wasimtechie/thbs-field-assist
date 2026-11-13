export const FTTP_TEMPLATE_ID='40000000-0000-4000-8000-000000000005';
export function fttpIssues(templateId:string,values:Record<string,unknown>,evidence:{stage:string}[]){
 if(templateId!==FTTP_TEMPLATE_ID)return [];
 const issues:string[]=[];
 const completed=values.installation_outcome==='completed';
 if(completed){
  for(const [field,label] of [['access_confirmed','Site access'],['route_agreed','Agreed route'],['site_checks','Site checks'],['customer_handover','Customer handover'],['site_tidy','Site left tidy']])if(values[field]!==true)issues.push(`${label} must be confirmed for a completed installation.`);
  if(values.connectivity_test!=='passed')issues.push('A completed installation needs a recorded passing connectivity test.');
  for(const stage of ['before','installation','test'])if(!evidence.some(e=>e.stage===stage))issues.push(`Add ${stage} evidence before completing this installation.`);
 }else if(['blocked','partial'].includes(String(values.installation_outcome))){
  for(const field of ['exception_reason','next_team','next_action'])if(typeof values[field]!=='string'||!(values[field] as string).trim())issues.push('Record the blocker, next team and next action.');
  if(!evidence.some(e=>e.stage==='blocker'))issues.push('Add blocker evidence for the receiving team.');
 }
 return [...new Set(issues)];
}
