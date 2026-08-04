/**
 * Label and Barcode Operations contract (ATW-021, CG-S10-ATW-021, Prompt 240). Mirrors
 * supabase/migrations/20260730290000_create_advanced_tms_label_barcode_operations.sql's
 * app.label_templates/app.label_template_versions/app.label_printers/
 * app.label_instances/app.label_print_jobs/app.label_scan_events shapes and their
 * template-lifecycle/printer-admin/generate-preview-print-reprint-void/resolve/read
 * RPCs.
 */

import { z } from "zod";

export const LABEL_SUBJECT_TYPES = ["bin", "item", "lot", "serial", "package", "pallet", "task"] as const;
export const LabelSubjectTypeSchema = z.enum(LABEL_SUBJECT_TYPES);
export type LabelSubjectType = z.infer<typeof LabelSubjectTypeSchema>;

export const LABEL_TEMPLATE_VERSION_STATUSES = ["draft", "published", "archived"] as const;
export const LabelTemplateVersionStatusSchema = z.enum(LABEL_TEMPLATE_VERSION_STATUSES);
export type LabelTemplateVersionStatus = z.infer<typeof LabelTemplateVersionStatusSchema>;

export const LABEL_SYMBOLOGIES = ["code128", "code39", "qr", "datamatrix"] as const;
export const LabelSymbologySchema = z.enum(LABEL_SYMBOLOGIES);
export type LabelSymbology = z.infer<typeof LabelSymbologySchema>;

export const LABEL_PRINTER_STATUSES = ["active", "inactive"] as const;
export const LabelPrinterStatusSchema = z.enum(LABEL_PRINTER_STATUSES);
export type LabelPrinterStatus = z.infer<typeof LabelPrinterStatusSchema>;

export const LABEL_INSTANCE_STATUSES = ["active", "void"] as const;
export const LabelInstanceStatusSchema = z.enum(LABEL_INSTANCE_STATUSES);
export type LabelInstanceStatus = z.infer<typeof LabelInstanceStatusSchema>;

export const LABEL_PRINT_JOB_STATUSES = ["queued", "succeeded", "failed", "cancelled"] as const;
export const LabelPrintJobStatusSchema = z.enum(LABEL_PRINT_JOB_STATUSES);
export type LabelPrintJobStatus = z.infer<typeof LabelPrintJobStatusSchema>;

export const LABEL_PRINT_OUTCOME_STATUSES = ["succeeded", "failed"] as const;
export const LabelPrintOutcomeStatusSchema = z.enum(LABEL_PRINT_OUTCOME_STATUSES);
export type LabelPrintOutcomeStatus = z.infer<typeof LabelPrintOutcomeStatusSchema>;

export const LABEL_SCAN_REJECTION_REASONS = ["invalid_checksum", "unknown_code", "void_code", "insufficient_authority"] as const;
export const LabelScanRejectionReasonSchema = z.enum(LABEL_SCAN_REJECTION_REASONS);
export type LabelScanRejectionReason = z.infer<typeof LabelScanRejectionReasonSchema>;

// --- Row schemas ---

export const LabelTemplateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  subjectType: LabelSubjectTypeSchema,
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type LabelTemplate = z.infer<typeof LabelTemplateSchema>;

export function parseLabelTemplate(row: Record<string, unknown>): LabelTemplate {
  return LabelTemplateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    code: row.code,
    name: row.name,
    subjectType: row.subject_type,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
  });
}

export const LabelTemplateVersionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  templateId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  contentTemplate: z.string(),
  allowedVariables: z.array(z.string()),
  symbology: LabelSymbologySchema,
  status: LabelTemplateVersionStatusSchema,
  supersedesVersionId: z.string().uuid().nullable(),
  effectiveFrom: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LabelTemplateVersion = z.infer<typeof LabelTemplateVersionSchema>;

export function parseLabelTemplateVersion(row: Record<string, unknown>): LabelTemplateVersion {
  return LabelTemplateVersionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    templateId: row.template_id,
    versionNumber: row.version_number,
    contentTemplate: row.content_template,
    allowedVariables: row.allowed_variables ?? [],
    symbology: row.symbology,
    status: row.status,
    supersedesVersionId: row.supersedes_version_id ?? null,
    effectiveFrom: row.effective_from,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const LabelPrinterSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  connectionDescriptor: z.record(z.string(), z.unknown()),
  status: LabelPrinterStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LabelPrinter = z.infer<typeof LabelPrinterSchema>;

export function parseLabelPrinter(row: Record<string, unknown>): LabelPrinter {
  return LabelPrinterSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id ?? null,
    code: row.code,
    name: row.name,
    connectionDescriptor: row.connection_descriptor ?? {},
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const LabelInstanceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  templateVersionId: z.string().uuid(),
  subjectType: LabelSubjectTypeSchema,
  subjectId: z.string().uuid(),
  ownerAccountId: z.string().uuid().nullable(),
  warehouseId: z.string().uuid().nullable(),
  encodedValue: z.string(),
  encodedValueDigest: z.string(),
  variablesSnapshot: z.record(z.string(), z.unknown()),
  status: LabelInstanceStatusSchema,
  voidReason: z.string().nullable(),
  voidedByAuthUserId: z.string().uuid().nullable(),
  voidedByLabel: z.string().nullable(),
  voidedAt: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LabelInstance = z.infer<typeof LabelInstanceSchema>;

export function parseLabelInstance(row: Record<string, unknown>): LabelInstance {
  return LabelInstanceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    templateVersionId: row.template_version_id,
    subjectType: row.subject_type,
    subjectId: row.subject_id,
    ownerAccountId: row.owner_account_id ?? null,
    warehouseId: row.warehouse_id ?? null,
    encodedValue: row.encoded_value,
    encodedValueDigest: row.encoded_value_digest,
    variablesSnapshot: row.variables_snapshot ?? {},
    status: row.status,
    voidReason: row.void_reason ?? null,
    voidedByAuthUserId: row.voided_by_auth_user_id ?? null,
    voidedByLabel: row.voided_by_label ?? null,
    voidedAt: row.voided_at ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const LabelPrintJobSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  labelInstanceId: z.string().uuid(),
  printerId: z.string().uuid(),
  appJobId: z.string().uuid().nullable(),
  copies: z.number().int().positive(),
  isReprint: z.boolean(),
  reprintReason: z.string().nullable(),
  renderedPayload: z.string(),
  status: LabelPrintJobStatusSchema,
  outcomeError: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid().nullable(),
  requestedByLabel: z.string().nullable(),
  requestedAt: z.string(),
  completedAt: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type LabelPrintJob = z.infer<typeof LabelPrintJobSchema>;

export function parseLabelPrintJob(row: Record<string, unknown>): LabelPrintJob {
  return LabelPrintJobSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    labelInstanceId: row.label_instance_id,
    printerId: row.printer_id,
    appJobId: row.app_job_id ?? null,
    copies: row.copies,
    isReprint: row.is_reprint,
    reprintReason: row.reprint_reason ?? null,
    renderedPayload: row.rendered_payload,
    status: row.status,
    outcomeError: row.outcome_error ?? null,
    requestedByAuthUserId: row.requested_by_auth_user_id ?? null,
    requestedByLabel: row.requested_by_label ?? null,
    requestedAt: row.requested_at,
    completedAt: row.completed_at ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

export const LabelScanEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  encodedValue: z.string(),
  labelInstanceId: z.string().uuid().nullable(),
  subjectType: LabelSubjectTypeSchema.nullable(),
  resolved: z.boolean(),
  rejectionReason: LabelScanRejectionReasonSchema.nullable(),
  scannedByAuthUserId: z.string().uuid().nullable(),
  scannedByLabel: z.string().nullable(),
  scannedAt: z.string(),
});
export type LabelScanEvent = z.infer<typeof LabelScanEventSchema>;

export function parseLabelScanEvent(row: Record<string, unknown>): LabelScanEvent {
  return LabelScanEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    encodedValue: row.encoded_value,
    labelInstanceId: row.label_instance_id ?? null,
    subjectType: row.subject_type ?? null,
    resolved: row.resolved,
    rejectionReason: row.rejection_reason ?? null,
    scannedByAuthUserId: row.scanned_by_auth_user_id ?? null,
    scannedByLabel: row.scanned_by_label ?? null,
    scannedAt: row.scanned_at,
  });
}

/**
 * app.resolve_label's own composite return shape -- NEVER raises for an ordinary
 * rejection outcome (invalid_checksum/unknown_code/void_code/insufficient_authority);
 * it RETURNS resolved=false with rejection_reason set instead (the migration's own
 * design note 12 -- an audit-log-survives-the-rejection guarantee, mirroring
 * app.resolve_gps_device_for_handshake/ATW-226D). Only a prior tenant-membership/RBAC
 * authority failure (no scan attempt to log at all) still raises.
 */
export const LabelResolveResultSchema = z.object({
  resolved: z.boolean(),
  rejectionReason: LabelScanRejectionReasonSchema.nullable(),
  labelInstanceId: z.string().uuid().nullable(),
  templateVersionId: z.string().uuid().nullable(),
  subjectType: LabelSubjectTypeSchema.nullable(),
  subjectId: z.string().uuid().nullable(),
  encodedValue: z.string().nullable(),
  status: LabelInstanceStatusSchema.nullable(),
  subjectCode: z.string().nullable(),
  subjectName: z.string().nullable(),
  subjectStatus: z.string().nullable(),
});
export type LabelResolveResult = z.infer<typeof LabelResolveResultSchema>;

export function parseLabelResolveResult(row: Record<string, unknown>): LabelResolveResult {
  return LabelResolveResultSchema.parse({
    resolved: row.resolved,
    rejectionReason: row.rejection_reason ?? null,
    labelInstanceId: row.label_instance_id ?? null,
    templateVersionId: row.template_version_id ?? null,
    subjectType: row.subject_type ?? null,
    subjectId: row.subject_id ?? null,
    encodedValue: row.encoded_value ?? null,
    status: row.status ?? null,
    subjectCode: row.subject_code ?? null,
    subjectName: row.subject_name ?? null,
    subjectStatus: row.subject_status ?? null,
  });
}

// --- Mutation input schemas ---

export const CreateLabelTemplateInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(1),
  name: z.string().min(1),
  subjectType: LabelSubjectTypeSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateLabelTemplateInput = z.input<typeof CreateLabelTemplateInputSchema>;

export const CreateLabelTemplateVersionDraftInputSchema = z.object({
  templateId: z.string().uuid(),
  contentTemplate: z.string().min(1),
  allowedVariables: z.array(z.string()).default([]),
  symbology: LabelSymbologySchema.optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateLabelTemplateVersionDraftInput = z.input<typeof CreateLabelTemplateVersionDraftInputSchema>;

export const PublishLabelTemplateVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishLabelTemplateVersionInput = z.input<typeof PublishLabelTemplateVersionInputSchema>;

export const SetLabelTemplateVersionStatusInputSchema = z.object({
  versionId: z.string().uuid(),
  newStatus: z.literal("archived"),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetLabelTemplateVersionStatusInput = z.input<typeof SetLabelTemplateVersionStatusInputSchema>;

export const CreateLabelPrinterInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid().nullable().optional(),
  code: z.string().min(1),
  name: z.string().min(1),
  connectionDescriptor: z.record(z.string(), z.unknown()).optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateLabelPrinterInput = z.input<typeof CreateLabelPrinterInputSchema>;

export const SetLabelPrinterStatusInputSchema = z.object({
  printerId: z.string().uuid(),
  newStatus: LabelPrinterStatusSchema,
  reason: z.string().nullable().optional(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetLabelPrinterStatusInput = z.input<typeof SetLabelPrinterStatusInputSchema>;

export const PreviewLabelInputSchema = z.object({
  templateVersionId: z.string().uuid(),
  variables: z.record(z.string(), z.unknown()).optional(),
  actorAuthUserId: z.string().uuid(),
});
export type PreviewLabelInput = z.input<typeof PreviewLabelInputSchema>;

export const GenerateLabelInputSchema = z.object({
  tenantId: z.string().uuid(),
  templateCode: z.string().min(1),
  subjectType: LabelSubjectTypeSchema,
  subjectId: z.string().uuid(),
  variables: z.record(z.string(), z.unknown()).optional(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type GenerateLabelInput = z.input<typeof GenerateLabelInputSchema>;

export const PrintLabelInputSchema = z.object({
  labelInstanceId: z.string().uuid(),
  printerId: z.string().uuid(),
  copies: z.number().int().positive().default(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PrintLabelInput = z.input<typeof PrintLabelInputSchema>;

export const ReprintLabelInputSchema = z.object({
  labelInstanceId: z.string().uuid(),
  printerId: z.string().uuid(),
  copies: z.number().int().positive().default(1),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReprintLabelInput = z.input<typeof ReprintLabelInputSchema>;

export const VoidLabelInputSchema = z.object({
  labelInstanceId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type VoidLabelInput = z.input<typeof VoidLabelInputSchema>;

/** service_role only -- a worker-side callback, never a client action (no authenticated grant at all). */
export const RecordLabelPrintOutcomeInputSchema = z.object({
  labelPrintJobId: z.string().uuid(),
  outcomeStatus: LabelPrintOutcomeStatusSchema,
  error: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordLabelPrintOutcomeInput = z.input<typeof RecordLabelPrintOutcomeInputSchema>;

export const ResolveLabelInputSchema = z.object({
  tenantId: z.string().uuid(),
  encodedValue: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ResolveLabelInput = z.input<typeof ResolveLabelInputSchema>;
