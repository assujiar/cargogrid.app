/**
 * Request-memoized Supreme Admin guard resolution (PLT-136, CG-S6-PLT-033). Mirrors
 * `resolve-tenant-admin-access.server.ts` -- `React.cache()` dedupes this call across
 * the Supreme layout and every nested page within one request/render pass.
 */

import { cache } from "react";
import { resolveSupremeAdminAccess, type SupremeAdminGuardResult } from "./supreme-admin-guard.ts";
import { buildSupremeAdminGuardDeps } from "./supreme-admin-guard-deps.server.ts";

export const resolveSupremeAdminAccessForRequest = cache(async (): Promise<SupremeAdminGuardResult> => {
  const deps = await buildSupremeAdminGuardDeps();
  return resolveSupremeAdminAccess(deps);
});
