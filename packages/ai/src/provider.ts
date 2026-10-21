export class AiProviderError extends Error {
 constructor(public code:string,message:string,public status=503){super(message);}
}
export type CompletionInput={instructions:string;data:unknown;schema:Record<string,unknown>};
export type Completion={value:unknown;model:string;usage:{inputTokens:number;outputTokens:number}};
export async function completeJson(input:CompletionInput,config:{apiKey:string;model:string;fetcher?:typeof fetch}):Promise<Completion>{
 if(!config.apiKey.trim())throw new AiProviderError('AI_NOT_CONFIGURED','AI is not configured on this server. Your saved work is available.');
 let response:Response;
 try{response=await (config.fetcher??fetch)('https://api.openai.com/v1/responses',{method:'POST',headers:{Authorization:`Bearer ${config.apiKey.trim()}`,'Content-Type':'application/json'},signal:AbortSignal.timeout(45000),body:JSON.stringify({model:config.model,store:false,instructions:input.instructions,input:[{role:'user',content:[{type:'input_text',text:JSON.stringify(input.data)}]}],text:{format:{type:'json_schema',name:'thbs_field_assist',strict:true,schema:input.schema}},max_output_tokens:2400,temperature:0.2})});}
 catch{throw new AiProviderError('AI_CONNECTION_FAILED','AI could not connect in time. Your work is saved; try again when the service is reachable.');}
 let body:any;try{body=await response.json();}catch{throw new AiProviderError('AI_INVALID_RESPONSE','AI returned an unreadable response. Try again.');}
 if(!response.ok){
  if(response.status===429&&body?.error?.code==='insufficient_quota')throw new AiProviderError('AI_QUOTA_EXCEEDED','OpenAI billing or API credit is unavailable. Ask the workspace administrator to check the API project.');
  if(response.status===429)throw new AiProviderError('AI_PROVIDER_BUSY','AI is busy. Wait a minute and try again.',429);
  if([401,403].includes(response.status))throw new AiProviderError('AI_KEY_REJECTED','OpenAI rejected the server credential. Ask the administrator to update the API key.');
  if(response.status===404)throw new AiProviderError('AI_MODEL_UNAVAILABLE','The configured AI model is unavailable to this API project. Ask the administrator to check the model setting.');
  throw new AiProviderError('AI_PROVIDER_UNAVAILABLE','AI is temporarily unavailable. Your saved work is available.');
 }
 const output=Array.isArray(body.output)?body.output:[];
 const content=output.flatMap((v:any)=>v.type==='message'&&Array.isArray(v.content)?v.content:[]);
 if(content.some((v:any)=>v.type==='refusal'))throw new AiProviderError('AI_REFUSED','AI could not complete this request. Use a field-operations question or complete the task manually.',422);
 if(body.status!=='completed')throw new AiProviderError('AI_INCOMPLETE','AI could not finish the response. Try a more focused request.');
 const text=content.filter((v:any)=>v.type==='output_text'&&typeof v.text==='string').map((v:any)=>v.text).join('');
 let value:unknown;try{value=JSON.parse(text);}catch{throw new AiProviderError('AI_INVALID_RESPONSE','AI returned an incomplete answer. Try again.');}
 const tokens=(n:unknown)=>typeof n==='number'&&Number.isInteger(n)&&n>=0?n:0;
 return {value,model:typeof body.model==='string'?body.model:config.model,usage:{inputTokens:tokens(body.usage?.input_tokens),outputTokens:tokens(body.usage?.output_tokens)}};
}
