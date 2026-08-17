import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLoyaltyPrograms, listLoyaltyAccounts, LoyaltyProgramQueryError } from "../../../../../server/queries/customer-portal-loyalty-program.ts";
import { listLoyaltyBenefitEntitlements, LoyaltyBenefitsQueryError } from "../../../../../server/queries/customer-portal-loyalty-benefits.ts";
import type { LoyaltyBenefitEntitlement } from "../../../../../server/contracts/customer-portal-loyalty-benefits/customer-portal-loyalty-benefits.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { IssueBenefitForm, EntitlementRow, ExpireBenefitsButton } from "./loyalty-benefits-admin-panel.tsx";

/**
 * Cashback, Discount and Voucher tenant-internal admin screen (CPL-319,
 * CG-S13-CPL-021). Per-account issuance, reversal, fraud hold/release, and a
 * tenant-wide expiry scan -- all gated by each RPC's own LYL:* authority
 * check, this page's own guard (resolveTenantAdminAccessForRequest) only
 * confirms a coarse tenant_admin portal-entry boundary. Reuses CPL-316's own
 * program/account queries (never re-derives them).
 */
export default async function LoyaltyBenefitsAdminPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ programId?: string }>;
}) {
  const { tenantSlug } = await params;
  const { programId } = await searchParams;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let programs: Awaited<ReturnType<typeof listLoyaltyPrograms>> = [];

  try {
    programs = await listLoyaltyPrograms(supabase, access.tenant.id, access.authUserId, { limit: 100 });
  } catch (error) {
    if (!(error instanceof LoyaltyProgramQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Cashback, Discount and Voucher</h1>
        <ErrorState description="Something went wrong loading loyalty programs. Please try again." />
      </div>
    );
  }

  const selectedProgram = programId ? (programs.find((program) => program.id === programId) ?? null) : null;
  let accounts: Awaited<ReturnType<typeof listLoyaltyAccounts>> = [];
  let entitlementsByAccount: Map<string, LoyaltyBenefitEntitlement[]> = new Map();
  let detailLoadFailed = false;

  if (selectedProgram) {
    try {
      accounts = await listLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { programId: selectedProgram.id, status: "active", limit: 50 });
      const perAccountEntitlements = await Promise.all(accounts.map((account) => listLoyaltyBenefitEntitlements(supabase, access.tenant.id, access.authUserId, { loyaltyAccountId: account.id, limit: 100 })));
      entitlementsByAccount = new Map(accounts.map((account, index) => [account.id, perAccountEntitlements[index] ?? []]));
    } catch (error) {
      if (!(error instanceof LoyaltyProgramQueryError) && !(error instanceof LoyaltyBenefitsQueryError)) throw error;
      detailLoadFailed = true;
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold text-text-primary">Cashback, Discount and Voucher</h1>
          <p className="text-sm text-text-secondary">Issue, reverse, and fraud-hold customer benefit entitlements. Voucher codes are shown once, at issuance, and never stored in plaintext.</p>
        </div>
        {selectedProgram ? <ExpireBenefitsButton tenantSlug={tenantSlug} programId={selectedProgram.id} /> : null}
      </div>

      <section aria-labelledby="benefit-programs-heading" className="flex flex-col gap-2">
        <h2 id="benefit-programs-heading" className="text-sm font-semibold text-text-primary">
          Select a program
        </h2>
        {programs.length === 0 ? (
          <EmptyState title="No loyalty programs yet" description="Create a loyalty program first, in Loyalty admin." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {programs.map((program) => (
              <a
                key={program.id}
                href={`/${tenantSlug}/admin/loyalty-benefits?programId=${program.id}`}
                className={`rounded-md border px-3 py-1.5 text-sm ${program.id === selectedProgram?.id ? "border-primary bg-primary/10 font-medium text-primary" : "border-neutral-200 text-text-secondary hover:text-text-primary"}`}
              >
                {program.name}
              </a>
            ))}
          </div>
        )}
      </section>

      {programId && !selectedProgram ? <ErrorState description="This program could not be found." /> : null}
      {selectedProgram && detailLoadFailed ? <ErrorState description="Something went wrong loading this program's own benefit detail. Please try again." /> : null}

      {selectedProgram && !detailLoadFailed ? (
        <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
          <h2 className="text-lg font-semibold text-text-primary">{selectedProgram.name}</h2>

          {accounts.length === 0 ? (
            <EmptyState title="No active enrolled accounts" description="Enroll a customer account in Loyalty admin first." />
          ) : (
            <div className="flex flex-col gap-4">
              {accounts.map((account) => {
                const entitlements = entitlementsByAccount.get(account.id) ?? [];
                return (
                  <div key={account.id} className="flex flex-col gap-3 rounded-md border border-neutral-100 p-3">
                    <p className="font-mono text-xs text-text-secondary">{account.customerAccountId}</p>
                    <IssueBenefitForm tenantSlug={tenantSlug} programId={selectedProgram.id} account={account} />
                    {entitlements.length === 0 ? (
                      <p className="text-xs text-text-secondary">No benefits issued yet for this account.</p>
                    ) : (
                      <div className="flex flex-col gap-2">
                        {entitlements.map((entitlement) => (
                          <EntitlementRow key={entitlement.id} tenantSlug={tenantSlug} programId={selectedProgram.id} entitlement={entitlement} />
                        ))}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      ) : null}
    </div>
  );
}
