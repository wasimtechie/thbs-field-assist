import {describe,it,expect} from 'vitest';
import {workOrderInputSchema,reviewInputSchema,jobIsOverdue} from './operations';
const job={title:'Inspect cable',site:'Demo site',instructions:'Read the label.',assetReference:'000042',assigneeId:'20000000-0000-4000-8001-000000000001',priority:'high',dueAt:'2026-10-15T15:00:00.000Z'};
describe('work assignment and human review',()=>{
 it('preserves literal asset identifiers and trims instructions',()=>{expect(workOrderInputSchema.parse({...job,instructions:'  Read the label.  '}).assetReference).toBe('000042');});
 it('rejects invalid priority, dates and arbitrary properties',()=>{for(const patch of [{priority:'critical'},{dueAt:'tomorrow'},{status:'completed'}])expect(workOrderInputSchema.safeParse({...job,...patch}).success).toBe(false);});
 it('requires an actionable note before follow-up',()=>{expect(reviewInputSchema.safeParse({decision:'follow_up',note:'   '}).success).toBe(false);expect(reviewInputSchema.parse({decision:'follow_up',note:'  Verify connectivity.  '}).note).toBe('Verify connectivity.');});
 it('does not treat a received report as overdue open work',()=>{for(const status of ['submitted','completed'])expect(jobIsOverdue({...job,status},new Date('2026-10-16T00:00:00Z'))).toBe(false);for(const status of ['assigned','follow_up'])expect(jobIsOverdue({...job,status},new Date('2026-10-16T00:00:00Z'))).toBe(true);});
});
