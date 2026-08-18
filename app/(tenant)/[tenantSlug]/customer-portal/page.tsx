import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerPortalScopePanel } from "./customer-portal-scope-panel.tsx";

/**
 * Customer portal scope-preview screen (CPL-300, CG-S13-CPL-002) -- this
 * checkpoint's own end-to-end proof of the scope primitive, not the full
 * dashboard (Prompt 301's own job, per the source prompt's own §15). Shows
 * the signed-in customer's own active account/site memberships (name, role,
 * status) via app.get_customer_portal_scope_context, an account/site switcher
 * when more than one is active, and a clear denied state for every non-
 * allowed guard outcome -- no data is fetched, let alone rendered, before the
 * guard resolves "allowed" server-side (source prompt's own explicit
 * requirement).
 *
 * State handling mirrors app/(tenant)/[tenantSlug]/admin/layout.tsx's own
 * established convention (PLT-135): unauthenticated -> redirect to sign-in
 * (never a page render); tenant_not_found/tenant_suspended/forbidden -> a
 * distinct denied state, deliberately not confirming/denying tenant
 * existence beyond what the viewer is already entitled to know.
 *
 * Carries `CustomerPortalNav` (CPL-301) so this page and the full dashboard
 * form one coherent portal shell -- see that component's own header for why
 * this is a shared presentational component rather than a `layout.tsx`
 * route-group restructuring.
 */
export default async function CustomerPortalPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={
          access.status === "tenant_suspended"
            ? "This organization's customer portal is currently unavailable."
            : "You don't have access to this organization's customer portal. Contact your account administrator if you believe this is a mistake."
        }
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let memberships: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];

  try {
    memberships = await getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="scope" />
        <ErrorState description="Something went wrong loading your account access. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="scope" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Your account access</h1>
        <p className="text-xs text-neutral-500">Every company/account/site you can act within, resolved from your own active membership grants -- never from a URL, filter, or payload.</p>
      </div>

      {memberships.length === 0 ? (
        <EmptyState
          title="No account access yet"
          description="You don't currently have an active membership on any account in this organization. Ask your account administrator to invite you."
        />
      ) : (
        <CustomerPortalScopePanel memberships={memberships} />
      )}
    </div>
  );
}
