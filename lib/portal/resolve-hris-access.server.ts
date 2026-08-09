/**
 * Request-memoized guard resolution (HRT-274, CG-S12-HRT-002). Same `React.cache()`
 * dedupe rationale as `resolve-procurement-access.server.ts` (PRC-251) -- the HRIS
 * layout and every nested employee page within one request share this one resolution.
 */

import { cache } from "react";
import { resolveHrisAccess, type HrisGuardResult } from "./hris-guard.ts";
import { buildHrisGuardDeps } from "./hris-guard-deps.server.ts";

export const resolveHrisAccessForRequest = cache(async (tenantSlug: string): Promise<HrisGuardResult> => {
  const deps = await buildHrisGuardDeps();
  return resolveHrisAccess(deps, tenantSlug);
});
