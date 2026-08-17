import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyBenefitEntitlements, LoyaltyBenefitsQueryError } from "../../../../server/queries/customer-portal-loyalty-benefits.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltyBenefitsWallet } from "./customer-loyalty-benefits-panel.tsx";

/**
 * Cashback, Discount and Voucher benefit wallet (CPL-319, CG-S13-CPL-021).
 * Read-only projection over Loyalty-owned app.loyalty_benefit_entitlements
 * (ADR-0024 Part A) plus ONE customer-initiated write, redemption -- the
 * FIRST anywhere in the Loyalty domain (migration design decision 5).
 * Issuance/reversal/expiry/fraud-hold remain staff-side
 * (app/(tenant)/[tenantSlug]/admin/loyalty-benefits).
 */
export default async function CustomerLoyaltyBenefitsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={access.status === "tenant_suspended" ? "This organization's customer portal is currently unavailable." : "You don't have access to this organization's cashback and vouchers. Contact your account administrator if you believe this is a mistake."}
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let entitlements: Awaited<ReturnType<typeof listCustomerPortalLoyaltyBenefitEntitlements>> = [];

  try {
    entitlements = await listCustomerPortalLoyaltyBenefitEntitlements(supabase, access.tenant.id, access.authUserId, { limit: 50 });
  } catch (error) {
    if (!(error instanceof LoyaltyBenefitsQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="benefits" />
        <ErrorState description="Something went wrong loading your cashback and vouchers. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="benefits" />

      <div>
        <h1 className="text-xl font-semibold text-text-primary">Cashback &amp; vouchers</h1>
        <p className="text-xs text-text-secondary">Cashback, discounts, and vouchers issued to your account. Vouchers can be redeemed here or by entering a code you received elsewhere.</p>
      </div>

      <CustomerLoyaltyBenefitsWallet tenantSlug={tenantSlug} entitlements={entitlements} />
    </div>
  );
}
