import {describe,it,expect} from 'vitest';
import {frozenReportSchema,reportLocationSchema} from './index';
const id='10000000-0000-4000-8000-000000000001';
const location={latitude:0,longitude:0,accuracyMeters:2500,capturedAt:'2026-10-15T12:00:00.000Z',isMocked:true};
const report={clientReportId:id,submissionAttemptId:id,revision:1,templateId:id,versionId:id,schemaHash:'a'.repeat(64),entitlementId:id,values:{},confirmedAt:'2026-10-15T12:00:10.000Z',originatingTimezone:'UTC',location};
describe('captured report location',()=>{
 it('preserves valid zero coordinates and approximate accuracy',()=>expect(reportLocationSchema.parse(location)).toEqual(location));
 it.each([{latitude:91},{longitude:-181},{accuracyMeters:-1},{latitude:NaN},{longitude:Infinity},{capturedAt:'yesterday'},{isMocked:'true'}])('rejects invalid metadata %j',change=>expect(reportLocationSchema.safeParse({...location,...change}).success).toBe(false));
 it('rejects a stale fix at confirmation',()=>expect(frozenReportSchema.safeParse({...report,location:{...location,capturedAt:'2026-10-15T11:55:00.000Z'}}).success).toBe(false));
 it('rejects a fix captured after confirmation',()=>expect(frozenReportSchema.safeParse({...report,location:{...location,capturedAt:'2026-10-15T12:05:00.000Z'}}).success).toBe(false));
 it('accepts an offline snapshot regardless of later upload date',()=>expect(frozenReportSchema.safeParse(report).success).toBe(true));
 it('keeps old frozen queues compatible without inventing coordinates',()=>{const {location:_,...legacy}=report;expect(frozenReportSchema.parse(legacy)).not.toHaveProperty('location');});
});
