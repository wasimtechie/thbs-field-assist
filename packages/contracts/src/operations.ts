import {z} from 'zod';
export const workOrderStatuses = ['assigned','submitted','follow_up','completed'] as const;
export const workOrderPriorities = ['normal','high','urgent'] as const;
export const workOrderInputSchema = z.object({
  title:z.string().trim().min(3).max(120),
  site:z.string().trim().min(2).max(180),
  instructions:z.string().trim().max(2000).default(''),
  closureContext:z.object({scenario:z.enum(['S1','S2','S3','S4','S5']),workStage:z.enum(['survey','design','civils','fibre','distribution','network_acceptance','final_provision'])}).strict().optional(),
  assetReference:z.string().trim().max(120).default(''),
  boardId:z.uuid().nullable().optional(), assigneeId:z.uuid(), clientId:z.uuid().nullable().optional(), priority:z.enum(workOrderPriorities), dueAt:z.iso.datetime(),
}).strict();
export const reviewInputSchema=z.object({decision:z.enum(['approved','follow_up']),note:z.string().trim().max(1500).default('')}).strict().superRefine((v,ctx)=>{
  if(v.decision==='follow_up'&&!v.note)ctx.addIssue({code:'custom',path:['note'],message:'Explain what the engineer should revisit.'});
});
export function jobIsOverdue(job:{status:string;dueAt:Date|string},now=new Date()){
  return ['assigned','follow_up'].includes(job.status)&&new Date(job.dueAt)<now;
}
