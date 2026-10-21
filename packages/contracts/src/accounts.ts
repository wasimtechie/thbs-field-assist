import {z} from 'zod';
import {accountRoles} from './access';
const details={employeeCode:z.string().trim().max(60).optional(),department:z.string().trim().max(100).optional(),jobTitle:z.string().trim().max(100).optional(),phone:z.string().trim().max(30).optional(),baseLocation:z.string().trim().max(160).optional(),teamId:z.uuid().nullable().optional()};
export const accountCreateSchema=z.object({name:z.string().trim().min(1).max(100),email:z.string().trim().toLowerCase().pipe(z.email().max(254)),...details,role:z.enum(accountRoles),typeId:z.uuid().optional(),initialPassword:z.string().min(6).max(256)}).strict().superRefine((v,ctx)=>{
 if(v.role==='ENGINEER'&&!v.typeId)ctx.addIssue({code:'custom',path:['typeId'],message:'Choose an engineer type.'});
 if(v.role!=='ENGINEER'&&v.typeId)ctx.addIssue({code:'custom',path:['typeId'],message:'Dashboard employees do not have a field engineer type.'});
});
export const accountPatchSchema=z.object({expectedRevision:z.number().int().min(1),name:z.string().trim().min(1).max(100).optional(),email:z.string().trim().toLowerCase().pipe(z.email().max(254)).optional(),...details,role:z.enum(accountRoles).optional(),typeId:z.uuid().optional(),status:z.enum(['active','paused','removed']).optional(),newPassword:z.string().min(6).max(256).optional()}).strict();
