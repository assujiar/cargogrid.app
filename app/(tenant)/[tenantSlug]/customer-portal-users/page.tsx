import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError, listCustomerPortalAccountMemberships } from "../../../../server/queries/customer-portal-scope.ts";
import { listCustomerPortalAccountMembershipsForAccessReview, CustomerPortalUserManagementQueryError } from "../../../../server/queries/customer-portal-user-management.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { Link } from "../../../../components/ui/link.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerPortalUsersPanel } from "./customer-portal-users-panel.tsx";
import { inviteCustomerPortalUserAction, updateCustomerPortalAccountMembershipRoleAction, setCustomerPortalAccountMembershipStatusAction, recordCustomerPortalAccountMembershipAccessReviewAction } from "./actions.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Customer User Management (CPL-315, CG-S13-CPL-017, Prompt 315). The
 * account_admin-facing counterpart to CPL-300's own `customer-portal` scope
 * page: invite, role-change, suspend/reactivate/revoke, pending invites, and
 * a real access-review surface, all scoped to one account the signed-in
 * identity administers.
 *
 * Guarded the same two-layer way every prior Phase 8 mutation surface is:
 * (1) lib/portal/customer-portal-guard.ts's own portal-entry gate (is this
 * identity a customer_user in this tenant at all), then (2) this page's own
 * client-side hint of whether the viewer is an account_admin FOR THE
 * SELECTED ACCOUNT (from app.get_customer_portal_scope_context's own `role`
 * column) -- a UX convenience only, never the real boundary: every RPC this
 * page's actions compose independently re-checks
 * app.actor_is_active_customer_portal_account_admin server-side on every
 * call, so a forged/stale client hint can deny a legitimate admin a
 * confusing UI state at worst, never grant an unauthorized write.
 */
export default async function CustomerPortalUsersPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ accountId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { accountId: rawAccountId } = await searchParams;
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
  let accounts: Awaited<ReturnType<typeof getCustomerPortalScopeContext>> = [];

  try {
    accounts = await getCustomerPortalScopeContext(supabase, access.authUserId, access.tenant.id);
  } catch (error) {
    if (!(error instanceof CustomerPortalScopeQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="users" />
        <ErrorState description="Something went wrong loading your account access. Please try again." />
      </div>
    );
  }

  if (accounts.length === 0) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="users" />
        <EmptyState title="No account linked yet" description="No account is linked to your customer profile yet. Contact your account administrator." />
      </div>
    );
  }

  const requestedAccountId = rawAccountId && UUID_RE.test(rawAccountId) ? rawAccountId : null;
  const selectedAccountId = (requestedAccountId && accounts.some((a) => a.accountId === requestedAccountId) ? requestedAccountId : null) ?? accounts.find((a) => a.isPrimary)?.accountId ?? accounts[0]!.accountId;
  const selectedAccount = accounts.find((a) => a.accountId === selectedAccountId) ?? null;
  const viewerIsAdmin = selectedAccount?.role === "account_admin";

  let detailLoadFailed = false;
  let memberships: Awaited<ReturnType<typeof listCustomerPortalAccountMemberships>> = [];
  let reviewMembershipRows: Awaited<ReturnType<typeof listCustomerPortalAccountMembershipsForAccessReview>> = [];

  if (viewerIsAdmin) {
    try {
      [memberships, reviewMembershipRows] = await Promise.all([
        listCustomerPortalAccountMemberships(supabase, access.tenant.id, selectedAccountId, access.authUserId, { limit: 200 }),
        listCustomerPortalAccountMembershipsForAccessReview(supabase, access.tenant.id, selectedAccountId, access.authUserId, { limit: 200 }),
      ]);
    } catch (error) {
      if (!(error instanceof CustomerPortalScopeQueryError) && !(error instanceof CustomerPortalUserManagementQueryError)) throw error;
      detailLoadFailed = true;
    }
  }

  // One fresh idempotency key per row, per render (never a client-side
  // Date.now()-derived key) -- mirrors app/(tenant)/[tenantSlug]/customer-
  // profile/page.tsx's own randomUUID()-per-render convention, applied per
  // ROW here since a single render can carry many independent review forms
  // and each needs its own distinct key (two different memberships reviewed
  // in the same render must never collide on one idempotency_key).
  const reviewRows = reviewMembershipRows.map((row) => ({
    row,
    reviewAction: recordCustomerPortalAccountMembershipAccessReviewAction.bind(null, tenantSlug, selectedAccountId, randomUUID()),
  }));

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="users" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Manage users</h1>
        <p className="text-xs text-neutral-500">Invite users, change their role, suspend or revoke access, and record periodic access reviews for this account. Only active account admins can manage users.</p>
      </div>

      {accounts.length > 1 ? (
        <nav aria-label="Account" className="flex flex-wrap gap-2 text-xs">
          {accounts.map((a) => (
            <Link
              key={a.accountId}
              href={`/${tenantSlug}/customer-portal-users?accountId=${a.accountId}`}
              className={a.accountId === selectedAccountId ? "font-semibold text-primary underline" : "text-neutral-500 underline"}
            >
              {a.accountName}
            </Link>
          ))}
        </nav>
      ) : null}

      {!viewerIsAdmin ? (
        <PermissionState description="Only an active account admin can manage users on this account. Ask your account administrator if you believe you should have this access." />
      ) : detailLoadFailed ? (
        <ErrorState description="Something went wrong loading this account's users. Please try again." />
      ) : (
        <CustomerPortalUsersPanel
          memberships={memberships}
          reviewRows={reviewRows}
          inviteAction={inviteCustomerPortalUserAction.bind(null, tenantSlug, selectedAccountId)}
          roleAction={updateCustomerPortalAccountMembershipRoleAction.bind(null, tenantSlug, selectedAccountId)}
          statusAction={setCustomerPortalAccountMembershipStatusAction.bind(null, tenantSlug, selectedAccountId)}
        />
      )}
    </div>
  );
}
