import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listLoyaltyPrograms,
  getLoyaltyProgram,
  listLoyaltyProgramRuleVersions,
  listLoyaltyAccounts,
  listLoyaltyEarningEvents,
} from "../../../../../server/queries/customer-portal-loyalty-program.ts";
import { LoyaltyProgramQueryError } from "../../../../../server/queries/customer-portal-loyalty-program.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CreateProgramForm, ProgramList, ProgramStatusForm, CreateRuleVersionForm, EditRuleVersionDraftForm, RuleVersionHistory, EnrollAccountForm, AccountList, EvaluateEarningForm, EarningEventList } from "./loyalty-admin-panel.tsx";

/**
 * Loyalty Program and Earning tenant-internal admin screen (CPL-316,
 * CG-S13-CPL-018). Program/rule-version lifecycle (draft -> published ->
 * superseded), account enrollment/status, and on-demand earning evaluation/
 * reversal -- all gated by each RPC's own LYL:* authority check, this page's
 * own guard (resolveTenantAdminAccessForRequest) only confirms a coarse
 * tenant_admin portal-entry boundary.
 */
export default async function LoyaltyAdminPage({
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
        <h1 className="text-xl font-semibold text-text-primary">Loyalty Program</h1>
        <ErrorState description="Something went wrong loading loyalty programs. Please try again." />
      </div>
    );
  }

  let selectedProgram: Awaited<ReturnType<typeof getLoyaltyProgram>> | null = null;
  let ruleVersions: Awaited<ReturnType<typeof listLoyaltyProgramRuleVersions>> = [];
  let accounts: Awaited<ReturnType<typeof listLoyaltyAccounts>> = [];
  let events: Awaited<ReturnType<typeof listLoyaltyEarningEvents>> = [];
  let detailLoadFailed = false;

  if (programId) {
    try {
      [selectedProgram, ruleVersions, accounts, events] = await Promise.all([
        getLoyaltyProgram(supabase, access.tenant.id, programId, access.authUserId),
        listLoyaltyProgramRuleVersions(supabase, access.tenant.id, programId, access.authUserId, { limit: 100 }),
        listLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { programId, limit: 100 }),
        listLoyaltyEarningEvents(supabase, access.tenant.id, access.authUserId, { programId, limit: 50 }),
      ]);
    } catch (error) {
      if (!(error instanceof LoyaltyProgramQueryError)) throw error;
      detailLoadFailed = true;
    }
  }

  const draftVersion = ruleVersions.find((version) => version.status === "draft") ?? null;

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Loyalty Program</h1>
        <p className="text-sm text-text-secondary">Configurable loyalty programs, effective-dated earning rules, customer enrollment, and on-demand paid-invoice earning evaluation.</p>
      </div>

      <CreateProgramForm tenantSlug={tenantSlug} />

      <section aria-labelledby="programs-heading" className="flex flex-col gap-2">
        <h2 id="programs-heading" className="text-sm font-semibold text-text-primary">
          Programs
        </h2>
        <ProgramList tenantSlug={tenantSlug} programs={programs} />
      </section>

      {programId && detailLoadFailed ? <ErrorState description="Something went wrong loading this program's own detail. Please try again." /> : null}

      {selectedProgram ? (
        <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
          <div className="flex items-center justify-between gap-4">
            <h2 className="text-lg font-semibold text-text-primary">{selectedProgram.name}</h2>
            <ProgramStatusForm tenantSlug={tenantSlug} program={selectedProgram} />
          </div>

          <section aria-labelledby="rule-versions-heading" className="flex flex-col gap-3">
            <h3 id="rule-versions-heading" className="text-sm font-semibold text-text-primary">
              Earning rule versions
            </h3>
            {draftVersion ? <EditRuleVersionDraftForm tenantSlug={tenantSlug} programId={selectedProgram.id} version={draftVersion} /> : <CreateRuleVersionForm tenantSlug={tenantSlug} programId={selectedProgram.id} disabled={false} />}
            <RuleVersionHistory versions={ruleVersions} />
          </section>

          <section aria-labelledby="accounts-heading" className="flex flex-col gap-3">
            <h3 id="accounts-heading" className="text-sm font-semibold text-text-primary">
              Enrolled customer accounts
            </h3>
            <EnrollAccountForm tenantSlug={tenantSlug} programId={selectedProgram.id} />
            <AccountList tenantSlug={tenantSlug} programId={selectedProgram.id} accounts={accounts} />
          </section>

          <section aria-labelledby="earning-heading" className="flex flex-col gap-3">
            <h3 id="earning-heading" className="text-sm font-semibold text-text-primary">
              Earning
            </h3>
            <EvaluateEarningForm tenantSlug={tenantSlug} programId={selectedProgram.id} />
            <EarningEventList tenantSlug={tenantSlug} programId={selectedProgram.id} events={events} />
          </section>
        </div>
      ) : null}
    </div>
  );
}
