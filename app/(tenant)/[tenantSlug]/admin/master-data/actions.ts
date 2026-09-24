"use server";

/**
 * Master-data merge Server Actions (CG-AUDIT-2026-09-02 UNTRACKED-A1's own sibling
 * finding: `app.merge_master_records` -- the only deduplication path in the system --
 * already existed, fully implemented and tested, but had zero callers anywhere in
 * `app/`. `server/mutations/master-data.ts` is `service_role`-only (this file's own
 * migration's grants) -- the merge call below uses the service-role client, the
 * "explicit actor, service-role execution" pattern every other privileged mutation in
 * this repository already follows. The search/lookup call uses the ordinary RLS-scoped
 * client -- `app.search_master_records` is a plain `authenticated` grant.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { searchMasterRecords, toMasterDataQueryRpcClient, MasterDataQueryError } from "../../../../../server/queries/master-data.ts";
import { mergeMasterRecords, toMasterDataMutationRpcClient, MasterDataMutationError } from "../../../../../server/mutations/master-data.ts";
import type { MasterRecord } from "../../../../../server/contracts/master-data/master-data.ts";

export interface SearchMasterDataFormState {
  readonly error: string | null;
  readonly results: MasterRecord[];
}

export interface MergeMasterDataFormState {
  readonly error: string | null;
}

export async function searchMasterDataAction(tenantSlug: string, masterTypeCode: string, query: string): Promise<SearchMasterDataFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's admin area.", results: [] };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const results = await searchMasterRecords(toMasterDataQueryRpcClient(supabase), {
      masterTypeCode,
      tenantId: access.tenant.id,
      query: query.trim() || null,
      limit: 50,
      afterCode: null,
    });
    return { error: null, results };
  } catch (error) {
    if (error instanceof MasterDataQueryError) {
      return { error: `Could not search master records: ${error.message}`, results: [] };
    }
    throw error;
  }
}

/**
 * Marks `sourceId` merged into `targetId` (never deletes the source -- it stays a real,
 * retained, `canonical_status='merged'` row per `app.merge_master_records`' own header).
 * `app.merge_master_records` itself re-validates the same master type/tenant/active-
 * status invariants server-side regardless of what this action's own search UI already
 * filtered to.
 */
export async function mergeMasterDataAction(tenantSlug: string, sourceId: string, targetId: string, reason: string): Promise<MergeMasterDataFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's admin area." };
  }

  const client = toMasterDataMutationRpcClient(createSupabaseServiceRoleClient());
  try {
    await mergeMasterRecords(client, { sourceId, targetId, actorAuthUserId: access.authUserId, reason, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof MasterDataMutationError) {
      return { error: `Could not merge these records: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/master-data`);
  return { error: null };
}
