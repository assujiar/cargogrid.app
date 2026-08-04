/**
 * Label and Barcode Operations read queries (ATW-021, CG-S10-ATW-021). Thin, typed
 * wrappers around app.get_label_template/app.list_label_templates/
 * app.list_label_template_versions/app.list_label_printers/app.get_label_instance/
 * app.list_label_instances/app.list_label_print_jobs/app.list_label_scan_events
 * (supabase/migrations/20260730290000_create_advanced_tms_label_barcode_operations.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLabelTemplate,
  parseLabelTemplateVersion,
  parseLabelPrinter,
  parseLabelInstance,
  parseLabelPrintJob,
  parseLabelScanEvent,
  type LabelTemplate,
  type LabelTemplateVersion,
  type LabelPrinter,
  type LabelInstance,
  type LabelPrintJob,
  type LabelScanEvent,
  type LabelSubjectType,
  type LabelTemplateVersionStatus,
  type LabelPrinterStatus,
  type LabelInstanceStatus,
  type LabelPrintJobStatus,
} from "../contracts/label-barcode/label-barcode.ts";

export type LabelBarcodeQueryClient = Pick<SupabaseClient, "rpc">;

export class LabelBarcodeQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LabelBarcodeQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC-gated (OPS:View). */
export async function getLabelTemplate(client: LabelBarcodeQueryClient, templateId: string, actorAuthUserId: string): Promise<LabelTemplate> {
  const { data, error } = await client.rpc("get_label_template", { p_template_id: templateId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeQueryError("get_label_template returned no row");
  }
  return parseLabelTemplate(row);
}

/** Bounded (default 50, hard-capped 200 server-side), tenant-wide. */
export async function listLabelTemplates(
  client: LabelBarcodeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { subjectTypeFilter?: LabelSubjectType | null; limit?: number },
): Promise<LabelTemplate[]> {
  const { data, error } = await client.rpc("list_label_templates", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_subject_type_filter: options?.subjectTypeFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLabelTemplate);
}

/** Bounded (default 50, hard-capped 200 server-side), one template's own versions. */
export async function listLabelTemplateVersions(
  client: LabelBarcodeQueryClient,
  templateId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: LabelTemplateVersionStatus | null; limit?: number },
): Promise<LabelTemplateVersion[]> {
  const { data, error } = await client.rpc("list_label_template_versions", {
    p_template_id: templateId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLabelTemplateVersion);
}

/** Bounded (default 50, hard-capped 200 server-side), tenant-wide, optionally warehouse-scoped. */
export async function listLabelPrinters(
  client: LabelBarcodeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; statusFilter?: LabelPrinterStatus | null; limit?: number },
): Promise<LabelPrinter[]> {
  const { data, error } = await client.rpc("list_label_printers", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLabelPrinter);
}

/** A direct lookup-by-id for an already-known label -- record-scope-gated, no scan-event logging (never use this to resolve a freshly scanned code; see mutations.resolveLabel for that). */
export async function getLabelInstance(client: LabelBarcodeQueryClient, labelInstanceId: string, actorAuthUserId: string): Promise<LabelInstance> {
  const { data, error } = await client.rpc("get_label_instance", { p_label_instance_id: labelInstanceId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LabelBarcodeQueryError("get_label_instance returned no row");
  }
  return parseLabelInstance(row);
}

/** Bounded (default 50, hard-capped 200 server-side), owner-scoped where owner_account_id is set. */
export async function listLabelInstances(
  client: LabelBarcodeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { subjectType?: LabelSubjectType | null; subjectId?: string | null; statusFilter?: LabelInstanceStatus | null; limit?: number },
): Promise<LabelInstance[]> {
  const { data, error } = await client.rpc("list_label_instances", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_subject_type: options?.subjectType ?? null,
    p_subject_id: options?.subjectId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLabelInstance);
}

/** Bounded (default 50, hard-capped 200 server-side), tenant-wide (staff-only operational table -- print/reprint are never customer-facing). */
export async function listLabelPrintJobs(
  client: LabelBarcodeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { labelInstanceId?: string | null; statusFilter?: LabelPrintJobStatus | null; limit?: number },
): Promise<LabelPrintJob[]> {
  const { data, error } = await client.rpc("list_label_print_jobs", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_label_instance_id: options?.labelInstanceId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLabelPrintJob);
}

/** Bounded (default 50, hard-capped 200 server-side), tenant-wide -- deliberately NOT owner-narrowed at the RPC layer (an audit trail of scan metadata only; see the migration's own design note 9). */
export async function listLabelScanEvents(
  client: LabelBarcodeQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { labelInstanceId?: string | null; limit?: number },
): Promise<LabelScanEvent[]> {
  const { data, error } = await client.rpc("list_label_scan_events", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_label_instance_id: options?.labelInstanceId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LabelBarcodeQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLabelScanEvent);
}
