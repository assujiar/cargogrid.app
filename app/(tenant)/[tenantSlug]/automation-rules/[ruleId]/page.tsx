import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  getAutomationRuleById,
  listAutomationRuleVersions,
  listAutomationRuleExecutions,
  getLatestAutomationRulePublishApprovalRequest,
  listApprovalRequestSteps,
  AutomationRuleQueryError,
} from "../../../../../server/queries/automation-rule.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { AutomationRuleDetailPanel } from "./automation-rule-detail-panel.tsx";
import {
  setAutomationRuleDefinitionAction,
  dryRunAutomationRuleAction,
  requestAutomationRulePublishApprovalAction,
  decideAutomationRulePublishApprovalAction,
  publishAutomationRuleVersionAction,
  setAutomationRuleStatusAction,
} from "../actions.ts";

/**
 * Automation Rule detail page (IAE-007, Prompt 335): the current draft
 * editor, a pure dry-run preview, the approval-gated publish flow (request
 * approval -> decide -> publish), pause/resume/archive controls, and the
 * real execution log (completed/suppressed/failed).
 */
export default async function AutomationRuleDetailPage({ params }: { params: Promise<{ tenantSlug: string; ruleId: string }> }) {
  const { tenantSlug, ruleId } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    rule: NonNullable<Awaited<ReturnType<typeof getAutomationRuleById>>>;
    versions: Awaited<ReturnType<typeof listAutomationRuleVersions>>;
    executions: Awaited<ReturnType<typeof listAutomationRuleExecutions>>;
    approvalRequest: Awaited<ReturnType<typeof getLatestAutomationRulePublishApprovalRequest>>;
    approvalSteps: Awaited<ReturnType<typeof listApprovalRequestSteps>>;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const rule = await getAutomationRuleById(supabase, ruleId);
    if (!rule) {
      notFound();
    }
    const [versions, executions] = await Promise.all([listAutomationRuleVersions(supabase, ruleId), listAutomationRuleExecutions(supabase, ruleId)]);
    const draft = versions.find((v) => v.status === "draft") ?? null;
    const approvalRequest = draft ? await getLatestAutomationRulePublishApprovalRequest(supabase, draft.id) : null;
    const approvalSteps = approvalRequest ? await listApprovalRequestSteps(supabase, approvalRequest.id) : [];
    loaded = { rule, versions, executions, approvalRequest, approvalSteps };
  } catch (error) {
    if (!(error instanceof AutomationRuleQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this automation rule. Please try again." />;
  }

  const { rule, versions, executions, approvalRequest, approvalSteps } = loaded;

  return (
    <AutomationRuleDetailPanel
      rule={rule}
      versions={versions}
      executions={executions}
      approvalRequest={approvalRequest}
      approvalSteps={approvalSteps}
      setDefinitionAction={setAutomationRuleDefinitionAction.bind(null, tenantSlug, ruleId)}
      dryRunAction={dryRunAutomationRuleAction.bind(null, tenantSlug, ruleId)}
      requestApprovalAction={requestAutomationRulePublishApprovalAction.bind(null, tenantSlug, ruleId)}
      decideApprovalActionFor={(stepId, decision) => decideAutomationRulePublishApprovalAction.bind(null, tenantSlug, ruleId, stepId, decision)}
      publishActionFor={(approvalRequestId) => publishAutomationRuleVersionAction.bind(null, tenantSlug, ruleId, approvalRequestId)}
      setStatusActionFor={(status) => setAutomationRuleStatusAction.bind(null, tenantSlug, ruleId, status)}
    />
  );
}
