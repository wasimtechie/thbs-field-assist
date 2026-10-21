import {z} from 'zod';
export const operationsAiInputSchema=z.object({question:z.string().trim().min(3).max(1000).default('What needs attention today?'),boardId:z.uuid().optional(),clientId:z.uuid().optional()}).strict();
export const reportAiInputSchema=z.object({reportId:z.uuid()}).strict();
export const briefAiInputSchema=z.object({title:z.string().trim().min(3).max(120),instructions:z.string().trim().max(2000).default(''),assigneeId:z.uuid(),jobId:z.uuid().optional()}).strict();
export const aiAnalysisSchema=z.object({
 summary:z.string().trim().min(1).max(1600),
 highlights:z.array(z.object({title:z.string().trim().min(1).max(100),detail:z.string().trim().min(1).max(700),tone:z.enum(['info','attention','positive']),sourceIds:z.array(z.string().min(1).max(80)).min(1).max(6)}).strict()).max(6),
 nextSteps:z.array(z.object({text:z.string().trim().min(1).max(500),sourceIds:z.array(z.string().min(1).max(80)).min(1).max(6)}).strict()).max(6),
 draftText:z.string().trim().max(1500),limitations:z.array(z.string().trim().min(1).max(400)).max(5),
}).strict();
export type AiAnalysis=z.infer<typeof aiAnalysisSchema>;
export type AiSource={id:string;label:string;href:string|null};
export type AiResult={id:string;kind:'operations'|'report'|'brief';analysis:AiAnalysis;sources:AiSource[];model:string;generatedAt:string;cached:boolean;usage:{inputTokens:number;outputTokens:number}};
