/**
 * Request-memoized guard resolution (HRT-287, CG-S12-HRT-015). Same
 * `React.cache()` dedupe rationale as `resolve-ticket-access.server.ts`.
 */

import { cache } from "react";
import { resolveCustomerTicketAccess, type CustomerTicketGuardResult } from "./customer-ticket-guard.ts";
import { buildCustomerTicketGuardDeps } from "./customer-ticket-guard-deps.server.ts";

export const resolveCustomerTicketAccessForRequest = cache(async (tenantSlug: string): Promise<CustomerTicketGuardResult> => {
  const deps = await buildCustomerTicketGuardDeps();
  return resolveCustomerTicketAccess(deps, tenantSlug);
});
