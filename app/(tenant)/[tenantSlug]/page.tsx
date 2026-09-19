import { redirect } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../lib/portal/resolve-commercial-access.server.ts";
import { resolveSignedInUserLabelForRequest } from "../../../lib/auth/resolve-signed-in-user-label.server.ts";
import { createSupabaseServerClient } from "../../../lib/supabase/server.ts";
import { listPendingApprovalStepsForActor, getApprovalRequestById, ApprovalQueryError } from "../../../server/queries/approval.ts";
import { toApprovalQueryRpcClient } from "../../../server/queries/procurement-approval.ts";
import type { ApprovalRequestStep } from "../../../server/contracts/approval/approval.ts";
import { AccountMenu } from "../../../components/layout/account-menu.tsx";
import { TenantPortalNav } from "../../../components/domain/tenant-portal-nav.tsx";
import { TenantMain } from "../../../components/layout/tenant-main.tsx";
import { ErrorState } from "../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../components/ui/empty-state.tsx";
import { Link } from "../../../components/ui/link.tsx";

/**
 * Tenant Internal Portal Home (audit remediation A1;
 * `docs/blueprint/03_CargoGrid_UX_Data_Access_Design.md` §6/§8 TNT-HOM-001
 * "Internal Home Dashboard": role-based work queue, quick actions, pending
 * approvals). Closes the confirmed 404 at the bare tenant root -- no
 * `page.tsx` existed at `app/(tenant)/[tenantSlug]/` at all, and
 * `signInAction` unconditionally redirected every signed-in tenant member
 * to `/{tenantSlug}/admin`, which requires `tenant_admin` layer and 403s
 * for any ordinary `org_user`.
 *
 * Scope: a real quick-links grid into every module `TenantPortalNav`
 * exposes, plus a genuine cross-domain "pending approvals" summary via
 * `listPendingApprovalStepsForActor` -- the one piece of TNT-HOM-001 with an
 * existing, tested, cross-domain read model behind it today
 * (`app.approval_requests`/`app.approval_request_steps` are shared across
 * Commercial/Procurement/HRIS, not domain-scoped). A full role-based
 * KPI/widget dashboard (the rest of TNT-HOM-001's own scope) has no
 * aggregation layer built yet and stays future work rather than being
 * faked here. Reuses `resolveCommercialAccessForRequest`, the same
 * domain-agnostic "any active tenant member" guard every other cross-domain
 * surface (`reports/`, `dashboards/`, `analytics/`, ...) already
 * established.
 */
export default async function TenantHomePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <main id="main-content" tabIndex={-1} className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-4 text-center">
        <h1 className="text-xl font-semibold text-neutral-900">Access denied</h1>
        <p className="text-sm text-neutral-600">
          {access.status === "tenant_suspended"
            ? "This organization's account is currently suspended."
            : "You don't have access to this organization."}
        </p>
        <a href="/login" className="text-sm font-medium text-primary underline">
          Sign in with a different account
        </a>
      </main>
    );
  }

  const signedInUserLabel = await resolveSignedInUserLabelForRequest();
  const supabase = await createSupabaseServerClient();

  let pendingSteps: ApprovalRequestStep[] = [];
  let pendingEntityTypes = new Map<string, string>();
  let approvalsLoadFailed = false;
  try {
    const approvalClient = toApprovalQueryRpcClient(supabase);
    pendingSteps = await listPendingApprovalStepsForActor(approvalClient, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    const requestIds = [...new Set(pendingSteps.map((step) => step.requestId))].slice(0, 20);
    const requests = await Promise.all(requestIds.map((requestId) => getApprovalRequestById(approvalClient, requestId)));
    pendingEntityTypes = new Map(requests.filter((request) => request !== null).map((request) => [request.id, request.entityType]));
  } catch (error) {
    if (!(error instanceof ApprovalQueryError)) {
      throw error;
    }
    approvalsLoadFailed = true;
  }

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-neutral-200 bg-neutral-50">
        <div className="flex items-center justify-between px-6 py-3">
          <span className="text-sm font-semibold text-neutral-900">CargoGrid — {access.tenant.slug}</span>
          <div className="flex items-center gap-4">
            <TenantPortalNav tenantSlug={access.tenant.slug} current="home" />
            {signedInUserLabel ? <AccountMenu name={signedInUserLabel} /> : null}
          </div>
        </div>
      </header>
      <TenantMain>
        <div className="flex flex-col gap-8">
          <section aria-labelledby="pending-approvals-heading" className="flex flex-col gap-3">
            <h2 id="pending-approvals-heading" className="text-base font-semibold text-neutral-900">
              Your pending approvals
            </h2>
            {approvalsLoadFailed ? (
              <ErrorState description="Something went wrong loading your pending approvals. Please try again." />
            ) : pendingSteps.length === 0 ? (
              <EmptyState title="No pending approvals" description="Nothing is waiting on your decision right now." />
            ) : (
              <ul className="flex flex-col divide-y divide-neutral-200 rounded-md border border-neutral-200">
                {pendingSteps.map((step) => (
                  <li key={step.id} className="flex items-center justify-between px-4 py-3 text-sm">
                    <span className="text-neutral-900">{pendingEntityTypes.get(step.requestId) ?? "Approval request"}</span>
                    <span className="text-neutral-600">
                      Step {step.stepOrder} · {step.approvalsCount}/{step.requiredApprovals} approved
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section aria-labelledby="modules-heading" className="flex flex-col gap-3">
            <h2 id="modules-heading" className="text-base font-semibold text-neutral-900">
              Modules
            </h2>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 md:grid-cols-4">
              {MODULE_QUICK_LINKS.map((module) => (
                <Link key={module.path} href={`/${access.tenant.slug}${module.path}`} className="rounded-md border border-neutral-200 px-4 py-3 text-sm font-medium hover:bg-neutral-50">
                  {module.label}
                </Link>
              ))}
            </div>
          </section>
        </div>
      </TenantMain>
    </div>
  );
}

const MODULE_QUICK_LINKS: ReadonlyArray<{ readonly label: string; readonly path: string }> = [
  { label: "Commercial", path: "/commercial/dashboard" },
  { label: "Operations", path: "/operations/dashboard" },
  { label: "Procurement", path: "/procurement" },
  { label: "Finance", path: "/finance" },
  { label: "HRIS", path: "/hris" },
  { label: "Tickets", path: "/tickets" },
  { label: "Helpdesk", path: "/helpdesk" },
  { label: "Knowledge base", path: "/knowledge-base" },
  { label: "Reports", path: "/reports" },
  { label: "Dashboards", path: "/dashboards" },
  { label: "Saved views", path: "/saved-views" },
  { label: "Scheduled reports", path: "/scheduled-reports" },
  { label: "Analytics", path: "/analytics" },
  { label: "Automation rules", path: "/automation-rules" },
  { label: "Integrations", path: "/integrations" },
  { label: "Admin", path: "/admin" },
];
