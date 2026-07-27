import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listQuotationApprovalRuleVersions, QuotationApprovalQueryError } from "../../../../../server/queries/quotation-approval.ts";
import type { QuotationApprovalRuleVersion } from "../../../../../server/contracts/quotation/quotation-approval.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { QUOTATION_APPROVAL_RULE_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { createQuotationApprovalRuleVersionAction, publishQuotationApprovalRuleVersionAction } from "./actions.ts";
import { CreateApprovalRuleForm } from "./create-approval-rule-form.tsx";

/**
 * Quotation Approval Rule list (COM-153, CG-S7-COM-012). Tenant-wide reference/policy
 * data, never field-masked -- app.quotation_approval_rules is read directly, not through a
 * masking view (mirrors margin-rules/page.tsx, COM-150). A published rule here is what
 * app.submit_quotation evaluates at submission time; publishing the approval *routing*
 * definition itself (who approves) is this capability's own disclosed scope boundary --
 * done via the generic Platform Configuration/Approval Engine RPCs directly, not through
 * this UI (supabase/migrations/20260724270000_create_commercial_quotation_approval.sql's
 * own migration header).
 */
export default async function ApprovalRulesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let rules: QuotationApprovalRuleVersion[];
  let loadFailed = false;
  try {
    rules = await listQuotationApprovalRuleVersions(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof QuotationApprovalQueryError)) {
      throw error;
    }
    loadFailed = true;
    rules = [];
  }

  const publishedRule = rules.find((rule) => rule.status === "published") ?? null;
  const boundCreateAction = createQuotationApprovalRuleVersionAction.bind(null, tenantSlug);

  const columns: readonly DataTableColumn<QuotationApprovalRuleVersion>[] = [
    { key: "minMarginPct", header: "Min margin %", render: (rule) => (rule.minMarginPct !== null ? `${rule.minMarginPct}%` : "—") },
    { key: "maxDiscountPct", header: "Max discount %", render: (rule) => (rule.maxDiscountPct !== null ? `${rule.maxDiscountPct}%` : "—") },
    { key: "minValueAmount", header: "Min value", render: (rule) => (rule.minValueAmount !== null ? rule.minValueAmount : "—") },
    {
      key: "status",
      header: "Status",
      render: (rule) => {
        const { tone, label } = QUOTATION_APPROVAL_RULE_STATUS_TONE_MAP[rule.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "action",
      header: "Action",
      render: (rule) =>
        rule.status === "draft" ? (
          <form action={publishQuotationApprovalRuleVersionAction.bind(null, tenantSlug, rule.id, rule.recordVersion, publishedRule?.id ?? null)}>
            <button type="submit" className="text-sm font-medium text-primary underline">
              Publish{publishedRule ? " (supersedes current)" : ""}
            </button>
          </form>
        ) : (
          "—"
        ),
    },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Quotation approval rules</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading approval rules. Please try again.</p>
        </div>
      ) : (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Rule versions</h2>
          <div className="mt-2">
            <DataTable
              caption="Quotation approval rule versions"
              columns={columns}
              rows={rules}
              rowKey={(rule) => rule.id}
              emptyMessage="No approval rules yet. Every quotation submits without routing until one is published below."
            />
          </div>
        </div>
      )}

      <CreateApprovalRuleForm action={boundCreateAction} />
    </div>
  );
}
