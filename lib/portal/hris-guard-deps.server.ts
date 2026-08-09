/**
 * Real `HrisGuardDeps` wiring (HRT-274, CG-S12-HRT-002). Identical in shape to
 * `procurement-guard-deps.server.ts`'s own delegation -- reused directly rather than
 * re-authoring the same Supabase wiring twice.
 */

import { buildTenantAdminGuardDeps } from "./tenant-admin-guard-deps.server.ts";
import type { HrisGuardDeps } from "./hris-guard.ts";

export async function buildHrisGuardDeps(): Promise<HrisGuardDeps> {
  return buildTenantAdminGuardDeps();
}
