/**
 * Cashback, Discount and Voucher mutation primitives (CPL-319,
 * CG-S13-CPL-021). Thin, typed wrappers around every write RPC in
 * supabase/migrations/20260801210000_create_customer_portal_cashback_
 * discount_voucher.sql. Unlike every prior Loyalty-domain mutations file
 * (CPL-316/317/318, all explicitly staff/system-only), `redeemLoyaltyBenefitEntitlement`
 * is genuinely reachable from a CUSTOMER-FACING Server Action too -- the
 * FIRST customer-initiated Loyalty write in this repository (migration's own
 * design decision 5). Every other export here remains staff/system-gated
 * (LYL:Edit/Configure) internally by its own RPC and should never be called
 * from a customer-facing Server Action.
 *
 * Mirrors server/mutations/customer-portal-loyalty-points.ts's own known-
 * error-code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyBenefitEntitlement,
  parseIssueLoyaltyBenefitEntitlementResult,
  IssueLoyaltyBenefitEntitlementInputSchema,
  RedeemLoyaltyBenefitEntitlementInputSchema,
  ReverseLoyaltyBenefitEntitlementInputSchema,
  ExpireLoyaltyBenefitEntitlementsInputSchema,
  HoldLoyaltyBenefitEntitlementInputSchema,
  ReleaseLoyaltyBenefitEntitlementHoldInputSchema,
  type IssueLoyaltyBenefitEntitlementInput,
  type RedeemLoyaltyBenefitEntitlementInput,
  type ReverseLoyaltyBenefitEntitlementInput,
  type ExpireLoyaltyBenefitEntitlementsInput,
  type HoldLoyaltyBenefitEntitlementInput,
  type ReleaseLoyaltyBenefitEntitlementHoldInput,
  type LoyaltyBenefitEntitlement,
  type IssueLoyaltyBenefitEntitlementResult,
} from "../contracts/customer-portal-loyalty-benefits/customer-portal-loyalty-benefits.ts";

export type LoyaltyBenefitsMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_BENEFITS_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_benefit_type",
  "invalid_value_amount",
  "invalid_value_cap",
  "value_exceeds_cap",
  "invalid_currency",
  "invalid_source_type",
  "invalid_expires_at",
  "invalid_idempotency_key",
  "loyalty_account_not_found",
  "loyalty_benefit_entitlement_not_found",
  "invalid_entitlement_reference",
  "invalid_transition",
  "entitlement_expired",
  "entitlement_not_held",
  "voucher_redemption_failed",
  "reason_required",
  "stale_version",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyBenefitsMutationErrorCode = (typeof LOYALTY_BENEFITS_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyBenefitsMutationErrorCode = KnownLoyaltyBenefitsMutationErrorCode | "mutation_failed";

export class LoyaltyBenefitsMutationError extends Error {
  readonly code: LoyaltyBenefitsMutationErrorCode;

  constructor(code: LoyaltyBenefitsMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyBenefitsMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyBenefitsMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_BENEFITS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyBenefitsMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LoyaltyBenefitsMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyBenefitsMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyBenefitsMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

// ===========================================================================
// Issuance (staff/system, LYL:Edit)
// ===========================================================================

/** Idempotent on (tenantId, idempotencyKey). value_cap is enforced both here (Zod refine, client-side convenience) and authoritatively in the database. For benefit_type=voucher, returns the RAW code exactly once -- rawCode is null on every idempotent replay (never recoverable after the first, real issuance). */
export async function issueLoyaltyBenefitEntitlement(client: LoyaltyBenefitsMutationRpcClient, input: IssueLoyaltyBenefitEntitlementInput): Promise<IssueLoyaltyBenefitEntitlementResult> {
  const v = IssueLoyaltyBenefitEntitlementInputSchema.parse(input);
  return callRpc(
    client,
    "issue_loyalty_benefit_entitlement",
    {
      p_tenant_id: v.tenantId,
      p_loyalty_account_id: v.loyaltyAccountId,
      p_benefit_type: v.benefitType,
      p_value_amount: v.valueAmount,
      p_value_cap: v.valueCap,
      p_currency: v.currency,
      p_source_type: v.sourceType,
      p_source_id: v.sourceId,
      p_expires_at: v.expiresAt,
      p_idempotency_key: v.idempotencyKey,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
      p_config_version: v.configVersion,
    },
    parseIssueLoyaltyBenefitEntitlementResult,
  );
}

// ===========================================================================
// Redemption -- dual authority (staff LYL:Edit OR the entitlement's own
// owning customer). The FIRST customer-initiated Loyalty write in this
// repository (migration design decision 5).
// ===========================================================================

/** entitlementIdOrCode: either a real entitlement id (staff, or the owning customer from their own already-scoped wallet listing) or a raw voucher code (staff or any customer -- fully anti-enumerating: every failure mode collapses into the identical voucher_redemption_failed error). expectedVersion is nullable -- pass the row's own recordVersion when known (wallet button, staff admin by id); leave null for a bare typed-in code, where the atomic status=issued transition is itself the concurrency guard. */
export async function redeemLoyaltyBenefitEntitlement(client: LoyaltyBenefitsMutationRpcClient, input: RedeemLoyaltyBenefitEntitlementInput): Promise<LoyaltyBenefitEntitlement> {
  const v = RedeemLoyaltyBenefitEntitlementInputSchema.parse(input);
  return callRpc(
    client,
    "redeem_loyalty_benefit_entitlement",
    {
      p_tenant_id: v.tenantId,
      p_entitlement_id_or_code: v.entitlementIdOrCode,
      p_expected_version: v.expectedVersion,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyBenefitEntitlement,
  );
}

// ===========================================================================
// Reversal (staff, LYL:Configure -- governance-grade)
// ===========================================================================

/** NEVER deletes or edits history -- transitions status to reversed, preserving the row and its full event chain. Reversible from issued/held/redeemed. */
export async function reverseLoyaltyBenefitEntitlement(client: LoyaltyBenefitsMutationRpcClient, input: ReverseLoyaltyBenefitEntitlementInput): Promise<LoyaltyBenefitEntitlement> {
  const v = ReverseLoyaltyBenefitEntitlementInputSchema.parse(input);
  return callRpc(
    client,
    "reverse_loyalty_benefit_entitlement",
    {
      p_tenant_id: v.tenantId,
      p_entitlement_id: v.entitlementId,
      p_expected_version: v.expectedVersion,
      p_reason: v.reason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyBenefitEntitlement,
  );
}

// ===========================================================================
// Expiry scan (staff/system, LYL:Edit) -- batch, idempotent per row.
// ===========================================================================

export async function expireLoyaltyBenefitEntitlements(client: LoyaltyBenefitsMutationRpcClient, input: ExpireLoyaltyBenefitEntitlementsInput): Promise<LoyaltyBenefitEntitlement[]> {
  const v = ExpireLoyaltyBenefitEntitlementsInputSchema.parse(input);
  const { data, error } = await client.rpc("expire_loyalty_benefit_entitlements", {
    p_tenant_id: v.tenantId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
  if (error) throw new LoyaltyBenefitsMutationError(classifyError(error.message), error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLoyaltyBenefitEntitlement);
}

// ===========================================================================
// Fraud hold (staff, LYL:Configure -- governance-grade). Blocks redemption
// while held (structural, via the shared status column).
// ===========================================================================

/** Idempotent -- holding an already-held entitlement is a safe no-op preserving the ORIGINAL reason. */
export async function holdLoyaltyBenefitEntitlement(client: LoyaltyBenefitsMutationRpcClient, input: HoldLoyaltyBenefitEntitlementInput): Promise<LoyaltyBenefitEntitlement> {
  const v = HoldLoyaltyBenefitEntitlementInputSchema.parse(input);
  return callRpc(
    client,
    "hold_loyalty_benefit_entitlement",
    {
      p_tenant_id: v.tenantId,
      p_entitlement_id: v.entitlementId,
      p_reason: v.reason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyBenefitEntitlement,
  );
}

export async function releaseLoyaltyBenefitEntitlementHold(client: LoyaltyBenefitsMutationRpcClient, input: ReleaseLoyaltyBenefitEntitlementHoldInput): Promise<LoyaltyBenefitEntitlement> {
  const v = ReleaseLoyaltyBenefitEntitlementHoldInputSchema.parse(input);
  return callRpc(
    client,
    "release_loyalty_benefit_entitlement_hold",
    {
      p_tenant_id: v.tenantId,
      p_entitlement_id: v.entitlementId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyBenefitEntitlement,
  );
}
