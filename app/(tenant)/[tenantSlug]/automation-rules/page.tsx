import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listAutomationRules, AutomationRuleQueryError } from "../../../../server/queries/automation-rule.ts";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { AutomationRuleManagementPanel } from "./automation-rule-management-panel.tsx";
import { createAutomationRuleAction } from "./actions.ts";

/**
 * Automation Rule Engine (IAE-007, Prompt 335 §21): condition/action
 * automation with versioning, approval-gated publish, dry run, and
 * loop/storm guardrails. Reuses resolveCommercialAccessForRequest, the same
 * domain-agnostic access gate every other cross-domain Phase 9 surface
 * already established.
 */
export default async function AutomationRulesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let rules: Awaited<ReturnType<typeof listAutomationRules>> = [];
  let loadFailed = false;
  try {
    rules = await listAutomationRules(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof AutomationRuleQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading automation rules. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Automation rules</h1>
        <p className="text-xs text-neutral-500">
          Condition/action automation for notifications, workflow steps and background jobs. Publishing a rule always requires a real, tenant-configured approval decision -- an
          AI-drafted rule can never publish itself.
        </p>
      </div>

      <AutomationRuleManagementPanel tenantSlug={tenantSlug} rules={rules} createAction={createAutomationRuleAction.bind(null, tenantSlug)} />
    </div>
  );
}
