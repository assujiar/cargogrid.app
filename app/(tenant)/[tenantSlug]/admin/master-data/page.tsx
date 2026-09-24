import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { MasterDataMergePanel } from "./master-data-merge-panel.tsx";

/**
 * Master-data merge/dedup entry (CG-AUDIT-2026-09-02 UNTRACKED-A1's own sibling
 * finding, discovered alongside the audit's own A1 paragraph). `app.merge_master_records`
 * (PLT-120) already existed as real, tested backend capability -- the only
 * deduplication path in the whole system -- with zero callers anywhere in `app/`. This
 * page closes that gap. `app.create_master_record`'s own generic wrapper is
 * deliberately NOT given a UI here: every currently-seeded master type (vendor,
 * vendor_rate, fleet, vehicle, driver, employee) already has its own dedicated,
 * tested, wired domain-specific creation path that calls `app.create_master_record`
 * internally (vendor intake, vehicle/driver registration, employee onboarding, etc.) --
 * there is no live domain today with an unmet creation need that would route through
 * a second, generic "create any master record" form.
 */
export default async function TenantAdminMasterDataPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Master data</h1>
      <p className="text-sm text-neutral-600">Merge duplicate vendor, vehicle, driver, employee, fleet, or vendor-rate records that refer to the same real-world entity.</p>
      <MasterDataMergePanel tenantSlug={tenantSlug} />
    </div>
  );
}
