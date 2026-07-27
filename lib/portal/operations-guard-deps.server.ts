/**
 * Real `OperationsGuardDeps` wiring (OPS-168, CG-S8-OPS-002). Identical in shape to
 * `commercial-guard-deps.server.ts`'s own delegation -- reused directly rather than
 * re-authoring the same Supabase wiring twice; only the pure guard logic that
 * *interprets* the resolved layer lives in a separate file (`operations-guard.ts`).
 */

import { buildTenantAdminGuardDeps } from "./tenant-admin-guard-deps.server.ts";
import type { OperationsGuardDeps } from "./operations-guard.ts";

export async function buildOperationsGuardDeps(): Promise<OperationsGuardDeps> {
  return buildTenantAdminGuardDeps();
}
