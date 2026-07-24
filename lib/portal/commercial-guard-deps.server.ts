/**
 * Real `CommercialGuardDeps` wiring (COM-143, CG-S7-COM-002). Identical in shape to
 * `tenant-admin-guard-deps.server.ts`'s own three dependencies (current-user lookup,
 * tenant-by-slug lookup, `app.resolve_access_context` via the service-role client) --
 * reused directly rather than re-authoring the same Supabase wiring twice; only the
 * pure guard logic that *interprets* the resolved layer differs (`commercial-guard.ts`
 * accepts `tenant_admin` and `org_user`, `tenant-admin-guard.ts` accepts only `tenant_admin`).
 */

import { buildTenantAdminGuardDeps } from "./tenant-admin-guard-deps.server.ts";
import type { CommercialGuardDeps } from "./commercial-guard.ts";

export async function buildCommercialGuardDeps(): Promise<CommercialGuardDeps> {
  return buildTenantAdminGuardDeps();
}
