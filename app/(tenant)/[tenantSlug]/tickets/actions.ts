"use server";

/**
 * Ticketing Server Actions (HRT-286, CG-S12-HRT-014). Mirrors
 * app/(tenant)/[tenantSlug]/hris/employees/actions.ts's own shape exactly:
 * resolve portal access, call the typed mutation wrapper, translate a known
 * mutation error into a plain-language message, revalidate the affected
 * path(s). One shared file for both the list route and the
 * `[ticketId]` detail route, matching that same precedent.
 *
 * Every write here is permission-gated at the RPC layer itself (TKT:Edit/
 * Assign/Close/Reopen, or requester/queue-staff structural scope, depending
 * on the action -- see the migration's own decision 5) -- this file never
 * re-implements or weakens that gate, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveTicketAccessForRequest } from "../../../../lib/portal/resolve-ticket-access.server.ts";
import {
  createTicketQueue,
  createTicketCategory,
  addTicketQueueMember,
  removeTicketQueueMember,
  createTicket,
  replyToTicket,
  redactTicketMessage,
  addTicketWatcher,
  removeTicketWatcher,
  assignTicket,
  transferTicketQueue,
  updateTicketClassification,
  transitionTicketStatus,
  setTicketCategoryCustomerVisibility,
  startTicketSlaClock,
  pauseTicketSlaClock,
  resumeTicketSlaClock,
  createSlaCalendar,
  createSlaCalendarVersion,
  addSlaCalendarBusinessHours,
  addSlaCalendarHoliday,
  publishSlaCalendarVersion,
  createSlaPolicy,
  createSlaPolicyVersion,
  publishSlaPolicyVersion,
  createTicketRoutingRule,
  createTicketRoutingRuleVersion,
  publishTicketRoutingRuleVersion,
  claimTicket,
  acceptTicketAssignment,
  declineTicketAssignment,
  autoRouteTicket,
  createTicketEscalationPolicy,
  createTicketEscalationPolicyVersion,
  addTicketEscalationLevel,
  publishTicketEscalationPolicyVersion,
  escalateTicket,
  acknowledgeTicketEscalation,
  resolveTicketEscalation,
  suppressTicketEscalation,
  revokeTicketEscalationSuppression,
  linkTicketRecord,
  unlinkTicketRecord,
  recordTicketLinkAccessDenial,
  recordTicketLinkSummaryAccess,
  TicketMutationError,
} from "../../../../server/mutations/ticketing.ts";
import { previewTicketRouting, previewTicketEscalation, searchTicketLinkCandidates, TicketQueryError } from "../../../../server/queries/ticketing.ts";
import { TICKET_LINK_ENTITY_TYPES, TICKET_LINK_RELATIONSHIPS } from "../../../../server/contracts/ticketing/ticketing.ts";
import type { TicketRoutingPreviewRow, TicketEscalationPreviewRow, TicketLinkCandidateRow } from "../../../../server/contracts/ticketing/ticketing.ts";
import type {
  MessageVisibility,
  TicketPriority,
  TicketStatus,
  SlaPauseReasonCode,
  TicketChannel,
  TicketRoutingAssignmentMode,
  TicketEscalationTriggerType,
  TicketEscalationTargetType,
  TicketLinkEntityType,
  TicketLinkRelationship,
} from "../../../../server/contracts/ticketing/ticketing.ts";

export interface TicketActionState {
  readonly error: string | null;
}

const OK: TicketActionState = { error: null };
const NO_ACCESS: TicketActionState = { error: "You don't have access to this organization's ticketing workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/tickets`;
}

function detailPath(tenantSlug: string, ticketId: string): string {
  return `/${tenantSlug}/tickets/${ticketId}`;
}

function errorMessage(prefix: string, error: unknown): TicketActionState {
  if (error instanceof TicketMutationError) return { error: `${prefix}: ${error.message}` };
  throw error;
}

// --- Queue/category catalog (TKT:Edit) ---

export async function createTicketQueueAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim();
  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  if (!orgUnitId || !code || !name) return { error: "Department, code, and name are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTicketQueue(supabase, { tenantId: access.tenant.id, orgUnitId, code, name, description, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this queue", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function createTicketCategoryAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const defaultQueueId = String(formData.get("defaultQueueId") ?? "").trim() || null;
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTicketCategory(supabase, { tenantId: access.tenant.id, code, name, defaultQueueId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this category", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function addTicketQueueMemberAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const queueId = String(formData.get("queueId") ?? "").trim();
  const employeeId = String(formData.get("employeeId") ?? "").trim();
  if (!queueId || !employeeId) return { error: "Queue and employee are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addTicketQueueMember(supabase, { queueId, employeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not add this queue member", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function removeTicketQueueMemberAction(
  tenantSlug: string,
  memberId: string,
  expectedVersion: number,
  _prevState: TicketActionState,
  formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await removeTicketQueueMember(supabase, { memberId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not remove this queue member", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function setTicketCategoryCustomerVisibilityAction(
  tenantSlug: string,
  categoryId: string,
  customerVisible: boolean,
  _prevState: TicketActionState,
  _formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await setTicketCategoryCustomerVisibility(supabase, { categoryId, customerVisible, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not update customer visibility for this category", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

// --- Ticket creation (self-service) ---

export async function createTicketAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const categoryId = String(formData.get("categoryId") ?? "").trim();
  const queueId = String(formData.get("queueId") ?? "").trim() || null;
  const priority = String(formData.get("priority") ?? "normal") as TicketPriority;
  const subject = String(formData.get("subject") ?? "").trim();
  const body = String(formData.get("body") ?? "").trim();
  if (!categoryId || !subject || !body) return { error: "Category, subject, and description are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTicket(supabase, {
      tenantId: access.tenant.id,
      categoryId,
      queueId,
      priority,
      subject,
      body,
      idempotencyKey: `create-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not create this ticket", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

// --- Conversation ---

export async function replyToTicketAction(tenantSlug: string, ticketId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const body = String(formData.get("body") ?? "").trim();
  const visibility = (String(formData.get("visibility") ?? "public") as MessageVisibility) ?? "public";
  if (!body) return { error: "A non-empty message is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await replyToTicket(supabase, {
      ticketId,
      body,
      visibility,
      attachmentFileIds: null,
      idempotencyKey: `reply-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not post this message", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function redactTicketMessageAction(
  tenantSlug: string,
  ticketId: string,
  messageId: string,
  expectedVersion: number,
  _prevState: TicketActionState,
  formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to redact a message." };

  const supabase = await createSupabaseServerClient();
  try {
    await redactTicketMessage(supabase, { messageId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not redact this message", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- Watchers ---

export async function addTicketWatcherAction(tenantSlug: string, ticketId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  if (!employeeId) return { error: "An employee is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addTicketWatcher(supabase, { ticketId, employeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not add this watcher", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function removeTicketWatcherAction(
  tenantSlug: string,
  ticketId: string,
  watcherId: string,
  expectedVersion: number,
  _prevState: TicketActionState,
  _formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await removeTicketWatcher(supabase, { watcherId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not remove this watcher", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- Assignment / transfer / classification / lifecycle ---

export async function assignTicketAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const assigneeEmployeeId = String(formData.get("assigneeEmployeeId") ?? "").trim() || null;
  // HRT-290: reason/override are optional -- omitted entirely on the
  // existing catalog-style form, present when submitted from the
  // workload-cap-aware assignment drawer control.
  const reason = String(formData.get("reason") ?? "").trim() || null;
  const overrideWorkloadLimit = formData.get("overrideWorkloadLimit") === "on";

  const supabase = await createSupabaseServerClient();
  try {
    await assignTicket(supabase, { ticketId, expectedVersion, assigneeEmployeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, reason, overrideWorkloadLimit });
  } catch (error) {
    return errorMessage("Could not assign this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function transferTicketQueueAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newQueueId = String(formData.get("newQueueId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!newQueueId || !reason) return { error: "A destination queue and a reason are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await transferTicketQueue(supabase, { ticketId, expectedVersion, newQueueId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not transfer this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function updateTicketClassificationAction(
  tenantSlug: string,
  ticketId: string,
  expectedVersion: number,
  _prevState: TicketActionState,
  formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const categoryId = String(formData.get("categoryId") ?? "").trim();
  const priority = String(formData.get("priority") ?? "normal") as TicketPriority;
  if (!categoryId) return { error: "A category is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await updateTicketClassification(supabase, { ticketId, expectedVersion, categoryId, priority, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not reclassify this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function transitionTicketStatusAction(
  tenantSlug: string,
  ticketId: string,
  expectedVersion: number,
  toStatus: TicketStatus,
  _prevState: TicketActionState,
  formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await transitionTicketStatus(supabase, { ticketId, expectedVersion, toStatus, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not update this ticket's status", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- SLA clock (HRT-289, CG-S12-HRT-017) -- explicit, separate calls from
// the ticket lifecycle above (decision 1 of the SLA migration): starting a
// clock is a SECOND step the UI takes right after ticket creation succeeds,
// never a hidden side effect of any ticket write. Every write here is
// permission-gated at the RPC layer itself (app.is_ticket_staff / TKT:Close
// for a correction) -- this file only forwards.

export async function startTicketSlaClockAction(tenantSlug: string, ticketId: string, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await startTicketSlaClock(supabase, { ticketId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not start the SLA clock for this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function pauseTicketSlaClockAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const pauseReasonCode = String(formData.get("pauseReasonCode") ?? "") as SlaPauseReasonCode;
  const reason = String(formData.get("reason") ?? "").trim() || null;
  if (!pauseReasonCode) return { error: "A pause reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await pauseTicketSlaClock(supabase, { ticketId, expectedVersion, pauseReasonCode, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not pause the SLA clock", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function resumeTicketSlaClockAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await resumeTicketSlaClock(supabase, { ticketId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not resume the SLA clock", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- SLA calendar/policy administration (TKT:Edit, HRT-289). Mirrors the
// "always rendered, gated at the RPC" pattern createTicketQueueAction/
// createTicketCategoryAction already use above -- these forms render for
// any tenant member; app.check_ticket_authority('Edit', ...) is what
// actually enforces the bar, never this file. ---

function slaPath(tenantSlug: string): string {
  return `/${tenantSlug}/tickets/sla`;
}

export async function createSlaCalendarAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createSlaCalendar(supabase, { tenantId: access.tenant.id, code, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this SLA calendar", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

export async function createSlaCalendarVersionAction(tenantSlug: string, calendarId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const timezone = String(formData.get("timezone") ?? "").trim();
  const is24x7 = formData.get("is24x7") === "on";
  if (!timezone) return { error: "A timezone is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createSlaCalendarVersion(supabase, { calendarId, timezone, is24x7, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this calendar version", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

export async function addSlaCalendarBusinessHoursAction(tenantSlug: string, calendarVersionId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const dayOfWeek = Number(formData.get("dayOfWeek") ?? Number.NaN);
  const startTime = String(formData.get("startTime") ?? "").trim();
  const endTime = String(formData.get("endTime") ?? "").trim();
  if (!Number.isInteger(dayOfWeek) || !startTime || !endTime) return { error: "Day of week, start time, and end time are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addSlaCalendarBusinessHours(supabase, { calendarVersionId, dayOfWeek, startTime, endTime, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not add these business hours", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

export async function addSlaCalendarHolidayAction(tenantSlug: string, calendarVersionId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const holidayDate = String(formData.get("holidayDate") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  if (!holidayDate || !name) return { error: "A date and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await addSlaCalendarHoliday(supabase, { calendarVersionId, holidayDate, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not add this holiday", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

export async function publishSlaCalendarVersionAction(tenantSlug: string, versionId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishSlaCalendarVersion(supabase, { versionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not publish this calendar version", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

export async function createSlaPolicyAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createSlaPolicy(supabase, { tenantId: access.tenant.id, code, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this SLA policy", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

export async function createSlaPolicyVersionAction(tenantSlug: string, policyId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const channel = String(formData.get("channel") ?? "") as TicketChannel;
  const categoryId = String(formData.get("categoryId") ?? "").trim() || null;
  const priority = (String(formData.get("priority") ?? "").trim() || null) as TicketPriority | null;
  const calendarId = String(formData.get("calendarId") ?? "").trim();
  const responseTargetMinutes = Number(formData.get("responseTargetMinutes") ?? Number.NaN);
  const resolutionTargetMinutes = Number(formData.get("resolutionTargetMinutes") ?? Number.NaN);
  const precedenceRank = Number(formData.get("precedenceRank") ?? 0);
  if (!channel || !calendarId || !Number.isFinite(responseTargetMinutes) || !Number.isFinite(resolutionTargetMinutes)) {
    return { error: "Channel, calendar, and both response/resolution targets are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createSlaPolicyVersion(supabase, {
      policyId,
      channel,
      categoryId,
      priority,
      customerAccountId: null,
      queueId: null,
      supportQueueId: null,
      calendarId,
      responseTargetMinutes,
      resolutionTargetMinutes,
      precedenceRank,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not create this policy version", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

export async function publishSlaPolicyVersionAction(tenantSlug: string, versionId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishSlaPolicyVersion(supabase, { versionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not publish this policy version", error);
  }
  revalidatePath(slaPath(tenantSlug));
  return OK;
}

// --- Ticket Assignment (HRT-290, CG-S12-HRT-018). Claim/accept/decline/
// auto-route are bounded to internal/customer channels at the RPC layer
// (a helpdesk ticket never renders these controls -- see the detail panel's
// own channel check); this file only forwards, the RPC is what actually
// enforces the boundary. ---

export async function claimTicketAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await claimTicket(supabase, { ticketId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not claim this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function acceptTicketAssignmentAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await acceptTicketAssignment(supabase, { ticketId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not confirm this assignment", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function declineTicketAssignmentAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to decline a ticket assignment." };

  const supabase = await createSupabaseServerClient();
  try {
    await declineTicketAssignment(supabase, { ticketId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not decline this assignment", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function autoRouteTicketAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await autoRouteTicket(supabase, { ticketId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not auto-route this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- Ticket routing rule administration (TKT:Edit). Mirrors the SLA admin
// forms above exactly: always rendered for any tenant member, the RPC layer
// (app.check_ticket_authority('Edit', ...)) is what actually enforces the
// bar. ---

function routingPath(tenantSlug: string): string {
  return `/${tenantSlug}/tickets/routing`;
}

export async function createTicketRoutingRuleAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTicketRoutingRule(supabase, { tenantId: access.tenant.id, code, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this routing rule", error);
  }
  revalidatePath(routingPath(tenantSlug));
  return OK;
}

export async function createTicketRoutingRuleVersionAction(tenantSlug: string, ruleId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const channel = String(formData.get("channel") ?? "") as TicketChannel;
  const categoryId = String(formData.get("categoryId") ?? "").trim() || null;
  const priority = (String(formData.get("priority") ?? "").trim() || null) as TicketPriority | null;
  const targetQueueId = String(formData.get("targetQueueId") ?? "").trim();
  const assignmentMode = (String(formData.get("assignmentMode") ?? "manual") || "manual") as TicketRoutingAssignmentMode;
  const maxRaw = String(formData.get("maxActiveAssignmentsPerMember") ?? "").trim();
  const maxActiveAssignmentsPerMember = maxRaw ? Number(maxRaw) : null;
  const precedenceRank = Number(formData.get("precedenceRank") ?? 0);
  if (channel !== "internal" && channel !== "customer") return { error: "Channel must be internal or customer -- helpdesk has no eligibility model to route within." };
  if (!targetQueueId) return { error: "A target queue is required." };
  if (maxRaw && (!Number.isFinite(maxActiveAssignmentsPerMember) || (maxActiveAssignmentsPerMember ?? 0) <= 0)) return { error: "The workload cap must be a positive number, or left blank for no cap." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTicketRoutingRuleVersion(supabase, {
      ruleId,
      channel,
      categoryId,
      priority,
      targetQueueId,
      assignmentMode,
      maxActiveAssignmentsPerMember,
      precedenceRank,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not create this routing rule version", error);
  }
  revalidatePath(routingPath(tenantSlug));
  return OK;
}

export async function publishTicketRoutingRuleVersionAction(tenantSlug: string, versionId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishTicketRoutingRuleVersion(supabase, { versionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not publish this routing rule version", error);
  }
  revalidatePath(routingPath(tenantSlug));
  return OK;
}

// app.preview_ticket_routing (section 14, "routing preview") -- a real,
// TKT:Edit-gated admin tool: verify which published rule version (if any)
// would match a given channel/category/priority scope before it ever
// affects a real ticket. A distinct result shape from TicketActionState
// (carries the match itself, not just an error) since this reads rather
// than mutates.
export interface TicketRoutingPreviewActionState {
  readonly error: string | null;
  readonly result: TicketRoutingPreviewRow | null;
}

export async function previewTicketRoutingAction(tenantSlug: string, _prevState: TicketRoutingPreviewActionState, formData: FormData): Promise<TicketRoutingPreviewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, result: null };

  const channel = String(formData.get("channel") ?? "") as TicketChannel;
  const categoryId = String(formData.get("categoryId") ?? "").trim() || null;
  const priority = (String(formData.get("priority") ?? "").trim() || null) as TicketPriority | null;
  if (channel !== "internal" && channel !== "customer") return { error: "Channel must be internal or customer.", result: null };

  const supabase = await createSupabaseServerClient();
  try {
    const result = await previewTicketRouting(supabase, access.tenant.id, channel, categoryId, priority, access.authUserId);
    return { error: null, result };
  } catch (error) {
    if (error instanceof TicketMutationError || error instanceof TicketQueryError) return { error: `Could not preview routing: ${error.message}`, result: null };
    throw error;
  }
}

// --- Ticket Escalation (HRT-291, CG-S12-HRT-019). Policy/level administration
// (TKT:Edit) mirrors the SLA/routing admin forms above exactly; manual
// escalate/acknowledge/resolve (is_ticket_staff) and suppress/revoke
// (TKT:Assign) mirror the assignment drawer's own "always rendered, RPC-
// enforced" pattern -- every write here is permission-gated at the RPC
// layer, this file only forwards. ---

function escalationPath(tenantSlug: string): string {
  return `/${tenantSlug}/tickets/escalation`;
}

export async function createTicketEscalationPolicyAction(tenantSlug: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTicketEscalationPolicy(supabase, { tenantId: access.tenant.id, code, name, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not create this escalation policy", error);
  }
  revalidatePath(escalationPath(tenantSlug));
  return OK;
}

export async function createTicketEscalationPolicyVersionAction(tenantSlug: string, policyId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const channel = String(formData.get("channel") ?? "") as TicketChannel;
  const categoryId = String(formData.get("categoryId") ?? "").trim() || null;
  const priority = (String(formData.get("priority") ?? "").trim() || null) as TicketPriority | null;
  const queueId = String(formData.get("queueId") ?? "").trim() || null;
  const precedenceRank = Number(formData.get("precedenceRank") ?? 0);
  if (channel !== "internal" && channel !== "customer") return { error: "Channel must be internal or customer -- helpdesk has no escalation model." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTicketEscalationPolicyVersion(supabase, {
      policyId, channel, categoryId, priority, queueId, precedenceRank,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not create this escalation policy version", error);
  }
  revalidatePath(escalationPath(tenantSlug));
  return OK;
}

export async function addTicketEscalationLevelAction(tenantSlug: string, policyVersionId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const levelNumber = Number(formData.get("levelNumber") ?? Number.NaN);
  const triggerType = String(formData.get("triggerType") ?? "") as TicketEscalationTriggerType;
  const thresholdRaw = String(formData.get("thresholdMinutes") ?? "").trim();
  const thresholdMinutes = thresholdRaw ? Number(thresholdRaw) : null;
  const minPriority = (String(formData.get("minPriority") ?? "").trim() || null) as TicketPriority | null;
  const targetType = String(formData.get("targetType") ?? "") as TicketEscalationTargetType;
  const targetQueueId = String(formData.get("targetQueueId") ?? "").trim() || null;
  const targetEmployeeId = String(formData.get("targetEmployeeId") ?? "").trim() || null;
  const actionNotify = formData.get("actionNotify") === "on";
  const actionReassign = formData.get("actionReassign") === "on";
  const cooldownMinutes = Number(formData.get("cooldownMinutes") ?? 60);
  if (!Number.isInteger(levelNumber) || levelNumber <= 0) return { error: "A positive level number is required." };
  if (!triggerType) return { error: "A trigger type is required." };
  if (targetType !== "queue" && targetType !== "employee") return { error: "Target type must be queue or employee." };
  if (targetType === "queue" && !targetQueueId) return { error: "A target queue is required for a queue-targeted level." };
  if (targetType === "employee" && !targetEmployeeId) return { error: "A target employee id is required for an employee-targeted level." };

  const supabase = await createSupabaseServerClient();
  try {
    await addTicketEscalationLevel(supabase, {
      policyVersionId, levelNumber, triggerType, thresholdMinutes, minPriority,
      targetType, targetQueueId: targetType === "queue" ? targetQueueId : null, targetEmployeeId: targetType === "employee" ? targetEmployeeId : null,
      actionNotify, actionReassign, cooldownMinutes,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not save this escalation level", error);
  }
  revalidatePath(escalationPath(tenantSlug));
  return OK;
}

export async function publishTicketEscalationPolicyVersionAction(tenantSlug: string, versionId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishTicketEscalationPolicyVersion(supabase, { versionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not publish this escalation policy version", error);
  }
  revalidatePath(escalationPath(tenantSlug));
  return OK;
}

export interface TicketEscalationPreviewActionState {
  readonly error: string | null;
  readonly result: TicketEscalationPreviewRow | null;
}

export async function previewTicketEscalationAction(tenantSlug: string, _prevState: TicketEscalationPreviewActionState, formData: FormData): Promise<TicketEscalationPreviewActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, result: null };

  const channel = String(formData.get("channel") ?? "") as TicketChannel;
  const categoryId = String(formData.get("categoryId") ?? "").trim() || null;
  const priority = (String(formData.get("priority") ?? "").trim() || null) as TicketPriority | null;
  const queueId = String(formData.get("queueId") ?? "").trim() || null;
  if (channel !== "internal" && channel !== "customer") return { error: "Channel must be internal or customer.", result: null };

  const supabase = await createSupabaseServerClient();
  try {
    const result = await previewTicketEscalation(supabase, access.tenant.id, channel, categoryId, priority, queueId, access.authUserId);
    return { error: null, result };
  } catch (error) {
    if (error instanceof TicketMutationError || error instanceof TicketQueryError) return { error: `Could not preview escalation: ${error.message}`, result: null };
    throw error;
  }
}

export async function escalateTicketAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const targetType = String(formData.get("targetType") ?? "") as TicketEscalationTargetType;
  const targetQueueId = String(formData.get("targetQueueId") ?? "").trim() || null;
  const targetEmployeeId = String(formData.get("targetEmployeeId") ?? "").trim() || null;
  const reassign = formData.get("reassign") === "on";
  const reason = String(formData.get("reason") ?? "").trim();
  if (targetType !== "queue" && targetType !== "employee") return { error: "Target type must be queue or employee." };
  if (!reason) return { error: "A reason is required to manually escalate a ticket." };

  const supabase = await createSupabaseServerClient();
  try {
    await escalateTicket(supabase, {
      ticketId, expectedVersion, targetType,
      targetQueueId: targetType === "queue" ? targetQueueId : null,
      targetEmployeeId: targetType === "employee" ? targetEmployeeId : null,
      reassign, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not escalate this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function acknowledgeTicketEscalationAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, _formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await acknowledgeTicketEscalation(supabase, { ticketId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not acknowledge this escalation", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function resolveTicketEscalationAction(tenantSlug: string, ticketId: string, expectedVersion: number, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await resolveTicketEscalation(supabase, { ticketId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not resolve this escalation", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function suppressTicketEscalationAction(tenantSlug: string, ticketId: string, _prevState: TicketActionState, formData: FormData): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  const expiresAtInput = String(formData.get("expiresAt") ?? "").trim();
  if (!reason) return { error: "A reason is required to suppress escalation." };
  if (!expiresAtInput) return { error: "An expiry date/time is required." };
  const expiresAt = new Date(expiresAtInput);
  if (Number.isNaN(expiresAt.getTime())) return { error: "The expiry date/time is not valid." };

  const supabase = await createSupabaseServerClient();
  try {
    await suppressTicketEscalation(supabase, { ticketId, reason, expiresAt: expiresAt.toISOString(), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not suppress escalation for this ticket", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function revokeTicketEscalationSuppressionAction(
  tenantSlug: string,
  ticketId: string,
  suppressionId: string,
  expectedVersion: number,
  _prevState: TicketActionState,
  formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await revokeTicketEscalationSuppression(supabase, { ticketId, suppressionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not revoke this suppression", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// --- Typed Ticket-Linked Records (HRT-292, CG-S12-HRT-020). Search/link/
// unlink are all permission-gated at the RPC layer itself (staff OR
// requester-side party may link/unlink; every candidate is independently
// re-authorized against its OWN domain, never trusted from ticket access
// alone) -- this file only forwards. ---

export interface TicketLinkSearchActionState {
  readonly error: string | null;
  readonly entityType: TicketLinkEntityType | null;
  readonly relationship: TicketLinkRelationship;
  readonly results: readonly TicketLinkCandidateRow[];
}

const LINK_SEARCH_INITIAL: TicketLinkSearchActionState = { error: null, entityType: null, relationship: "related", results: [] };

export async function searchTicketLinkCandidatesAction(
  tenantSlug: string,
  ticketId: string,
  _prevState: TicketLinkSearchActionState,
  formData: FormData,
): Promise<TicketLinkSearchActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { ...LINK_SEARCH_INITIAL, error: NO_ACCESS.error };

  const entityType = String(formData.get("entityType") ?? "") as TicketLinkEntityType;
  const relationship = (String(formData.get("relationship") ?? "related") || "related") as TicketLinkRelationship;
  const searchText = String(formData.get("searchText") ?? "").trim() || null;
  if (!(TICKET_LINK_ENTITY_TYPES as readonly string[]).includes(entityType)) {
    return { error: "Select a record type to search.", entityType: null, relationship, results: [] };
  }
  if (!(TICKET_LINK_RELATIONSHIPS as readonly string[]).includes(relationship)) {
    return { error: "Select a valid relationship.", entityType, relationship: "related", results: [] };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const results = await searchTicketLinkCandidates(supabase, ticketId, entityType, searchText, access.authUserId, 20);
    return { error: null, entityType, relationship, results };
  } catch (error) {
    if (error instanceof TicketQueryError) return { error: `Could not search: ${error.message}`, entityType, relationship, results: [] };
    throw error;
  }
}

export async function linkTicketRecordAction(
  tenantSlug: string,
  ticketId: string,
  entityType: TicketLinkEntityType,
  entityId: string,
  relationship: TicketLinkRelationship,
  _prevState: TicketActionState,
  _formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await linkTicketRecord(supabase, { ticketId, entityType, entityId, relationship, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TicketMutationError) {
      // Durable denial audit (decision 9 of the migration): a genuinely
      // separate call, fire-and-forget -- never blocks the user-facing
      // error on it, and never lets an audit-write failure mask the real
      // denial the user already sees.
      if (error.code === "record_not_eligible" || error.code === "entity_type_not_permitted") {
        void recordTicketLinkAccessDenial(supabase, {
          tenantId: access.tenant.id, ticketId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
          entityType, entityId, reason: error.code,
        }).catch(() => {});
      }
      return { error: `Could not link this record: ${error.message}` };
    }
    throw error;
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function unlinkTicketRecordAction(
  tenantSlug: string,
  ticketId: string,
  linkId: string,
  expectedVersion: number,
  _prevState: TicketActionState,
  formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await unlinkTicketRecord(supabase, { linkId, expectedVersion, reason: reason ?? "", actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    return errorMessage("Could not unlink this record", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

// Fired only when a viewer actually expands a link's full summary -- never
// on every list render (audit impact "safe-summary/deep-link access...
// audited", never a per-page-view spam source). A logging failure never
// blocks the viewer from seeing data they are already independently
// authorized to see -- the button's own client-side expand/collapse state
// is not gated on this call succeeding.
export async function recordTicketLinkSummaryAccessAction(
  tenantSlug: string,
  linkId: string,
  accessType: "summary_viewed" | "deep_link_opened",
  _prevState: TicketActionState,
  _formData: FormData,
): Promise<TicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const supabase = await createSupabaseServerClient();
  try {
    await recordTicketLinkSummaryAccess(supabase, { linkId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, accessType });
  } catch (error) {
    return errorMessage("Could not record this view", error);
  }
  return OK;
}
