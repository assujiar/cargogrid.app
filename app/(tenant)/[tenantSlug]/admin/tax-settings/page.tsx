import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listFinanceTaxCodes,
  listFinanceTaxRuleVersions,
  TaxBaselineQueryError,
  type TaxBaselineQueryRpcClient,
} from "../../../../../server/queries/tax-baseline.ts";
import type { FinanceTaxCode, FinanceTaxRuleVersion } from "../../../../../server/contracts/tax-baseline/tax-baseline.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { TaxCodeTable, RuleVersionTable, UnconfirmedRateBanner } from "./tax-settings-admin-panel.tsx";

/**
 * Tax settings console — the configuration surface for `RPD-016`.
 *
 * `RPD-016` records that the seeded Indonesia PPN rate is SME/legal-unconfirmed. That has been
 * carried as a launch blocker on the reasoning that an agent must not invent a statutory rate.
 * That reasoning is right, and it points at the wrong remedy: the rate is *data*, and
 * `app.finance_tax_rule_versions` already models it as versioned data with an effective window,
 * an approval, and an evidence reference.
 *
 * What was missing is a place to see and manage it. With this console, confirming the rate stops
 * being a code change and becomes what it actually is — a tax adviser reading a figure, and
 * someone recording it with its evidence. **No release, no migration.**
 *
 * Composes `app.list_finance_tax_codes` and `app.list_finance_tax_rule_versions`, both
 * `FIN:View`-gated; this page's own guard only confirms the coarse tenant-admin boundary.
 *
 * **Read-only by design.** Creating and approving a rate version have their own audited RPCs with
 * their own authority checks. This page's job is to make an unconfirmed rate impossible to
 * overlook, which is the part that was genuinely absent.
 */

function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): TaxBaselineQueryRpcClient {
  return client as unknown as TaxBaselineQueryRpcClient;
}

export default async function TaxSettingsAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const client = toQueryClient(await createSupabaseServerClient());

  let loadFailed = false;
  let codes: FinanceTaxCode[] = [];
  let allRules: FinanceTaxRuleVersion[] = [];

  try {
    codes = await listFinanceTaxCodes(client, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId });
    // One bounded read per code rather than a single unbounded one: the RPC is scoped by tax code,
    // and reading them together keeps the "which rate is in force" answer per-code and exact.
    const perCode = await Promise.all(
      codes.map((code) =>
        listFinanceTaxRuleVersions(client, { tenantId: access.tenant.id, taxCodeId: code.id, actorAuthUserId: access.authUserId }),
      ),
    );
    allRules = perCode.flat();
  } catch (error) {
    if (!(error instanceof TaxBaselineQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-xl font-semibold text-text-primary">Tax settings</h1>
        <ErrorState description="Something went wrong loading tax codes and rates. Do not read this as confirmation that the configured rates are correct." />
      </div>
    );
  }

  const rulesByCode = new Map<string, FinanceTaxRuleVersion[]>();
  for (const rule of allRules) {
    const list = rulesByCode.get(rule.taxCodeId);
    if (list) list.push(rule);
    else rulesByCode.set(rule.taxCodeId, [rule]);
  }
  // Newest effective date first, so the rate that matters is the top row.
  for (const list of rulesByCode.values()) {
    list.sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom));
  }

  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Tax settings</h1>
        <p className="text-sm text-text-secondary">
          Tax codes and their rate versions. A rate is versioned with an effective date range, so a statutory change is
          recorded as a new version rather than by overwriting history — past invoices keep the rate they were actually
          computed with. This console is <strong>read-only</strong>; creating and approving a rate version go through
          their own audited operations.
        </p>
      </div>

      <UnconfirmedRateBanner rules={allRules} />

      <section aria-labelledby="codes-heading" className="flex flex-col gap-3">
        <h2 id="codes-heading" className="text-lg font-semibold text-text-primary">
          Tax codes ({codes.length})
        </h2>
        <TaxCodeTable codes={codes} rulesByCode={rulesByCode} />
      </section>

      {codes.map((code) => (
        <section key={code.id} aria-labelledby={`rules-${code.id}`} className="flex flex-col gap-3">
          <h2 id={`rules-${code.id}`} className="text-lg font-semibold text-text-primary">
            {code.code} — rate history
          </h2>
          <RuleVersionTable code={code} rules={rulesByCode.get(code.id) ?? []} />
        </section>
      ))}

      <section aria-labelledby="confirm-heading" className="flex flex-col gap-2">
        <h2 id="confirm-heading" className="text-lg font-semibold text-text-primary">
          Confirming a rate
        </h2>
        <p className="text-sm text-text-secondary">
          A rate counts as confirmed here when it is <strong>approved</strong>, is <strong>not an example fixture</strong>,
          and carries <strong>evidence</strong> — a note or an attached document recording who said so and on what basis.
          All three matter: an approved rate with no evidence cannot be defended later, and an example fixture is a
          placeholder regardless of its status.
        </p>
      </section>
    </div>
  );
}
