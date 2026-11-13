import {z} from 'zod';

export function customerTime(value:Date|string,timeZone:string) {
  return new Intl.DateTimeFormat('en-GB',{dateStyle:'long',timeStyle:'short',timeZone}).format(new Date(value));
}
export function customerVisitWindow(start:Date|string,end:Date|string|null,timeZone:string) {
  return `${customerTime(start,timeZone)}${end?' – '+customerTime(end,timeZone):''} (${timeZone})`;
}

export const customerJobStatusInputSchema = z.object({
  expectedRevision: z.number().int().min(0),
  customerEmail: z.email().max(254).transform(v => v.trim().toLowerCase()),
  appointmentStartAt: z.iso.datetime().nullable(),
  appointmentEndAt: z.iso.datetime().nullable(),
  appointmentTimezone: z.string().max(100).refine(v => {
    try {new Intl.DateTimeFormat('en', {timeZone:v});return true;} catch {return false;}
  }, 'Choose a valid time zone.'),
  activationStatus: z.enum(['not_confirmed','scheduled','active','blocked']),
  activationAt: z.iso.datetime().nullable(),
  activationNote: z.string().trim().max(1500).default(''),
}).strict().superRefine((v,ctx) => {
  if(v.appointmentEndAt && (!v.appointmentStartAt || v.appointmentEndAt <= v.appointmentStartAt))
    ctx.addIssue({code:'custom',path:['appointmentEndAt'],message:'The visit window must end after it starts.'});
  if(v.activationStatus==='scheduled' && !v.activationAt)
    ctx.addIssue({code:'custom',path:['activationAt'],message:'Record the provider-confirmed activation time.'});
  if(['not_confirmed','blocked'].includes(v.activationStatus) && v.activationAt)
    ctx.addIssue({code:'custom',path:['activationAt'],message:'An unconfirmed or blocked activation has no promised start time.'});
});
