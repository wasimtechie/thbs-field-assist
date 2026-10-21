import {z} from 'zod';
import {avatarIds} from './avatar-catalogue';
export * from './avatar-catalogue';
export const profileInputSchema=z.object({avatarId:z.enum(avatarIds).optional(),name:z.string().trim().min(1).max(100).optional(),expectedRevision:z.number().int().min(1).optional()}).strict().superRefine((v,ctx)=>{
 if(v.avatarId===undefined&&v.name===undefined)ctx.addIssue({code:'custom',message:'Choose an avatar or enter your name.'});
 if(v.name!==undefined&&v.expectedRevision===undefined)ctx.addIssue({code:'custom',path:['expectedRevision'],message:'Reload your profile before editing your name.'});
});
export const boardInputSchema=z.object({name:z.string().trim().min(3).max(80),description:z.string().trim().max(500).default(''),teamId:z.uuid(),clientId:z.uuid().nullable().default(null)}).strict();
export const timeActions=['check_in','break_start','break_end','check_out'] as const;
const fix=z.object({latitude:z.number().finite().min(-90).max(90),longitude:z.number().finite().min(-180).max(180),accuracyMeters:z.number().finite().min(0).max(100000),capturedAt:z.iso.datetime(),isMocked:z.boolean()}).strict();
export const timeEventInputSchema=z.object({requestId:z.uuid(),visitId:z.uuid(),assignmentRevision:z.number().int().min(1),sequence:z.number().int().min(1).max(1000),action:z.enum(timeActions),occurredAt:z.iso.datetime(),location:fix.optional(),note:z.string().trim().max(500).default('')}).strict().superRefine((v,ctx)=>{
 if(['check_in','check_out'].includes(v.action)&&!v.location)ctx.addIssue({code:'custom',path:['location'],message:'Capture location at arrival and departure.'});
 if(v.location&&Math.abs(Date.parse(v.location.capturedAt)-Date.parse(v.occurredAt))>120000)ctx.addIssue({code:'custom',path:['location'],message:'Use the location captured for this action.'});
 if(v.action==='check_in'&&v.sequence!==1)ctx.addIssue({code:'custom',path:['sequence'],message:'Check-in starts the visit at sequence one.'});
});
export function visitDurations(events:{action:string;occurredAt:string|Date}[],now=new Date()){
 let working=0,breaks=0,state='closed',start:number|null=null,first:number|null=null,last:number|null=null;
 for(const e of events){const t=new Date(e.occurredAt).getTime();if(start!==null){const elapsed=Math.max(0,t-start);if(state==='working')working+=elapsed;else if(state==='break')breaks+=elapsed;}if(e.action==='check_in'){first=t;state='working';}else if(e.action==='break_start')state='break';else if(e.action==='break_end')state='working';else state='closed';start=t;last=t;}
 if(start!==null&&state!=='closed'){const elapsed=Math.max(0,now.getTime()-start);if(state==='working')working+=elapsed;else breaks+=elapsed;last=Math.max(start,now.getTime());}
 return {workSeconds:Math.floor(working/1000),breakSeconds:Math.floor(breaks/1000),siteSeconds:first===null||last===null?0:Math.floor(Math.max(0,last-first)/1000)};
}
