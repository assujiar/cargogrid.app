/**
 * Vendor Rate and Pricelist extension mutation primitives (PRC-255, CG-S11-PRC-006).
 * Thin, typed wrappers around the new/widened RPCs
 * supabase/migrations/20260730620000_extend_commercial_vendor_rate_for_procurement.sql
 * adds on top of COM-149's own canonical rate engine.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  AddVendorRateTierInputSchema,
  RemoveVendorRateTierInputSchema,
  CalculateVendorRateInputSchema,
  CommitVendorRateImportJobInputSchema,
  ValidateVendorRateImportRowInputSchema,
  parseVendorRateTier,
  parseVendorRateCalculation,
  type AddVendorRateTierInput,
  type RemoveVendorRateTierInput,
  type CalculateVendorRateInput,
  type CommitVendorRateImportJobInput,
  type ValidateVendorRateImportRowInput,
  type VendorRateTier,
  type VendorRateCalculation,
} from "../contracts/procurement-rate/procurement-rate.ts";
import {
  CreateRateVersionInputSchema,
  SelectVendorRateInputSchema,
  parseRateVersionRecord,
  parseRateSelection,
  type CreateRateVersionInput,
  type SelectVendorRateInput,
  type RateVersionRecord,
  type RateSelection,
} from "../contracts/rate/rate.ts";
import type { VendorRateProcurementLink, VendorRateSelectionCalculationInputs } from "../contracts/procurement-rate/procurement-rate.ts";

export type ProcurementRateMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PROCUREMENT_RATE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "rate_version_not_found",
  "vendor_rate_version_not_found",
  "vendor_rate_version_not_editable",
  "vendor_rate_tier_not_found",
  "vendor_master_record_not_found",
  "invalid_vendor_identity",
  "tenant_mismatch",
  "invalid_transition",
  "stale_version",
  "vendor_not_active",
  "ambiguous_overlap",
  "tier_overlap",
  "tier_gap",
  "invalid_tier_order",
  "invalid_tier_amount",
  "invalid_tier_range",
  "invalid_tier_weight_range",
  "invalid_tier_volume_range",
  "invalid_tier_minimum_charge",
  "duplicate_tier_order",
  "idempotency_key_conflict",
  "invalid_quantity",
  "reason_required",
  "invalid_adhoc_rate",
  "costing_request_not_found",
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
  "import_vendor_master_not_found",
  "job_actor_unauthorized",
] as const;
type KnownProcurementRateMutationErrorCode = (typeof PROCUREMENT_RATE_KNOWN_MUTATION_ERROR_CODES)[number];
export type ProcurementRateMutationErrorCode = KnownProcurementRateMutationErrorCode | "mutation_failed" | "invalid_response";

export class ProcurementRateMutationError extends Error {
  readonly code: ProcurementRateMutationErrorCode;

  constructor(code: ProcurementRateMutationErrorCode, message: string) {
    super(message);
    this.name = "ProcurementRateMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ProcurementRateMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PROCUREMENT_RATE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownProcurementRateMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: ProcurementRateMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ProcurementRateMutationError(classifyError(error.message), error.message);
  }
  return data;
}

/** Create (or revise) a vendor rate, additionally linking it to the real Procurement vendor identity (ADR-0020) and/or lead-time/capacity terms. Composes server/mutations/rate.ts's own input shape with the three new optional trailing fields -- never a competing/duplicated create function. */
export async function createProcurementRateVersion(
  client: ProcurementRateMutationRpcClient,
  input: CreateRateVersionInput & Partial<VendorRateProcurementLink>,
): Promise<RateVersionRecord> {
  const parsedBase = CreateRateVersionInputSchema.parse(input);
  const data = await callRpc(client, "create_rate_version", {
    p_tenant_id: parsedBase.tenantId,
    p_vendor_code: parsedBase.vendorCode,
    p_vendor_name: parsedBase.vendorName,
    p_service_type: parsedBase.serviceType,
    p_mode: parsedBase.mode,
    p_origin_lane: parsedBase.originLane,
    p_destination_lane: parsedBase.destinationLane,
    p_equipment_type: parsedBase.equipmentType,
    p_cargo_weight_min: parsedBase.cargoWeightMin,
    p_cargo_weight_max: parsedBase.cargoWeightMax,
    p_cargo_volume_min: parsedBase.cargoVolumeMin,
    p_cargo_volume_max: parsedBase.cargoVolumeMax,
    p_currency: parsedBase.currency,
    p_base_amount: parsedBase.baseAmount,
    p_minimum_amount: parsedBase.minimumAmount,
    p_surcharge_components: parsedBase.surchargeComponents,
    p_effective_from: parsedBase.effectiveFrom,
    p_effective_to: parsedBase.effectiveTo,
    p_supersedes_version_id: parsedBase.supersedesVersionId,
    p_actor_auth_user_id: parsedBase.actorAuthUserId,
    p_actor_label: parsedBase.actorLabel,
    p_vendor_master_id: input.vendorMasterId ?? null,
    p_lead_time_days: input.leadTimeDays ?? null,
    p_capacity_terms: input.capacityTerms ?? null,
    p_source_import_staging_row_id: null,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementRateMutationError("invalid_response", "create_rate_version returned no row");
  }
  return parseRateVersionRecord(data as Record<string, unknown>);
}

// Approving a rate version (pending_approval -> approved) now ALSO validates the
// linked-vendor lifecycle_status=active, tier contiguity, and cross-version overlap
// (PRC-255) -- but the RPC's own signature/authority is unchanged, so callers use
// server/mutations/rate.ts's own `approveRateVersion` directly; no wrapper is
// duplicated here.

/** Snapshots the selected rate, optionally computing the exact tier-matched amount when weight/volume/quantity are supplied (PRC-255). Composes server/mutations/rate.ts's own input shape. */
export async function selectProcurementVendorRate(
  client: ProcurementRateMutationRpcClient,
  input: SelectVendorRateInput & Partial<VendorRateSelectionCalculationInputs>,
): Promise<RateSelection> {
  const parsedBase = SelectVendorRateInputSchema.parse(input);
  const data = await callRpc(client, "select_vendor_rate", {
    p_costing_request_id: parsedBase.costingRequestId,
    p_rate_version_id: parsedBase.rateVersionId,
    p_is_adhoc: parsedBase.isAdhoc,
    p_adhoc_currency: parsedBase.adhocCurrency,
    p_adhoc_amount: parsedBase.adhocAmount,
    p_override_reason: parsedBase.overrideReason,
    p_actor_auth_user_id: parsedBase.actorAuthUserId,
    p_actor_label: parsedBase.actorLabel,
    p_weight: input.weight ?? null,
    p_volume: input.volume ?? null,
    p_quantity: input.quantity ?? null,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementRateMutationError("invalid_response", "select_vendor_rate returned no row");
  }
  return parseRateSelection(data as Record<string, unknown>);
}

/** Adds a weight/volume pricing tier to a pending_approval rate version. Requires PRC:Edit. Idempotency-key replay compares every load-bearing field. */
export async function addVendorRateTier(client: ProcurementRateMutationRpcClient, input: AddVendorRateTierInput): Promise<VendorRateTier> {
  const parsedInput = AddVendorRateTierInputSchema.parse(input);
  const data = await callRpc(client, "add_vendor_rate_tier", {
    p_rate_version_id: parsedInput.rateVersionId,
    p_tier_order: parsedInput.tierOrder,
    p_weight_min: parsedInput.weightMin,
    p_weight_max: parsedInput.weightMax,
    p_volume_min: parsedInput.volumeMin,
    p_volume_max: parsedInput.volumeMax,
    p_amount: parsedInput.amount,
    p_minimum_charge: parsedInput.minimumCharge,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementRateMutationError("invalid_response", "add_vendor_rate_tier returned no row");
  }
  return parseVendorRateTier(data as Record<string, unknown>);
}

/** Removes a tier from a pending_approval rate version. Requires PRC:Edit and the tier's current record_version. */
export async function removeVendorRateTier(client: ProcurementRateMutationRpcClient, input: RemoveVendorRateTierInput): Promise<void> {
  const parsedInput = RemoveVendorRateTierInputSchema.parse(input);
  await callRpc(client, "remove_vendor_rate_tier", {
    p_tier_id: parsedInput.tierId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Read-only, no side effect (RPD-040): the exact computed amount plus the full snapshot inputs/components/rounding. Requires PRC:View cost. */
export async function calculateVendorRate(client: ProcurementRateMutationRpcClient, input: CalculateVendorRateInput): Promise<VendorRateCalculation> {
  const parsedInput = CalculateVendorRateInputSchema.parse(input);
  const data = await callRpc(client, "calculate_vendor_rate", {
    p_rate_version_id: parsedInput.rateVersionId,
    p_weight: parsedInput.weight,
    p_volume: parsedInput.volume,
    p_quantity: parsedInput.quantity,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (!Array.isArray(data) || data.length === 0) {
    throw new ProcurementRateMutationError("invalid_response", "calculate_vendor_rate returned no row");
  }
  return parseVendorRateCalculation(data[0] as Record<string, unknown>);
}

/** Server-mediated only (service_role client) -- validates one staged vendor_rate_import row, rejecting (never silently stripping) any formula/spreadsheet-injection-shaped text field. */
export async function validateVendorRateImportRow(client: ProcurementRateMutationRpcClient, input: ValidateVendorRateImportRowInput): Promise<Record<string, unknown>> {
  const parsedInput = ValidateVendorRateImportRowInputSchema.parse(input);
  const data = await callRpc(client, "validate_vendor_rate_import_row", {
    p_staging_row_id: parsedInput.stagingRowId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementRateMutationError("invalid_response", "validate_vendor_rate_import_row returned no row");
  }
  return data as Record<string, unknown>;
}

/** Server-mediated only (service_role client) -- the first real domain-write adapter for PLT-131 (ISS-2026-013). Requires both is_support_grant_authority and PRC:Import. Idempotent-safe to retry. */
export async function commitVendorRateImportJob(client: ProcurementRateMutationRpcClient, input: CommitVendorRateImportJobInput): Promise<Record<string, unknown>> {
  const parsedInput = CommitVendorRateImportJobInputSchema.parse(input);
  const data = await callRpc(client, "commit_vendor_rate_import_job", {
    p_job_id: parsedInput.jobId,
    p_allow_partial: parsedInput.allowPartial,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new ProcurementRateMutationError("invalid_response", "commit_vendor_rate_import_job returned no row");
  }
  return data as Record<string, unknown>;
}
