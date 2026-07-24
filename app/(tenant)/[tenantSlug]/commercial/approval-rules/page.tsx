import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listQuotationApprovalRuleVersions, QuotationApprovalQueryError } from "../../../../../server/queries/quotation-approval.ts";
import type { QuotationApprovalRuleVersion } from "../../../../../server/contracts/quotation/quotation-approval.ts";
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
          {rules.length === 0 ? (
            <p className="mt-2 text-sm text-neutral-600">No approval rules yet. Every quotation submits without routing until one is published below.</p>
          ) : (
            <table className="mt-2 w-full border-collapse text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-left text-neutral-600">
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Min margin %
                  </th>
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Max discount %
                  </th>
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Min value
                  </th>
                  <th scope="col" className="py-2 pr-4 font-medium">
                    Status
                  </th>
                  <th scope="col" className="py-2 font-medium">
                    Action
                  </th>
                </tr>
              </thead>
              <tbody>
                {rules.map((rule) => (
                  <tr key={rule.id} className="border-b border-neutral-100">
                    <td className="py-2 pr-4 text-neutral-900">{rule.minMarginPct !== null ? `${rule.minMarginPct}%` : "—"}</td>
                    <td className="py-2 pr-4 text-neutral-600">{rule.maxDiscountPct !== null ? `${rule.maxDiscountPct}%` : "—"}</td>
                    <td className="py-2 pr-4 text-neutral-600">{rule.minValueAmount !== null ? rule.minValueAmount : "—"}</td>
                    <td className="py-2 pr-4 text-neutral-600">{rule.status}</td>
                    <td className="py-2 text-neutral-600">
                      {rule.status === "draft" ? (
                        <form action={publishQuotationApprovalRuleVersionAction.bind(null, tenantSlug, rule.id, rule.recordVersion, publishedRule?.id ?? null)}>
                          <button type="submit" className="text-sm font-medium text-primary underline">
                            Publish{publishedRule ? " (supersedes current)" : ""}
                          </button>
                        </form>
                      ) : (
                        "—"
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      <CreateApprovalRuleForm action={boundCreateAction} />
    </div>
  );
}
