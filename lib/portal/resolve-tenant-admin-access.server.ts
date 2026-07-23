/**
 * Request-memoized guard resolution (PLT-135, CG-S6-PLT-032). `React.cache()` dedupes
 * this call across the admin layout and every nested page within one request/render
 * pass -- without it, each Server Component that needs the resolved tenant/access
 * context would re-run the guard's own Supabase/RPC round-trips independently.
 */

import { cache } from "react";
import { resolveTenantAdminAccess, type TenantAdminGuardResult } from "./tenant-admin-guard.ts";
import { buildTenantAdminGuardDeps } from "./tenant-admin-guard-deps.server.ts";

export const resolveTenantAdminAccessForRequest = cache(async (tenantSlug: string): Promise<TenantAdminGuardResult> => {
  const deps = await buildTenantAdminGuardDeps();
  return resolveTenantAdminAccess(deps, tenantSlug);
});
