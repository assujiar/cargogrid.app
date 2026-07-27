import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listMarginRuleVersions, MarginQueryError } from "../../../../../server/queries/margin.ts";
import type { MarginRuleVersion } from "../../../../../server/contracts/margin/margin.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { MARGIN_RULE_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import { createMarginRuleVersionAction, publishMarginRuleVersionAction } from "./actions.ts";
import { CreateMarginRuleForm } from "./create-margin-rule-form.tsx";

/**
 * Margin Rule list (COM-150, CG-S7-COM-009). Tenant-wide reference/policy data, never
 * field-masked (COM-150 migration header) -- app.margin_rule_versions is read directly,
 * not through a masking view. app.create_margin_rule_version/app.publish_margin_rule_version
 * are gated by ordinary COM:Create/COM:Approve (mirroring app.create_sales_plan/
 * app.publish_sales_plan, COM-146), not app.is_support_grant_authority -- this form
 * renders for every Commercial portal user; an actor lacking the right permission sees
 * the real server-side denial, the same posture every prior Commercial page already uses.
 */
export default async function MarginRulesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let rules: MarginRuleVersion[];
  let loadFailed = false;
  try {
    rules = await listMarginRuleVersions(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof MarginQueryError)) {
      throw error;
    }
    loadFailed = true;
    rules = [];
  }

  const publishedRule = rules.find((rule) => rule.status === "published") ?? null;
  const boundCreateAction = createMarginRuleVersionAction.bind(null, tenantSlug);

  const columns: readonly DataTableColumn<MarginRuleVersion>[] = [
    { key: "minimumMarginPct", header: "Minimum margin %", render: (rule) => `${rule.minimumMarginPct}%` },
    { key: "roundingMode", header: "Rounding", render: (rule) => rule.roundingMode },
    {
      key: "status",
      header: "Status",
      render: (rule) => {
        const { tone, label } = MARGIN_RULE_STATUS_TONE_MAP[rule.status];
        return <StatusBadge tone={tone} label={label} />;
      },
    },
    {
      key: "action",
      header: "Action",
      render: (rule) =>
        rule.status === "draft" ? (
          <form action={publishMarginRuleVersionAction.bind(null, tenantSlug, rule.id, rule.recordVersion, publishedRule?.id ?? null)}>
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
      <h1 className="text-xl font-semibold text-neutral-900">Margin rules</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading margin rules. Please try again.</p>
        </div>
      ) : (
        <div className="rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Rule versions</h2>
          <div className="mt-2">
            <DataTable
              caption="Margin rule versions"
              columns={columns}
              rows={rules}
              rowKey={(rule) => rule.id}
              emptyMessage="No margin rules yet. Create one below."
            />
          </div>
        </div>
      )}

      <CreateMarginRuleForm action={boundCreateAction} />
    </div>
  );
}
