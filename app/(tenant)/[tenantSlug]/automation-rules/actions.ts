"use server";

/**
 * Automation Rule Engine server actions (IAE-007, Prompt 335). Uses the
 * RLS-scoped `authenticated` client -- every app.* RPC below is
 * INTHUB:Configure-gated and performs its own permission check in-body,
 * mirroring every prior report/dashboard/saved-view/scheduled-report
 * action's convention. Deciding a publish approval reuses
 * server/mutations/approval.ts's own decideApprovalStep directly (PLT-123),
 * never forked.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import {
  createAutomationRule,
  setAutomationRuleDefinition,
  dryRunAutomationRule,
  requestAutomationRulePublishApproval,
  decideAutomationRulePublishApproval,
  publishAutomationRuleVersion,
  setAutomationRuleStatus,
  AutomationRuleMutationError,
} from "../../../../server/mutations/automation-rule.ts";
import { AutomationConditionsSchema, AutomationActionsSchema, type AutomationRuleStatus, type DryRunAutomationRuleResult } from "../../../../server/contracts/automation-rule/automation-rule.ts";

export interface AutomationRuleActionState {
  readonly error: string | null;
}

export interface DryRunActionState {
  readonly error: string | null;
  readonly result: DryRunAutomationRuleResult | null;
}

const OK: AutomationRuleActionState = { error: null };
const NO_ACCESS: AutomationRuleActionState = { error: "You don't have access to this organization's workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function parseJsonArray(raw: FormDataEntryValue | null): unknown[] {
  const text = String(raw ?? "").trim();
  if (!text) return [];
  const parsed: unknown = JSON.parse(text);
  if (!Array.isArray(parsed)) {
    throw new Error("must be a JSON array");
  }
  return parsed;
}

function parseJsonObject(raw: FormDataEntryValue | null): Record<string, unknown> {
  const text = String(raw ?? "").trim();
  if (!text) return {};
  const parsed: unknown = JSON.parse(text);
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("must be a JSON object");
  }
  return parsed as Record<string, unknown>;
}

export async function createAutomationRuleAction(tenantSlug: string, _prevState: AutomationRuleActionState, formData: FormData): Promise<AutomationRuleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await createAutomationRule(supabase, { tenantId: access.tenant.id, name, description, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AutomationRuleMutationError) return { error: `Could not create this rule: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/automation-rules`);
  return OK;
}

export async function setAutomationRuleDefinitionAction(tenantSlug: string, ruleId: string, _prevState: AutomationRuleActionState, formData: FormData): Promise<AutomationRuleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const triggerEventType = String(formData.get("triggerEventType") ?? "").trim();
  let conditions: ReturnType<typeof AutomationConditionsSchema.parse>;
  let actions: ReturnType<typeof AutomationActionsSchema.parse>;
  try {
    conditions = AutomationConditionsSchema.parse(parseJsonArray(formData.get("conditions")));
    actions = AutomationActionsSchema.parse(parseJsonArray(formData.get("actions")));
  } catch {
    return { error: "Conditions must be a JSON array of {field,operator,value}; actions must be a JSON array of {action_type,...} objects." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await setAutomationRuleDefinition(supabase, {
      ruleId,
      triggerEventType,
      conditions,
      actions,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof AutomationRuleMutationError) return { error: `Could not save this definition: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/automation-rules/${ruleId}`);
  return OK;
}

export async function dryRunAutomationRuleAction(tenantSlug: string, ruleId: string, _prevState: DryRunActionState, formData: FormData): Promise<DryRunActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, result: null };

  let sampleEventPayload: Record<string, unknown>;
  try {
    sampleEventPayload = parseJsonObject(formData.get("sampleEventPayload"));
  } catch {
    return { error: "Sample event payload must be a valid JSON object.", result: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const result = await dryRunAutomationRule(supabase, { ruleId, sampleEventPayload, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    return { error: null, result };
  } catch (error) {
    if (error instanceof AutomationRuleMutationError) return { error: `Could not dry-run this rule: ${error.message}`, result: null };
    throw error;
  }
}

export async function requestAutomationRulePublishApprovalAction(
  tenantSlug: string,
  ruleId: string,
  _prevState: AutomationRuleActionState,
  _formData: FormData,
): Promise<AutomationRuleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await requestAutomationRulePublishApproval(supabase, { ruleId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AutomationRuleMutationError) return { error: `Could not request publish approval: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/automation-rules/${ruleId}`);
  return OK;
}

export async function decideAutomationRulePublishApprovalAction(
  tenantSlug: string,
  ruleId: string,
  stepId: string,
  decision: "approved" | "rejected",
  _prevState: AutomationRuleActionState,
  _formData: FormData,
): Promise<AutomationRuleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await decideAutomationRulePublishApproval(supabase, { requestStepId: stepId, decision, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AutomationRuleMutationError) return { error: `Could not record this decision: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/automation-rules/${ruleId}`);
  return OK;
}

export async function publishAutomationRuleVersionAction(
  tenantSlug: string,
  ruleId: string,
  approvalRequestId: string,
  _prevState: AutomationRuleActionState,
  _formData: FormData,
): Promise<AutomationRuleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishAutomationRuleVersion(supabase, { ruleId, approvalRequestId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AutomationRuleMutationError) return { error: `Could not publish this rule: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/automation-rules/${ruleId}`);
  revalidatePath(`/${tenantSlug}/automation-rules`);
  return OK;
}

export async function setAutomationRuleStatusAction(
  tenantSlug: string,
  ruleId: string,
  status: AutomationRuleStatus,
  _prevState: AutomationRuleActionState,
  _formData: FormData,
): Promise<AutomationRuleActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await setAutomationRuleStatus(supabase, { ruleId, status, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AutomationRuleMutationError) return { error: `Could not change this rule's status: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/automation-rules/${ruleId}`);
  revalidatePath(`/${tenantSlug}/automation-rules`);
  return OK;
}
