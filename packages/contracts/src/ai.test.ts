import {describe,it,expect} from 'vitest';
import {operationsAiInputSchema,reportAiInputSchema,briefAiInputSchema,aiAnalysisSchema} from './ai';
import {hasPermission} from './access';
const id='20000000-0000-4000-8000-000000000001';
describe('dashboard AI contracts',()=>{
 it('accepts focused operations requests and rejects arbitrary tools/scopes',()=>{expect(operationsAiInputSchema.parse({}).question).toBeTruthy();for(const v of [{question:'x'},{question:'Find jobs',organizationId:id},{question:'Find jobs',tools:['sql']},{boardId:'bad'}])expect(operationsAiInputSchema.safeParse(v).success).toBe(false);});
 it('requires a report ID or the scoped engineer needed for drafting',()=>{expect(reportAiInputSchema.safeParse({reportId:id}).success).toBe(true);expect(briefAiInputSchema.safeParse({title:'Cable inspection',assigneeId:id}).success).toBe(true);expect(briefAiInputSchema.safeParse({title:'Cable inspection'}).success).toBe(false);});
 it('requires source references on factual highlights, and permits an honest empty finding set',()=>{const good={summary:'No jobs in this permitted view.',highlights:[],nextSteps:[],draftText:'',limitations:['This view contains no jobs.']};expect(aiAnalysisSchema.safeParse(good).success).toBe(true);expect(aiAnalysisSchema.safeParse({...good,highlights:[{title:'Unlinked claim',detail:'Some fact',tone:'attention',sourceIds:[]}]}).success).toBe(false);});
 it('does not accept automatic decisions, arbitrary actions or oversized drafts',()=>{const base={summary:'Summary',highlights:[],nextSteps:[],draftText:'',limitations:[]};for(const v of [{...base,approve:true},{...base,sql:'SELECT *'},{...base,draftText:'x'.repeat(1501)}])expect(aiAnalysisSchema.safeParse(v).success).toBe(false);});
 it('limits AI access to operational dashboard roles',()=>{for(const role of ['ADMIN','OPERATIONS_MANAGER','TEAM_LEAD','SALES','VIEWER','ENGINEER'])expect(hasPermission(role,'ai.use')).toBe(true);expect(hasPermission('TEMPLATE_MANAGER','ai.use')).toBe(false);});
});
