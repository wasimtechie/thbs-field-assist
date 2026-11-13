import {describe,it,expect} from 'vitest';
import {customerJobStatusInputSchema,customerTime,customerVisitWindow} from './customer-jobs';
const base={expectedRevision:0,customerEmail:'Customer@EXAMPLE.test',appointmentStartAt:null,appointmentEndAt:null,appointmentTimezone:'Europe/London',activationStatus:'not_confirmed',activationAt:null,activationNote:''};
describe('Customer-facing appointment and activation records',()=>{
 it('formats the actual site clock across the UK daylight-saving boundary',()=>{
   expect(customerTime('2026-10-24T09:00:00Z','Europe/London')).toContain('10:00');
   expect(customerTime('2026-10-25T09:00:00Z','Europe/London')).toContain('09:00');
   expect(customerVisitWindow('2026-10-24T09:00:00Z','2026-10-24T11:00:00Z','Europe/London')).toContain('12:00');
 });
 it('normalizes the linked customer and leaves unknown timing unknown',()=>{expect(customerJobStatusInputSchema.parse(base)).toMatchObject({customerEmail:'customer@example.test',appointmentStartAt:null,activationAt:null});});
 it('requires a provider-confirmed time for scheduled activation',()=>{expect(customerJobStatusInputSchema.safeParse({...base,activationStatus:'scheduled'}).success).toBe(false);});
 it('rejects promises attached to blocked or unknown activation',()=>{for(const activationStatus of ['blocked','not_confirmed'])expect(customerJobStatusInputSchema.safeParse({...base,activationStatus,activationAt:'2026-10-26T10:00:00Z'}).success).toBe(false);});
 it('rejects reversed visit windows and unknown time zones',()=>{expect(customerJobStatusInputSchema.safeParse({...base,appointmentStartAt:'2026-10-26T12:00:00Z',appointmentEndAt:'2026-10-26T10:00:00Z'}).success).toBe(false);expect(customerJobStatusInputSchema.safeParse({...base,appointmentTimezone:'Planet/Mars'}).success).toBe(false);});
});
