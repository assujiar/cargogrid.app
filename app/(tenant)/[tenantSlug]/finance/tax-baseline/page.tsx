import { notFound } from "next/navigation";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listFinanceTaxCodes, listFinanceTaxRuleVersions, TaxBaselineQueryError } from "../../../../../server/queries/tax-baseline.ts";
import type { FinanceTaxCode, FinanceTaxRuleVersion } from "../../../../../server/contracts/tax-baseline/tax-baseline.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FINANCE_TAX_RULE_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import {
  createFinanceTaxRuleDraftAction,
  attachFinanceTaxRuleEvidenceAction,
  discardFinanceTaxRuleDraftAction,
  approveFinanceTaxRuleAction,
  calculateFinanceTaxAction,
} from "./actions.ts";
import {
  CreateFinanceTaxRuleDraftForm,
  AttachFinanceTaxRuleEvidenceForm,
  DiscardFinanceTaxRuleDraftForm,
  ApproveFinanceTaxRuleForm,
  CalculateFinanceTaxForm,
} from "./tax-baseline-forms.tsx";

/**
 * Tax Baseline workspace (FIN-195, CG-S9-FIN-006). An Indonesia-first,
 * configurable tax-code catalogue, a bounded rule-version list (create-draft
 * form, per-row evidence-attach/discard/approve actions -- the same bounded
 * "no pagination needed for a bounded reference set" precedent FIN-192/193/194
 * already established), and a read-only calculate-preview tool. No rate or
 * legal conclusion is ever asserted by this page -- every rule starts as an
 * unverified draft and can only calculate once an authorized SME has
 * attached evidence and approved it.
 */
export default async function TaxBaselinePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let taxCodes: FinanceTaxCode[] = [];
  let rules: FinanceTaxRuleVersion[] = [];
  let loadFailed = false;
  try {
    [taxCodes, rules] = await Promise.all([
      listFinanceTaxCodes(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId }),
      listFinanceTaxRuleVersions(supabase, { tenantId: access.tenant.id, taxCodeId: null, actorAuthUserId: access.authUserId }),
    ]);
  } catch (error) {
    if (!(error instanceof TaxBaselineQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  const taxCodeById = new Map(taxCodes.map((code) => [code.id, code]));

  const codeColumns: readonly DataTableColumn<FinanceTaxCode>[] = [
    { key: "code", header: "Code", render: (code) => code.code },
    { key: "name", header: "Name", render: (code) => code.name },
    { key: "taxType", header: "Type", render: (code) => code.taxType },
    { key: "jurisdictionCountry", header: "Jurisdiction", render: (code) => code.jurisdictionCountry },
    {
      key: "isRecoverable",
      header: "Recoverable",
      render: (code) => <StatusBadge tone={code.isRecoverable ? "info" : "neutral"} label={code.isRecoverable ? "Yes" : "No"} />,
    },
  ];

  const ruleColumns: readonly DataTableColumn<FinanceTaxRuleVersion>[] = [
    { key: "taxCode", header: "Tax code", render: (rule) => taxCodeById.get(rule.taxCodeId)?.code ?? rule.taxCodeId },
    { key: "rateBasis", header: "Basis", render: (rule) => rule.rateBasis },
    { key: "rateValue", header: "Rate", render: (rule) => rule.rateValue },
    { key: "effectiveFrom", header: "Effective from", render: (rule) => rule.effectiveFrom },
    { key: "effectiveTo", header: "Effective to", render: (rule) => rule.effectiveTo ?? "—" },
    {
      key: "fixture",
      header: "Fixture",
      render: (rule) => (rule.isExampleFixture ? <StatusBadge tone="warning" label="Example only" /> : "—"),
    },
    {
      key: "status",
      header: "Status",
      render: (rule) => {
        const { tone, label } = FINANCE_TAX_RULE_STATUS_TONE_MAP[rule.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "actions",
      header: "Actions",
      render: (rule) =>
        rule.status === "draft" ? (
          <div className="flex flex-wrap gap-2">
            {rule.evidenceNote || rule.evidenceReferenceFileId ? null : <AttachFinanceTaxRuleEvidenceForm action={attachFinanceTaxRuleEvidenceAction.bind(null, tenantSlug, rule.id, rule.recordVersion)} />}
            <ApproveFinanceTaxRuleForm action={approveFinanceTaxRuleAction.bind(null, tenantSlug, rule.id, rule.recordVersion)} />
            <DiscardFinanceTaxRuleDraftForm action={discardFinanceTaxRuleDraftAction.bind(null, tenantSlug, rule.id, rule.recordVersion)} />
          </div>
        ) : (
          "—"
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold text-text-primary">Tax Baseline</h1>
        <p className="text-sm text-text-secondary">
          Indonesia-first, configurable tax codes and versioned, SME-approved rules. No rate, filing rule, or legal conclusion is invented by this workspace -- every rule starts as an unverified draft and can only calculate once an
          authorized SME attaches evidence and approves it.
        </p>
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-text-primary">Tax code catalogue</h2>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading tax codes. Please try again." />
        ) : (
          <DataTable caption="Tax codes" columns={codeColumns} rows={taxCodes} rowKey={(code) => code.id} emptyMessage="No tax codes registered." />
        )}
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold text-text-primary">Tax rule versions</h2>
        {loadFailed ? (
          <ErrorState description="Something went wrong loading tax rules. Please try again." />
        ) : rules.length === 0 ? (
          <EmptyState title="No tax rules yet" description="Create a draft rule below." />
        ) : (
          <DataTable caption="Tax rule versions" columns={ruleColumns} rows={rules} rowKey={(rule) => rule.id} emptyMessage="No tax rules yet." />
        )}
      </div>

      <CreateFinanceTaxRuleDraftForm action={createFinanceTaxRuleDraftAction.bind(null, tenantSlug)} taxCodes={taxCodes} />
      <CalculateFinanceTaxForm action={calculateFinanceTaxAction.bind(null, tenantSlug)} />
    </div>
  );
}
