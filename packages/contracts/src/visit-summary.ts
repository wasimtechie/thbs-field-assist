import {z} from 'zod';
export const visitSummaryLabels = {
  actual_work: 'Work done', claimed_outcome: 'Visit outcome',
  access_permission: 'Customer access permission', location_agreed: 'ONT location approved',
  drop_route: 'Fibre route', external_connection: 'External fibre / connection point installed',
  internal_fibre: 'Internal fibre fitted to ONT', ont_fitted: 'ONT installed',
  ont_status_checked: 'ONT power and status checked', optical_rx_dbm: 'Optical reading (dBm)',
  operational_test: 'Test result', service_live: 'Service live',
  customer_handover: 'Customer shown the equipment', site_handover_safe: 'Site left safe and tidy',
  next_action: 'Follow-up / next action', serving_asset: 'Asset reference',
};
const text = z.string().trim().min(1).max(8000);
const visitSourceSchema = z.object({
    sourceType: z.enum(['speech','manual','text']), sourceSpan: z.string().max(8000),
    question: z.string().max(2000).optional(),
    // Retain extraction provenance without treating it as closure approval.
    fieldId: z.string().optional(), value: z.unknown().optional(), confidence: z.number().nullable().optional(),
    verificationStatus: z.string().optional(), ambiguityReason: z.string().optional(),
    derivedFrom: z.literal('actual_work').optional(), derivedSummary: z.string().max(8000).optional(),
    requiresConfirmation: z.boolean().optional(), unitNeedsConfirmation: z.boolean().optional(),
    unitSource: z.literal('field_definition').optional(), confirmationSpan: z.string().max(2000).optional(),
    rawTranscript: z.string().max(8000).optional(), interpretedSpan: z.string().max(8000).optional(),
    speechRepairs: z.array(z.object({
      discarded: z.string().max(8000), cue: z.string().max(160), replacement: z.string().max(8000),
    }).strict()).max(24).optional(),
  }).strict();
export const visitSummarySchema = z.object({
  clientSummaryId: z.uuid(), clientReportId: z.uuid(), workOrderId: z.uuid().nullable(),
  confirmedAt: z.iso.datetime(),
  values: z.object({
    actual_work: text,
    claimed_outcome: z.enum(['completed','partial','blocked','referred','hold','stage_completed','network_ready']),
    serving_asset: text.nullable().optional(),
    access_permission: z.boolean().nullable().optional(),
    location_agreed: z.boolean().nullable().optional(),
    drop_route: z.enum(['existing','underground','overhead']).nullable().optional(),
    external_connection: z.boolean().nullable().optional(),
    internal_fibre: z.boolean().nullable().optional(),
    ont_fitted: z.boolean().nullable().optional(),
    ont_status_checked: z.boolean().nullable().optional(),
    service_live: z.boolean().nullable().optional(),
    customer_handover: z.boolean().nullable().optional(),
    site_handover_safe: z.boolean().nullable().optional(),
    optical_rx_dbm: z.number().finite().min(-100).max(100).nullable().optional(),
    operational_test: z.enum(['passed','failed','not_tested','not_applicable']).nullable().optional(),
    next_action: text.nullable().optional(),
  }).strict().refine(v => v.claimed_outcome === 'completed' || !!v.next_action,
    {message:'Record the next action for an incomplete visit.',path:['next_action']}),
  sources: z.partialRecord(z.enum(Object.keys(visitSummaryLabels) as [string,...string[]]), visitSourceSchema.extend({
    inputMethod: z.enum(['speech','option','typed','transcript_edit']).optional(),
    originalSpeech: visitSourceSchema.optional(),
    previousTranscript: z.string().max(8000).optional(),
    editedAt: z.iso.datetime().optional(),
  }).strict()),
}).strict();
