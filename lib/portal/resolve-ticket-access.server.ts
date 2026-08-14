/**
 * Request-memoized guard resolution (HRT-286, CG-S12-HRT-014). Same
 * `React.cache()` dedupe rationale as `resolve-hris-access.server.ts` --
 * the tickets layout and every nested page within one request share this one
 * resolution.
 */

import { cache } from "react";
import { resolveTicketAccess, type TicketGuardResult } from "./ticket-guard.ts";
import { buildTicketGuardDeps } from "./ticket-guard-deps.server.ts";

export const resolveTicketAccessForRequest = cache(async (tenantSlug: string): Promise<TicketGuardResult> => {
  const deps = await buildTicketGuardDeps();
  return resolveTicketAccess(deps, tenantSlug);
});
