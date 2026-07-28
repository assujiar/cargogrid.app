/**
 * Real `FinanceGuardDeps` wiring (FIN-191, CG-S9-FIN-002). Identical in shape to
 * `commercial-guard-deps.server.ts`/`operations-guard-deps.server.ts`'s own three
 * dependencies (current-user lookup, tenant-by-slug lookup, `app.resolve_access_context`
 * via the service-role client) -- reused directly rather than re-authoring the same
 * Supabase wiring a third time; only the pure guard logic that *interprets* the
 * resolved layer differs (`finance-guard.ts` accepts `tenant_admin` and `org_user`,
 * the same set `commercial-guard.ts`/`operations-guard.ts` already accept).
 */

import { buildTenantAdminGuardDeps } from "./tenant-admin-guard-deps.server.ts";
import type { FinanceGuardDeps } from "./finance-guard.ts";

export async function buildFinanceGuardDeps(): Promise<FinanceGuardDeps> {
  return buildTenantAdminGuardDeps();
}
