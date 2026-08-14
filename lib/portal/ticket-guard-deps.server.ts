/**
 * Real `TicketGuardDeps` wiring (HRT-286, CG-S12-HRT-014). Identical in shape
 * to `hris-guard-deps.server.ts`/`procurement-guard-deps.server.ts`'s own
 * delegation -- reused directly rather than re-authoring the same Supabase
 * wiring twice.
 */

import { buildTenantAdminGuardDeps } from "./tenant-admin-guard-deps.server.ts";
import type { TicketGuardDeps } from "./ticket-guard.ts";

export async function buildTicketGuardDeps(): Promise<TicketGuardDeps> {
  return buildTenantAdminGuardDeps();
}
