import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listLoyaltyPrograms, LoyaltyProgramQueryError } from "../../../../../server/queries/customer-portal-loyalty-program.ts";
import { listLoyaltyTierDefinitions, LoyaltyTierQueryError } from "../../../../../server/queries/customer-portal-loyalty-tier.ts";
import { listLoyaltyRewards, LoyaltyRewardQueryError } from "../../../../../server/queries/customer-portal-loyalty-rewards.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { CreateLoyaltyRewardForm, EditLoyaltyRewardDraftForm, LoyaltyRewardHistory } from "./loyalty-rewards-admin-panel.tsx";

/**
 * Reward Catalogue tenant-internal admin screen (CPL-320, CG-S13-CPL-022).
 * Reward lifecycle (draft -> published -> paused/resumed -> archived, or
 * superseded by a republish) per (program, reward_name) -- all gated by
 * each RPC's own LYL:* authority check, this page's own guard
 * (resolveTenantAdminAccessForRequest) only confirms a coarse tenant_admin
 * portal-entry boundary. Reuses CPL-316's own program query and CPL-317's
 * own published-tier-definitions query (for the min-tier-gate selector) --
 * never re-derives them.
 *
 * No file-upload UI is built here -- reward media/terms reuse app.files via
 * a foreign key (design decision 9); staff paste an existing file id
 * (already uploaded via the Document Center or a future capability's own
 * uploader), disclosed scope simplification, not a silent gap -- this
 * checkpoint's own job is the catalogue, not a new upload surface.
 */
export default async function LoyaltyRewardsAdminPage({ params, searchParams }: { params: Promise<{ tenantSlug: string }>; searchParams: Promise<{ programId?: string }> }) {
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
        <h1 className="text-xl font-semibold text-text-primary">Reward Catalogue</h1>
        <ErrorState description="Something went wrong loading loyalty programs. Please try again." />
      </div>
    );
  }

  const selectedProgram = programId ? (programs.find((program) => program.id === programId) ?? null) : null;
  let rewards: Awaited<ReturnType<typeof listLoyaltyRewards>> = [];
  let publishedTiers: Awaited<ReturnType<typeof listLoyaltyTierDefinitions>> = [];
  let detailLoadFailed = false;

  if (selectedProgram) {
    try {
      [rewards, publishedTiers] = await Promise.all([
        listLoyaltyRewards(supabase, access.tenant.id, access.authUserId, { programId: selectedProgram.id, limit: 200 }),
        listLoyaltyTierDefinitions(supabase, access.tenant.id, selectedProgram.id, access.authUserId, { status: "published", limit: 100 }),
      ]);
    } catch (error) {
      if (!(error instanceof LoyaltyRewardQueryError) && !(error instanceof LoyaltyTierQueryError)) throw error;
      detailLoadFailed = true;
    }
  }

  const liveByRewardName = new Map(rewards.filter((reward) => reward.status === "published" || reward.status === "paused").map((reward) => [reward.rewardName, reward]));
  const draftByRewardName = new Map(rewards.filter((reward) => reward.status === "draft").map((reward) => [reward.rewardName, reward]));
  const rewardNames = Array.from(new Set(rewards.map((reward) => reward.rewardName))).sort();

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Reward Catalogue</h1>
        <p className="text-sm text-text-secondary">Reward definitions, eligibility criteria, stock configuration, and effective-dated scheduling. Redemption itself is a separate, future capability -- this screen only configures what customers may see and become eligible for.</p>
      </div>

      <section aria-labelledby="reward-programs-heading" className="flex flex-col gap-2">
        <h2 id="reward-programs-heading" className="text-sm font-semibold text-text-primary">
          Select a program
        </h2>
        {programs.length === 0 ? (
          <EmptyState title="No loyalty programs yet" description="Create a loyalty program first, in Loyalty admin." />
        ) : (
          <div className="flex flex-wrap gap-2">
            {programs.map((program) => (
              <a
                key={program.id}
                href={`/${tenantSlug}/admin/loyalty-rewards?programId=${program.id}`}
                className={`rounded-md border px-3 py-1.5 text-sm ${program.id === selectedProgram?.id ? "border-primary bg-primary/10 font-medium text-primary" : "border-neutral-200 text-text-secondary hover:text-text-primary"}`}
              >
                {program.name}
              </a>
            ))}
          </div>
        )}
      </section>

      {programId && !selectedProgram ? <ErrorState description="This program could not be found." /> : null}
      {selectedProgram && detailLoadFailed ? <ErrorState description="Something went wrong loading this program's own rewards. Please try again." /> : null}

      {selectedProgram && !detailLoadFailed ? (
        <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
          <h2 className="text-lg font-semibold text-text-primary">{selectedProgram.name}</h2>

          <section aria-labelledby="rewards-heading" className="flex flex-col gap-3">
            <h3 id="rewards-heading" className="text-sm font-semibold text-text-primary">
              Rewards
            </h3>
            <p className="text-xs text-text-secondary">Each reward name has its own independent draft/published/superseded lineage -- publishing locks that version forever and supersedes the prior live (published or paused) version, if any.</p>
            <CreateLoyaltyRewardForm tenantSlug={tenantSlug} programId={selectedProgram.id} publishedTiers={publishedTiers} />
            {rewardNames.length === 0 ? (
              <EmptyState title="No rewards yet" description="Create this program's first reward above." />
            ) : (
              <div className="flex flex-col gap-3">
                {rewardNames.map((rewardName) => {
                  const draft = draftByRewardName.get(rewardName);
                  const live = liveByRewardName.get(rewardName);
                  return (
                    <div key={rewardName} className="rounded-md border border-neutral-100 p-3">
                      <p className="text-sm font-semibold text-text-primary">{rewardName}</p>
                      {draft ? <EditLoyaltyRewardDraftForm tenantSlug={tenantSlug} programId={selectedProgram.id} reward={draft} publishedTiers={publishedTiers} /> : null}
                      {live ? (
                        <p className="mt-1 text-xs text-text-secondary">
                          {live.status === "published" ? "Published" : "Paused"}: {live.rewardType}, {live.totalStock === null ? "unlimited stock" : `${live.totalStock} total stock`}
                          {live.minPointsRequired !== null ? `, ${live.minPointsRequired}+ points` : ""}
                        </p>
                      ) : null}
                    </div>
                  );
                })}
              </div>
            )}
            <LoyaltyRewardHistory tenantSlug={tenantSlug} programId={selectedProgram.id} rewards={rewards} />
          </section>
        </div>
      ) : null}
    </div>
  );
}
