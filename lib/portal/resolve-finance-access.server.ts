/**
 * Request-memoized guard resolution (FIN-191, CG-S9-FIN-002). Same `React.cache()`
 * dedupe rationale as `resolve-commercial-access.server.ts` (COM-143) --
 * the Finance layout and every nested Finance page within one request share this
 * one resolution rather than each re-running the guard's own Supabase/RPC round-trips.
 */

import { cache } from "react";
import { resolveFinanceAccess, type FinanceGuardResult } from "./finance-guard.ts";
import { buildFinanceGuardDeps } from "./finance-guard-deps.server.ts";

export const resolveFinanceAccessForRequest = cache(async (tenantSlug: string): Promise<FinanceGuardResult> => {
  const deps = await buildFinanceGuardDeps();
  return resolveFinanceAccess(deps, tenantSlug);
});
