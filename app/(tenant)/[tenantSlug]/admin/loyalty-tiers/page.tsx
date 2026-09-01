import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLoyaltyPrograms, listLoyaltyAccounts, LoyaltyProgramQueryError } from "../../../../../server/queries/customer-portal-loyalty-program.ts";
import { listLoyaltyTierDefinitions, getLoyaltyAccountTierState, getLoyaltyProgramTierReadiness, LoyaltyTierQueryError } from "../../../../../server/queries/customer-portal-loyalty-tier.ts";
import type { LoyaltyAccountTierState, LoyaltyProgramTierReadiness } from "../../../../../server/contracts/customer-portal-loyalty-tier/customer-portal-loyalty-tier.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  CreateTierDefinitionForm,
  EditTierDefinitionDraftForm,
  TierDefinitionHistory,
  TierReadinessBanner,
  AccountTierRow,
} from "./loyalty-tier-admin-panel.tsx";

/**
 * Membership Tier tenant-internal admin screen (CPL-317, CG-S13-CPL-019).
 * Tier definition lifecycle (draft -> published -> superseded) per
 * (program, tier_name), plus per-account tier state, on-demand
 * recalculation, and fraud-hold/release -- all gated by each RPC's own
 * LYL:* authority check, this page's own guard
 * (resolveTenantAdminAccessForRequest) only confirms a coarse tenant_admin
 * portal-entry boundary. Reuses CPL-316's own program/account queries
 * (never re-derives them).
 */
export default async function LoyaltyTierAdminPage({
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
        <h1 className="text-xl font-semibold text-text-primary">Membership Tier</h1>
        <ErrorState description="Something went wrong loading loyalty programs. Please try again." />
      </div>
    );
  }

  const selectedProgram = programId ? (programs.find((program) => program.id === programId) ?? null) : null;
  let tierDefinitions: Awaited<ReturnType<typeof listLoyaltyTierDefinitions>> = [];
  let accounts: Awaited<ReturnType<typeof listLoyaltyAccounts>> = [];
  let accountStates: Map<string, LoyaltyAccountTierState> = new Map();
  let readiness: LoyaltyProgramTierReadiness | null = null;
  let detailLoadFailed = false;

  if (selectedProgram) {
    try {
      // ISS-2026-127 item 2: the readiness fetch rides alongside this
      // page's own existing Promise.all, but its own failure is tolerated
      // independently (mapped to null, never rethrown) so an advisory-only
      // banner can never block the tier definitions/accounts this section
      // already renders without it.
      [tierDefinitions, accounts, readiness] = await Promise.all([
        listLoyaltyTierDefinitions(supabase, access.tenant.id, selectedProgram.id, access.authUserId, { limit: 100 }),
        listLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { programId: selectedProgram.id, status: "active", limit: 50 }),
        getLoyaltyProgramTierReadiness(supabase, access.tenant.id, selectedProgram.id, access.authUserId).catch((error: unknown) => {
          if (!(error instanceof LoyaltyTierQueryError)) throw error;
          return null;
        }),
      ]);
      const states = await Promise.all(accounts.map((account) => getLoyaltyAccountTierState(supabase, access.tenant.id, account.id, access.authUserId)));
      accountStates = new Map(states.map((state) => [state.loyaltyAccountId, state]));
    } catch (error) {
      if (!(error instanceof LoyaltyProgramQueryError) && !(error instanceof LoyaltyTierQueryError)) throw error;
      detailLoadFailed = true;
    }
  }

  const publishedByTierName = new Map(tierDefinitions.filter((tier) => tier.status === "published").map((tier) => [tier.tierName, tier]));
  const draftByTierName = new Map(tierDefinitions.filter((tier) => tier.status === "draft").map((tier) => [tier.tierName, tier]));
  const tierNames = Array.from(new Set(tierDefinitions.map((tier) => tier.tierName))).sort();

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Membership Tier</h1>
        <p className="text-sm text-text-secondary">Effective-dated tier thresholds and benefits, per-account tier movement, on-demand recalculation, and fraud-hold suspension of tier benefits.</p>
      </div>

      <section aria-labelledby="tier-programs-heading" className="flex flex-col gap-2">
        <h2 id="tier-programs-heading" className="text-sm font-semibold text-text-primary">
          Select a program
        </h2>
        {programs.length === 0 ? (
          <EmptyState title="No loyalty programs yet" description="Create a loyalty program first, in Loyalty admin." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {programs.map((program) => (
              <a
                key={program.id}
                href={`/${tenantSlug}/admin/loyalty-tiers?programId=${program.id}`}
                className={`rounded-md border px-3 py-1.5 text-sm ${program.id === selectedProgram?.id ? "border-primary bg-primary/10 font-medium text-primary" : "border-neutral-200 text-text-secondary hover:text-text-primary"}`}
              >
                {program.name}
              </a>
            ))}
          </div>
        )}
      </section>

      {programId && !selectedProgram ? <ErrorState description="This program could not be found." /> : null}
      {selectedProgram && detailLoadFailed ? <ErrorState description="Something went wrong loading this program's own tier detail. Please try again." /> : null}

      {selectedProgram && !detailLoadFailed ? (
        <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
          <h2 className="text-lg font-semibold text-text-primary">{selectedProgram.name}</h2>

          <TierReadinessBanner readiness={readiness} />

          <section aria-labelledby="tier-defs-heading" className="flex flex-col gap-3">
            <h3 id="tier-defs-heading" className="text-sm font-semibold text-text-primary">
              Tier definitions
            </h3>
            <p className="text-xs text-text-secondary">Higher tier_rank is a more prestigious tier. Each tier name has its own independent draft/published/superseded lineage -- publishing locks that version forever.</p>
            <CreateTierDefinitionForm tenantSlug={tenantSlug} programId={selectedProgram.id} />
            {tierNames.length === 0 ? (
              <EmptyState title="No tier definitions yet" description="Create this program's first tier above." />
            ) : (
              <div className="flex flex-col gap-3">
                {tierNames.map((tierName) => {
                  const draft = draftByTierName.get(tierName);
                  const published = publishedByTierName.get(tierName);
                  return (
                    <div key={tierName} className="rounded-md border border-neutral-100 p-3">
                      <p className="text-sm font-semibold text-text-primary">{tierName}</p>
                      {draft ? <EditTierDefinitionDraftForm tenantSlug={tenantSlug} programId={selectedProgram.id} version={draft} /> : null}
                      {published ? (
                        <p className="mt-1 text-xs text-text-secondary">
                          Published: rank {published.tierRank}, {published.thresholdDimension} ≥ {published.thresholdValue}, review {published.reviewPeriodDays}d
                        </p>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            )}
            <TierDefinitionHistory versions={tierDefinitions} />
          </section>

          <section aria-labelledby="tier-accounts-heading" className="flex flex-col gap-3">
            <h3 id="tier-accounts-heading" className="text-sm font-semibold text-text-primary">
              Enrolled accounts -- tier state
            </h3>
            {accounts.length === 0 ? (
              <EmptyState title="No active enrolled accounts" description="Enroll a customer account in Loyalty admin first." />
            ) : (
              <div className="flex flex-col gap-3">
                {accounts.map((account) => (
                  <AccountTierRow key={account.id} tenantSlug={tenantSlug} programId={selectedProgram.id} account={account} state={accountStates.get(account.id) ?? null} />
                ))}
              </div>
            )}
          </section>
        </div>
      ) : null}
    </div>
  );
}
