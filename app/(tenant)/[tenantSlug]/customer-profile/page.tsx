import { randomUUID } from "node:crypto";
import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { getCustomerPortalScopeContext, CustomerPortalScopeQueryError } from "../../../../server/queries/customer-portal-scope.ts";
import {
  getCustomerPortalAccountProfile,
  listCustomerPortalAccountContacts,
  listCustomerPortalProfileChangeRequests,
  CustomerPortalProfileQueryError,
} from "../../../../server/queries/customer-portal-profile.ts";
import { listCustomerPortalLegalIdentityChangeRequests, CustomerPortalLegalIdentityQueryError } from "../../../../server/queries/customer-portal-legal-identity.ts";
import { listCustomerPortalContactChangeRequests, CustomerPortalContactChangeQueryError } from "../../../../server/queries/customer-portal-contact-change.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { Link } from "../../../../components/ui/link.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerProfilePanel } from "./customer-profile-panel.tsx";
import {
  submitCustomerProfileChangeRequestAction,
  withdrawCustomerProfileChangeRequestAction,
  submitCustomerLegalIdentityChangeRequestAction,
  withdrawCustomerLegalIdentityChangeRequestAction,
  submitCustomerContactChangeRequestAction,
  withdrawCustomerContactChangeRequestAction,
} from "./actions.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Customer Profile (CPL-314, CG-S13-CPL-016, Prompt 314; extended by
 * ISS-2026-123). Current-state projection of one account's own trade_name/
 * billing_address/legal_name/tax_id (all editable via their own staff-
 * reviewed change-request path) plus customer_status, contacts (add/update/
 * remove change requests, ISS-2026-123 item 2), and change-request history.
 *
 * Uses lib/portal/customer-portal-guard.ts (CPL-300's general-purpose Layer 4
 * portal entry guard), carrying `CustomerPortalNav` (a natural sibling of the
 * account-access/dashboard screens, mirroring CPL-309..313's own identical
 * choice).
 *
 * Business rule (source prompt §24): "Customer profile edits cannot silently
 * overwrite canonical customer master data" -- there is no direct edit action
 * anywhere on this page. Every writable field goes through its own change-
 * request form that produces a `pending` row; the real app.accounts/
 * app.contacts/app.contact_links rows only change once staff decides it
 * (app.decide_customer_profile_change_request/app.decide_customer_legal_
 * identity_change_request/app.decide_customer_contact_change_request, none
 * callable from here). legal_name/tax_id changes are ADDITIONALLY gated on a
 * current step-up-MFA authorization when the tenant has configured one for
 * (COM, Approve) -- enforced entirely server-side at the decide RPC, this
 * page has no MFA-specific UI of its own.
 */
export default async function CustomerProfilePage({
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
        <CustomerPortalNav tenantSlug={tenantSlug} current="profile" />
        <ErrorState description="Something went wrong loading your account access. Please try again." />
      </div>
    );
  }

  if (accounts.length === 0) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="profile" />
        <EmptyState title="No account linked yet" description="No account is linked to your customer profile yet. Contact your account administrator." />
      </div>
    );
  }

  const requestedAccountId = rawAccountId && UUID_RE.test(rawAccountId) ? rawAccountId : null;
  const selectedAccountId = (requestedAccountId && accounts.some((a) => a.accountId === requestedAccountId) ? requestedAccountId : null) ?? accounts.find((a) => a.isPrimary)?.accountId ?? accounts[0]!.accountId;

  let detailLoadFailed = false;
  let notFoundResult = false;
  let profile: Awaited<ReturnType<typeof getCustomerPortalAccountProfile>> | null = null;
  let contacts: Awaited<ReturnType<typeof listCustomerPortalAccountContacts>> = [];
  let history: Awaited<ReturnType<typeof listCustomerPortalProfileChangeRequests>> = [];
  let legalIdentityHistory: Awaited<ReturnType<typeof listCustomerPortalLegalIdentityChangeRequests>> = [];
  let contactChangeHistory: Awaited<ReturnType<typeof listCustomerPortalContactChangeRequests>> = [];

  try {
    [profile, contacts, history, legalIdentityHistory, contactChangeHistory] = await Promise.all([
      getCustomerPortalAccountProfile(supabase, access.tenant.id, access.authUserId, selectedAccountId),
      listCustomerPortalAccountContacts(supabase, access.tenant.id, access.authUserId, selectedAccountId),
      listCustomerPortalProfileChangeRequests(supabase, access.tenant.id, access.authUserId, { accountId: selectedAccountId, limit: 50 }),
      listCustomerPortalLegalIdentityChangeRequests(supabase, access.tenant.id, access.authUserId, { accountId: selectedAccountId, limit: 50 }),
      listCustomerPortalContactChangeRequests(supabase, access.tenant.id, access.authUserId, { accountId: selectedAccountId, limit: 50 }),
    ]);
  } catch (error) {
    if (error instanceof CustomerPortalProfileQueryError && error.code === "record_not_found") {
      notFoundResult = true;
    } else if (error instanceof CustomerPortalProfileQueryError || error instanceof CustomerPortalLegalIdentityQueryError || error instanceof CustomerPortalContactChangeQueryError) {
      detailLoadFailed = true;
    } else {
      throw error;
    }
  }

  // Fresh per render, one per writable field -- a genuine retry of the SAME
  // rendered form reuses this same key; a successful submit revalidates this
  // route and mints a fresh key for the NEXT proposal. Mirrors
  // app/(tenant)/[tenantSlug]/customer-quotes/page.tsx's own established
  // randomUUID()-per-render convention -- never a client-side Date.now()
  // derivation.
  const tradeNameIdempotencyKey = randomUUID();
  const billingAddressIdempotencyKey = randomUUID();
  const legalNameIdempotencyKey = randomUUID();
  const taxIdIdempotencyKey = randomUUID();
  const addContactIdempotencyKey = randomUUID();
  // One bound update action and one bound remove action per existing contact, per render --
  // a plain closure cannot cross the Server -> Client Component boundary, only a real (bound)
  // Server Action reference can, so every per-contact action is pre-bound here rather than
  // passed down as a factory the client would call.
  const contactActions = new Map(
    contacts.map((c) => [
      c.contactId,
      {
        updateAction: submitCustomerContactChangeRequestAction.bind(null, tenantSlug, selectedAccountId, "update", c.contactId, randomUUID()),
        removeAction: submitCustomerContactChangeRequestAction.bind(null, tenantSlug, selectedAccountId, "remove", c.contactId, randomUUID()),
      },
    ]),
  );

  return (
    <div className="flex flex-col gap-4">
      <CustomerPortalNav tenantSlug={tenantSlug} current="profile" />

      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Company profile</h1>
        <p className="text-xs text-neutral-500">Trade name, billing address, legal name, tax ID, and contact changes are all reviewed by our team before they take effect. Nothing here is applied immediately.</p>
      </div>

      {accounts.length > 1 ? (
        <nav aria-label="Account" className="flex flex-wrap gap-2 text-xs">
          {accounts.map((a) => (
            <Link key={a.accountId} href={`/${tenantSlug}/customer-profile?accountId=${a.accountId}`} className={a.accountId === selectedAccountId ? "font-semibold text-primary underline" : "text-neutral-500 underline"}>
              {a.accountName}
            </Link>
          ))}
        </nav>
      ) : null}

      {notFoundResult ? (
        <PermissionState description="You don't have access to this account's profile." />
      ) : detailLoadFailed || !profile ? (
        <ErrorState description="Something went wrong loading this account's profile. Please try again." />
      ) : (
        <CustomerProfilePanel
          tenantSlug={tenantSlug}
          profile={profile}
          contacts={contacts}
          history={history}
          legalIdentityHistory={legalIdentityHistory}
          contactChangeHistory={contactChangeHistory}
          submitTradeNameAction={submitCustomerProfileChangeRequestAction.bind(null, tenantSlug, selectedAccountId, "trade_name", tradeNameIdempotencyKey)}
          submitBillingAddressAction={submitCustomerProfileChangeRequestAction.bind(null, tenantSlug, selectedAccountId, "billing_address", billingAddressIdempotencyKey)}
          withdrawAction={withdrawCustomerProfileChangeRequestAction.bind(null, tenantSlug)}
          submitLegalNameAction={submitCustomerLegalIdentityChangeRequestAction.bind(null, tenantSlug, selectedAccountId, "legal_name", legalNameIdempotencyKey)}
          submitTaxIdAction={submitCustomerLegalIdentityChangeRequestAction.bind(null, tenantSlug, selectedAccountId, "tax_id", taxIdIdempotencyKey)}
          withdrawLegalIdentityAction={withdrawCustomerLegalIdentityChangeRequestAction.bind(null, tenantSlug)}
          submitAddContactAction={submitCustomerContactChangeRequestAction.bind(null, tenantSlug, selectedAccountId, "add", null, addContactIdempotencyKey)}
          contactActions={contactActions}
          withdrawContactChangeAction={withdrawCustomerContactChangeRequestAction.bind(null, tenantSlug)}
        />
      )}
    </div>
  );
}
