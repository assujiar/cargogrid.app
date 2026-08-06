/**
 * Real `ProcurementGuardDeps` wiring (PRC-251, CG-S11-PRC-002). Identical in shape to
 * `commercial-guard-deps.server.ts`'s own delegation -- reused directly rather than
 * re-authoring the same Supabase wiring twice; only the pure guard logic that
 * *interprets* the resolved layer lives in a separate file (`procurement-guard.ts`).
 */

import { buildTenantAdminGuardDeps } from "./tenant-admin-guard-deps.server.ts";
import type { ProcurementGuardDeps } from "./procurement-guard.ts";

export async function buildProcurementGuardDeps(): Promise<ProcurementGuardDeps> {
  return buildTenantAdminGuardDeps();
}
