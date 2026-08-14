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
  TicketMutationError,
} from "../../../../server/mutations/ticketing.ts";
import type { MessageVisibility, TicketPriority, TicketStatus } from "../../../../server/contracts/ticketing/ticketing.ts";

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

  const supabase = await createSupabaseServerClient();
  try {
    await assignTicket(supabase, { ticketId, expectedVersion, assigneeEmployeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
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
