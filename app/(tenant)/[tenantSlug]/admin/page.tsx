import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../lib/portal/resolve-tenant-admin-access.server.ts";

/**
 * Home dashboard shell (PLT-135, CG-S6-PLT-032, Prompt 135 §20 task 3's "bounded core
 * management flows"). Deliberately minimal -- a role-based welcome only, no module
 * tiles or widgets yet, since inventing dashboard content ahead of the data those
 * widgets would summarize (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §14's
 * atomic backlog places real cross-domain dashboard widgets behind each owning
 * domain's own phase) would be exactly the "dead button" business rule §24 forbids.
 * `resolveTenantAdminAccessForRequest` is request-memoized (`React.cache()`) so this
 * adds no extra round-trip beyond what the layout already resolved.
 */
export default async function TenantAdminHomePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);

  if (access.status !== "allowed") {
    notFound();
  }

  return (
    <div className="flex flex-col gap-2">
      <h1 className="text-xl font-semibold text-neutral-900">Welcome</h1>
      <p className="text-sm text-neutral-600">
        Signed in to <span className="font-medium text-neutral-900">{access.tenant.slug}</span> as Tenant Admin.
      </p>
    </div>
  );
}
