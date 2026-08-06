import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorProfiles, VendorProfileQueryError } from "../../../../../server/queries/vendor-profile.ts";
import type { VendorLifecycleStatus } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VendorDirectoryPanel } from "./vendor-directory-panel.tsx";
import { createVendorProfileDraftAction } from "./actions.ts";

/**
 * Vendor directory (PRC-251, CG-S11-PRC-002) -- the first UI Phase 6 has ever built.
 * Cursor-paginated, server-filtered/searched (Prompt 251 §17: "no client-loaded full
 * dataset"). The onboarding wizard is folded into this same page as a create-draft
 * form rather than a separate multi-route wizard flow, a disclosed simplification --
 * every field the wizard needs (legal identity + category + payment term) is
 * collected in the one create_vendor_profile_draft call; contacts/addresses/services/
 * coverage are added afterward on the vendor's own detail page, matching the
 * database's own draft-then-enrich shape rather than a separate client-only wizard
 * state machine.
 */
export default async function VendorDirectoryPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string; q?: string; after?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status, q, after } = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as VendorLifecycleStatus) : null) ?? null;

  let loadFailed = false;
  let vendors: Awaited<ReturnType<typeof listVendorProfiles>> = [];
  try {
    vendors = await listVendorProfiles(supabase, access.tenant.id, access.authUserId, { statusFilter, search: q ?? null, limit: 50, afterCode: after ?? null });
  } catch (error) {
    if (!(error instanceof VendorProfileQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor directory. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendors</h1>
        <p className="text-xs text-neutral-500">Canonical vendor registration and onboarding. One vendor identity, reused across Commercial, Operations, and Finance.</p>
      </div>

      <VendorDirectoryPanel tenantSlug={tenantSlug} vendors={vendors} statusFilter={statusFilter} search={q ?? ""} createAction={createVendorProfileDraftAction.bind(null, tenantSlug)} />
    </div>
  );
}
