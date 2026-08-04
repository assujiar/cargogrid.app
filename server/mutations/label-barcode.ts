/**
 * Label and Barcode Operations mutation primitives (ATW-021, CG-S10-ATW-021). Thin,
 * typed wrappers around app.create_label_template/app.create_label_template_version_
 * draft/app.publish_label_template_version/app.set_label_template_version_status/
 * app.create_label_printer/app.set_label_printer_status/app.preview_label/
 * app.generate_label/app.print_label/app.reprint_label/app.void_label/
 * app.record_label_print_outcome/app.resolve_label
 * (supabase/migrations/20260730290000_create_advanced_tms_label_barcode_operations.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateLabelTemplateInputSchema,
  CreateLabelTemplateVersionDraftInputSchema,
  PublishLabelTemplateVersionInputSchema,
  SetLabelTemplateVersionStatusInputSchema,
  CreateLabelPrinterInputSchema,
  SetLabelPrinterStatusInputSchema,
  PreviewLabelInputSchema,
  GenerateLabelInputSchema,
  PrintLabelInputSchema,
  ReprintLabelInputSchema,
  VoidLabelInputSchema,
  RecordLabelPrintOutcomeInputSchema,
  ResolveLabelInputSchema,
  parseLabelTemplate,
  parseLabelTemplateVersion,
  parseLabelPrinter,
  parseLabelInstance,
  parseLabelPrintJob,
  parseLabelResolveResult,
  type CreateLabelTemplateInput,
  type CreateLabelTemplateVersionDraftInput,
  type PublishLabelTemplateVersionInput,
  type SetLabelTemplateVersionStatusInput,
  type CreateLabelPrinterInput,
  type SetLabelPrinterStatusInput,
  type PreviewLabelInput,
  type GenerateLabelInput,
  type PrintLabelInput,
  type ReprintLabelInput,
  type VoidLabelInput,
  type RecordLabelPrintOutcomeInput,
  type ResolveLabelInput,
  type LabelTemplate,
  type LabelTemplateVersion,
  type LabelPrinter,
  type LabelInstance,
  type LabelPrintJob,
  type LabelResolveResult,
} from "../contracts/label-barcode/label-barcode.ts";

export type LabelBarcodeMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LABEL_BARCODE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_code",
  "invalid_name",
  "invalid_subject_type",
  "label_template_code_conflict",
  "label_printer_code_conflict",
  "idempotency_key_conflict",
  "label_template_not_found",
  "invalid_content_template",
  "invalid_symbology",
  "unwhitelisted_template_variable",
  "label_template_version_not_found",
  "stale_version",
  "invalid_transition",
  "superseded_version_not_found",
  "invalid_supersede",
  "active_template_version_exists",
  "invalid_status_transition",
  "reason_required",
  "warehouse_not_found",
  "invalid_connection_descriptor",
  "label_printer_not_found",
  "invalid_status",
  "unsafe_variable",
  "invalid_idempotency_key",
  "subject_type_mismatch",
  "stale_template",
  "subject_not_found",
  "invalid_copies",
  "label_voided",
  "printer_inactive",
  "label_instance_not_found",
  "already_void",
  "invalid_outcome_status",
  "label_print_job_not_found",
  "label_print_job_already_resolved",
  "invalid_actor_label",
] as const;
type KnownLabelBarcodeMutationErrorCode = (typeof LABEL_BARCODE_KNOWN_MUTATION_ERROR_CODES)[number];
export type LabelBarcodeMutationErrorCode = KnownLabelBarcodeMutationErrorCode | "mutation_failed" | "invalid_response";

export class LabelBarcodeMutationError extends Error {
  readonly code: LabelBarcodeMutationErrorCode;

  constructor(code: LabelBarcodeMutationErrorCode, message: string) {
    super(message);
    this.name = "LabelBarcodeMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LabelBarcodeMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (LABEL_BARCODE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownLabelBarcodeMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseTemplateResponse(data: unknown, rpcName: string): LabelTemplate {
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseLabelTemplate(row);
}

function parseTemplateVersionResponse(data: unknown, rpcName: string): LabelTemplateVersion {
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseLabelTemplateVersion(row);
}

function parsePrinterResponse(data: unknown, rpcName: string): LabelPrinter {
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseLabelPrinter(row);
}

function parseInstanceResponse(data: unknown, rpcName: string): LabelInstance {
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseLabelInstance(row);
}

function parsePrintJobResponse(data: unknown, rpcName: string): LabelPrintJob {
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseLabelPrintJob(row);
}

/** Idempotent on (tenant_id, code). code/subject_type are immutable once created. */
export async function createLabelTemplate(client: LabelBarcodeMutationRpcClient, input: CreateLabelTemplateInput): Promise<LabelTemplate> {
  const parsedInput = CreateLabelTemplateInputSchema.parse(input);
  const { data, error } = await client.rpc("create_label_template", {
    p_tenant_id: parsedInput.tenantId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_subject_type: parsedInput.subjectType,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parseTemplateResponse(data, "create_label_template");
}

/** Rejects unwhitelisted_template_variable at DRAFT time -- every {{name}} placeholder in contentTemplate must already be in allowedVariables. */
export async function createLabelTemplateVersionDraft(client: LabelBarcodeMutationRpcClient, input: CreateLabelTemplateVersionDraftInput): Promise<LabelTemplateVersion> {
  const parsedInput = CreateLabelTemplateVersionDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_label_template_version_draft", {
    p_template_id: parsedInput.templateId,
    p_content_template: parsedInput.contentTemplate,
    p_allowed_variables: parsedInput.allowedVariables,
    p_symbology: parsedInput.symbology ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parseTemplateVersionResponse(data, "create_label_template_version_draft");
}

/** draft -> published, archiving supersedesVersionId first so at most one published version ever exists per template. */
export async function publishLabelTemplateVersion(client: LabelBarcodeMutationRpcClient, input: PublishLabelTemplateVersionInput): Promise<LabelTemplateVersion> {
  const parsedInput = PublishLabelTemplateVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_label_template_version", {
    p_version_id: parsedInput.versionId,
    p_expected_version: parsedInput.expectedVersion,
    p_supersedes_version_id: parsedInput.supersedesVersionId ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parseTemplateVersionResponse(data, "publish_label_template_version");
}

/** The archive path only (draft->archived or published->archived). */
export async function setLabelTemplateVersionStatus(client: LabelBarcodeMutationRpcClient, input: SetLabelTemplateVersionStatusInput): Promise<LabelTemplateVersion> {
  const parsedInput = SetLabelTemplateVersionStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_label_template_version_status", {
    p_version_id: parsedInput.versionId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parseTemplateVersionResponse(data, "set_label_template_version_status");
}

/** Idempotent on (tenant_id, code). warehouseId, when given, must belong to the same tenant -- omit for a tenant-wide "virtual"/office printer. */
export async function createLabelPrinter(client: LabelBarcodeMutationRpcClient, input: CreateLabelPrinterInput): Promise<LabelPrinter> {
  const parsedInput = CreateLabelPrinterInputSchema.parse(input);
  const { data, error } = await client.rpc("create_label_printer", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId ?? null,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_connection_descriptor: parsedInput.connectionDescriptor ?? {},
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parsePrinterResponse(data, "create_label_printer");
}

/** active <-> inactive. A non-empty reason is required to deactivate. */
export async function setLabelPrinterStatus(client: LabelBarcodeMutationRpcClient, input: SetLabelPrinterStatusInput): Promise<LabelPrinter> {
  const parsedInput = SetLabelPrinterStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_label_printer_status", {
    p_printer_id: parsedInput.printerId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason ?? null,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parsePrinterResponse(data, "set_label_printer_status");
}

/** STABLE, no insert of any kind, pure render -- creates no row. */
export async function previewLabel(client: LabelBarcodeMutationRpcClient, input: PreviewLabelInput): Promise<string> {
  const parsedInput = PreviewLabelInputSchema.parse(input);
  const { data, error } = await client.rpc("preview_label", {
    p_template_version_id: parsedInput.templateVersionId,
    p_variables: parsedInput.variables ?? {},
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  if (typeof data !== "string") {
    throw new LabelBarcodeMutationError("invalid_response", "preview_label returned a non-string result");
  }
  return data;
}

/** Creates exactly one label_instances row per logical label. Idempotent on (tenantId, idempotencyKey). */
export async function generateLabel(client: LabelBarcodeMutationRpcClient, input: GenerateLabelInput): Promise<LabelInstance> {
  const parsedInput = GenerateLabelInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_label", {
    p_tenant_id: parsedInput.tenantId,
    p_template_code: parsedInput.templateCode,
    p_subject_type: parsedInput.subjectType,
    p_subject_id: parsedInput.subjectId,
    p_variables: parsedInput.variables ?? {},
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parseInstanceResponse(data, "generate_label");
}

/** OPS:Edit-gated (routine staff print action). Enqueues a real app.jobs row (job_type=print_label). Idempotent on (tenantId via the label's own tenant, idempotencyKey). */
export async function printLabel(client: LabelBarcodeMutationRpcClient, input: PrintLabelInput): Promise<LabelPrintJob> {
  const parsedInput = PrintLabelInputSchema.parse(input);
  const { data, error } = await client.rpc("print_label", {
    p_label_instance_id: parsedInput.labelInstanceId,
    p_printer_id: parsedInput.printerId,
    p_copies: parsedInput.copies,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parsePrintJobResponse(data, "print_label");
}

/** OPS:Override-gated (a governed reprint action). Requires a non-empty reason. Preserves the SAME label instance -- never creates a second one. */
export async function reprintLabel(client: LabelBarcodeMutationRpcClient, input: ReprintLabelInput): Promise<LabelPrintJob> {
  const parsedInput = ReprintLabelInputSchema.parse(input);
  const { data, error } = await client.rpc("reprint_label", {
    p_label_instance_id: parsedInput.labelInstanceId,
    p_printer_id: parsedInput.printerId,
    p_copies: parsedInput.copies,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parsePrintJobResponse(data, "reprint_label");
}

/** OPS:Override-gated. Rejects if already void (already_void). Once void, print/reprint reject label_voided. */
export async function voidLabel(client: LabelBarcodeMutationRpcClient, input: VoidLabelInput): Promise<LabelInstance> {
  const parsedInput = VoidLabelInputSchema.parse(input);
  const { data, error } = await client.rpc("void_label", {
    p_label_instance_id: parsedInput.labelInstanceId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parseInstanceResponse(data, "void_label");
}

/**
 * service_role only -- a worker-side callback called AFTER a future worker has
 * already called the generic app.complete_job/app.record_job_failure (PLT-132). No
 * authenticated grant exists on the underlying RPC at all; this wrapper is intended
 * for server-side/worker code paths, never a browser client.
 */
export async function recordLabelPrintOutcome(client: LabelBarcodeMutationRpcClient, input: RecordLabelPrintOutcomeInput): Promise<LabelPrintJob> {
  const parsedInput = RecordLabelPrintOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_label_print_outcome", {
    p_label_print_job_id: parsedInput.labelPrintJobId,
    p_outcome_status: parsedInput.outcomeStatus,
    p_error: parsedInput.error ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  return parsePrintJobResponse(data, "record_label_print_outcome");
}

/**
 * THE flagship scan-resolution RPC. A barcode resolves a candidate label; it never
 * itself authorizes anything -- every resolution reauthorizes the caller's current
 * tenant/record scope against the LIVE subject row. Only a prior tenant-membership/
 * RBAC authority failure raises (LabelBarcodeMutationError); every ORDINARY rejection
 * (a malformed/forged code, an unknown code, a voided code, or a record-scope denial)
 * comes back as a normal LabelResolveResult with resolved=false and rejectionReason
 * set -- inspect that field, do not assume a resolved call always means success.
 */
export async function resolveLabel(client: LabelBarcodeMutationRpcClient, input: ResolveLabelInput): Promise<LabelResolveResult> {
  const parsedInput = ResolveLabelInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_label", {
    p_tenant_id: parsedInput.tenantId,
    p_encoded_value: parsedInput.encodedValue,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new LabelBarcodeMutationError(classifyError(error.message), error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeMutationError("invalid_response", "resolve_label returned no row");
  }
  return parseLabelResolveResult(row);
}
