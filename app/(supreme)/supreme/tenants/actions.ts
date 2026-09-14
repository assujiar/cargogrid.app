"use server";

/**
 * Tenant provisioning Server Action (audit remediation A2;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A2:
 * "A tenant cannot be created ... no code path anywhere calls
 * app.provision_tenant"). `provisionTenant` (`server/mutations/tenant.ts`,
 * PLT-105) already existed, fully implemented and tested against a live
 * Postgres instance (`scripts/db-tests/tenant-lifecycle.sql`) -- this closes
 * the missing caller, not new business logic.
 *
 * The idempotency key is derived from the slug (`provision-tenant:{slug}`)
 * rather than generated fresh per submit: `app.provision_tenant`'s own
 * contract (20260716075355_create_tenants.sql) is "retry with the same
 * idempotency key returns the original row, never a duplicate" -- a
 * per-submit random key would defeat that guarantee for the one case it
 * exists to cover (an accidental double-submit of this exact form). A
 * different slug is naturally a different key; a retry of a slug that
 * already failed before insert finds nothing and proceeds normally.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveSupremeAdminAccessForRequest } from "../../../../lib/portal/resolve-supreme-admin-access.server.ts";
import { provisionTenant, toTenantRpcClient, TenantServiceError } from "../../../../server/mutations/tenant.ts";

export interface CreateTenantActionState {
  readonly error: string | null;
}

const OK: CreateTenantActionState = { error: null };
const NO_ACCESS: CreateTenantActionState = { error: "You don't have access to create tenants." };

export async function createTenantAction(_prevState: CreateTenantActionState, formData: FormData): Promise<CreateTenantActionState> {
  const access = await resolveSupremeAdminAccessForRequest();
  if (access.status !== "allowed") return NO_ACCESS;

  const slug = String(formData.get("slug") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await provisionTenant(toTenantRpcClient(supabase), {
      slug,
      name,
      idempotencyKey: `provision-tenant:${slug}`,
      requestedBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TenantServiceError) return { error: `Could not create this tenant: ${error.message}` };
    throw error;
  }

  revalidatePath(`/supreme/tenants`);
  return OK;
}
