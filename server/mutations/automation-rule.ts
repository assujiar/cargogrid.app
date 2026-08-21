/**
 * Automation Rule Engine mutation primitives (IAE-007, Prompt 335). Thin,
 * typed wrappers around app.create_automation_rule / app.set_automation_rule_definition /
 * app.dry_run_automation_rule / app.request_automation_rule_publish_approval /
 * app.decide_automation_rule_publish_approval / app.publish_automation_rule_version /
 * app.set_automation_rule_status
 * (supabase/migrations/20260803010000_create_intelligence_automation_rule_engine.sql).
 * app.decide_automation_rule_publish_approval is this capability's own
 * domain-scoped SECURITY DEFINER proxy to app.decide_approval_step (PLT-123,
 * service_role-only) -- calling the generic RPC directly from an
 * authenticated session is not possible (no grant), so a bespoke wrapper is
 * used here rather than server/mutations/approval.ts's own decideApprovalStep.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateAutomationRuleInputSchema,
  SetAutomationRuleDefinitionInputSchema,
  DryRunAutomationRuleInputSchema,
  RequestAutomationRulePublishApprovalInputSchema,
  DecideAutomationRulePublishApprovalInputSchema,
  PublishAutomationRuleVersionInputSchema,
  SetAutomationRuleStatusInputSchema,
  parseAutomationRule,
  parseAutomationRuleVersion,
  parseDryRunAutomationRuleResult,
  type CreateAutomationRuleInput,
  type SetAutomationRuleDefinitionInput,
  type DryRunAutomationRuleInput,
  type RequestAutomationRulePublishApprovalInput,
  type DecideAutomationRulePublishApprovalInput,
  type PublishAutomationRuleVersionInput,
  type SetAutomationRuleStatusInput,
  type AutomationRule,
  type AutomationRuleVersion,
  type DryRunAutomationRuleResult,
} from "../contracts/automation-rule/automation-rule.ts";
import { parseApprovalRequest, parseApprovalRequestStep, type ApprovalRequest, type ApprovalRequestStep } from "../contracts/approval/approval.ts";

export type AutomationRuleMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const AUTOMATION_RULE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "automation_rule_not_found",
  "automation_rule_no_open_draft",
  "automation_rule_unsafe_definition",
  "automation_rule_missing_trigger",
  "automation_rule_unsafe_conditions",
  "automation_rule_invalid_conditions",
  "automation_rule_condition_missing_field",
  "automation_rule_condition_invalid_operator",
  "automation_rule_condition_missing_value",
  "automation_rule_unsafe_actions",
  "automation_rule_missing_actions",
  "automation_rule_too_many_actions",
  "automation_rule_invalid_action_type",
  "automation_rule_action_missing_notification_type",
  "automation_rule_action_unknown_notification_type",
  "automation_rule_action_missing_channel",
  "automation_rule_action_missing_recipient_field",
  "automation_rule_action_missing_instance_field",
  "automation_rule_action_missing_to_state",
  "automation_rule_action_invalid_job_type",
  "automation_rule_publish_approval_not_configured",
  "automation_rule_publish_approval_not_found",
  "automation_rule_publish_approval_mismatch",
  "automation_rule_publish_approval_step_not_found",
  "automation_rule_publish_approval_wrong_domain",
  "automation_rule_publish_not_approved",
  "automation_rule_publish_content_changed",
  "automation_rule_invalid_status",
] as const;
type KnownAutomationRuleMutationErrorCode = (typeof AUTOMATION_RULE_KNOWN_MUTATION_ERROR_CODES)[number];
export type AutomationRuleMutationErrorCode = KnownAutomationRuleMutationErrorCode | "mutation_failed" | "invalid_response";

export class AutomationRuleMutationError extends Error {
  readonly code: AutomationRuleMutationErrorCode;

  constructor(code: AutomationRuleMutationErrorCode, message: string) {
    super(message);
    this.name = "AutomationRuleMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AutomationRuleMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (AUTOMATION_RULE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownAutomationRuleMutationErrorCode)
    : "mutation_failed";
}

/** INTHUB:Configure-gated. Creates the rule plus a real, empty version-1 draft in one transaction. */
export async function createAutomationRule(client: AutomationRuleMutationRpcClient, input: CreateAutomationRuleInput): Promise<AutomationRule> {
  const parsedInput = CreateAutomationRuleInputSchema.parse(input);
  const { data, error } = await client.rpc("create_automation_rule", {
    p_tenant_id: parsedInput.tenantId,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AutomationRuleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AutomationRuleMutationError("invalid_response", "create_automation_rule returned no row");
  }
  return parseAutomationRule(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated, draft-only. Structural (never business) validation only -- full publish-time validation happens separately. */
export async function setAutomationRuleDefinition(client: AutomationRuleMutationRpcClient, input: SetAutomationRuleDefinitionInput): Promise<AutomationRuleVersion> {
  const parsedInput = SetAutomationRuleDefinitionInputSchema.parse(input);
  const { data, error } = await client.rpc("set_automation_rule_definition", {
    p_rule_id: parsedInput.ruleId,
    p_trigger_event_type: parsedInput.triggerEventType,
    p_conditions: parsedInput.conditions,
    p_actions: parsedInput.actions,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AutomationRuleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AutomationRuleMutationError("invalid_response", "set_automation_rule_definition returned no row");
  }
  return parseAutomationRuleVersion(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated. Pure, side-effect-free simulation against the rule's own current draft. */
export async function dryRunAutomationRule(client: AutomationRuleMutationRpcClient, input: DryRunAutomationRuleInput): Promise<DryRunAutomationRuleResult> {
  const parsedInput = DryRunAutomationRuleInputSchema.parse(input);
  const { data, error } = await client.rpc("dry_run_automation_rule", {
    p_rule_id: parsedInput.ruleId,
    p_sample_event_payload: parsedInput.sampleEventPayload,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AutomationRuleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AutomationRuleMutationError("invalid_response", "dry_run_automation_rule returned no row");
  }
  return parseDryRunAutomationRuleResult(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated. Opens a real approval request against the tenant's own published approval:automation_rule_publish definition, bound to the exact draft version. */
export async function requestAutomationRulePublishApproval(
  client: AutomationRuleMutationRpcClient,
  input: RequestAutomationRulePublishApprovalInput,
): Promise<ApprovalRequest> {
  const parsedInput = RequestAutomationRulePublishApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("request_automation_rule_publish_approval", {
    p_rule_id: parsedInput.ruleId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AutomationRuleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AutomationRuleMutationError("invalid_response", "request_automation_rule_publish_approval returned no row");
  }
  return parseApprovalRequest(data as Record<string, unknown>);
}

/** A real, eligible tenant approver decides one step -- proxies app.decide_approval_step (PLT-123, service_role-only) through this domain's own scoped wrapper, which refuses a step outside an automation_rule_version request. */
export async function decideAutomationRulePublishApproval(client: AutomationRuleMutationRpcClient, input: DecideAutomationRulePublishApprovalInput): Promise<ApprovalRequestStep> {
  const parsedInput = DecideAutomationRulePublishApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_automation_rule_publish_approval", {
    p_request_step_id: parsedInput.requestStepId,
    p_decision: parsedInput.decision,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new AutomationRuleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AutomationRuleMutationError("invalid_response", "decide_automation_rule_publish_approval returned no row");
  }
  return parseApprovalRequestStep(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated. Requires an approved request bound to the exact draft being published; opens a fresh draft. */
export async function publishAutomationRuleVersion(client: AutomationRuleMutationRpcClient, input: PublishAutomationRuleVersionInput): Promise<AutomationRule> {
  const parsedInput = PublishAutomationRuleVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_automation_rule_version", {
    p_rule_id: parsedInput.ruleId,
    p_approval_request_id: parsedInput.approvalRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AutomationRuleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AutomationRuleMutationError("invalid_response", "publish_automation_rule_version returned no row");
  }
  return parseAutomationRule(data as Record<string, unknown>);
}

/** INTHUB:Configure-gated. Pause/resume/archive -- a paused/archived rule is structurally excluded from evaluation. */
export async function setAutomationRuleStatus(client: AutomationRuleMutationRpcClient, input: SetAutomationRuleStatusInput): Promise<AutomationRule> {
  const parsedInput = SetAutomationRuleStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_automation_rule_status", {
    p_rule_id: parsedInput.ruleId,
    p_status: parsedInput.status,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AutomationRuleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AutomationRuleMutationError("invalid_response", "set_automation_rule_status returned no row");
  }
  return parseAutomationRule(data as Record<string, unknown>);
}
