/**
 * Tenant lifecycle service (PLT-105, CG-S6-PLT-002). A thin, typed wrapper around the
 * two Postgres RPC functions supabase/migrations/20260716075355_create_tenants.sql
 * defines (app.provision_tenant, app.transition_tenant_status) — the actual
 * transactional/idempotency/state-machine logic lives in the database (proven for
 * real against a live Postgres instance in scripts/db-tests/tenant-lifecycle.sql),
 * not reimplemented here.
 *
 * Takes its client as a parameter (dependency injection) rather than importing a
 * singleton — no live Supabase project exists yet (Supabase Auth integration is
 * PLT-107, a later capability); this keeps the service real and fully testable today
 * without inventing a fake global client. `TenantRpcClient` is a minimal structural
 * subset of `SupabaseClient` — a real `@supabase/supabase-js` client satisfies it
 * without any adapter.
 *
 * Security posture (docs/standards/SECURITY_STANDARDS.md §2): a raw database error
 * is never returned to the caller — TenantServiceError carries a fixed, safe `code`
 * plus the database's own message (already safe: it originates from this repository's
 * own trigger/function RAISE EXCEPTION text, not a leaked internal detail), never a
 * raw driver/connection-string/stack-trace value.
 */

import {
  ProvisionTenantInputSchema,
  TransitionTenantInputSchema,
  parseTenantRow,
  type ProvisionTenantInput,
  type Tenant,
  type TransitionTenantInput,
} from "../contracts/tenant/tenant.ts";

export interface TenantRpcClient {
  rpc(
    fn: "provision_tenant" | "transition_tenant_status",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string; code?: string } | null }>;
}

export type TenantServiceErrorCode = "provision_failed" | "transition_failed" | "invalid_response";

export class TenantServiceError extends Error {
  readonly code: TenantServiceErrorCode;

  constructor(code: TenantServiceErrorCode, message: string) {
    super(message);
    this.name = "TenantServiceError";
    this.code = code;
  }
}

export async function provisionTenant(client: TenantRpcClient, input: ProvisionTenantInput): Promise<Tenant> {
  const parsedInput = ProvisionTenantInputSchema.parse(input);

  const { data, error } = await client.rpc("provision_tenant", {
    p_slug: parsedInput.slug,
    p_name: parsedInput.name,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_requested_by: parsedInput.requestedBy,
    p_plan_snapshot: parsedInput.planSnapshot ?? {},
  });

  if (error) {
    throw new TenantServiceError("provision_failed", error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TenantServiceError("invalid_response", "provision_tenant returned no row");
  }
  return parseTenantRow(data as Record<string, unknown>);
}

export async function transitionTenantStatus(client: TenantRpcClient, input: TransitionTenantInput): Promise<Tenant> {
  const parsedInput = TransitionTenantInputSchema.parse(input);

  const { data, error } = await client.rpc("transition_tenant_status", {
    p_tenant_id: parsedInput.tenantId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_requested_by: parsedInput.requestedBy,
  });

  if (error) {
    throw new TenantServiceError("transition_failed", error.message);
  }
  if (!data || typeof data !== "object") {
    throw new TenantServiceError("invalid_response", "transition_tenant_status returned no row");
  }
  return parseTenantRow(data as Record<string, unknown>);
}
