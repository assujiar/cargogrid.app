/**
 * Request-memoized guard resolution (CPL-300, CG-S13-CPL-002). Same
 * `React.cache()` dedupe rationale as lib/portal/resolve-customer-ticket-access.server.ts.
 */

import { cache } from "react";
import { resolveCustomerPortalAccess, type CustomerPortalGuardResult } from "./customer-portal-guard.ts";
import { buildCustomerPortalGuardDeps } from "./customer-portal-guard-deps.server.ts";

export const resolveCustomerPortalAccessForRequest = cache(async (tenantSlug: string): Promise<CustomerPortalGuardResult> => {
  const deps = await buildCustomerPortalGuardDeps();
  return resolveCustomerPortalAccess(deps, tenantSlug);
});
