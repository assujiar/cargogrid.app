"use server";

/**
 * Customer ticket Server Actions (HRT-287, CG-S12-HRT-015). Mirrors
 * app/(tenant)/[tenantSlug]/tickets/actions.ts's own shape, but calls only
 * the customer-facing mutation wrappers -- createCustomerTicket,
 * replyToCustomerTicket, and the SAME generic transitionTicketStatus the
 * internal surface uses (close/reopen-as-configured reaches the customer
 * channel through the identical RPC, decision 9 of the HRT-287 migration).
 * Every write is permission/scope-gated at the RPC layer itself
 * (app.resolve_customer_owner_account_scope) -- this file never re-derives
 * or trusts a client-supplied account/site id, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerTicketAccessForRequest } from "../../../../lib/portal/resolve-customer-ticket-access.server.ts";
import { createCustomerTicket, replyToCustomerTicket, transitionTicketStatus, TicketMutationError } from "../../../../server/mutations/ticketing.ts";
import type { TicketPriority, TicketStatus } from "../../../../server/contracts/ticketing/ticketing.ts";

export interface CustomerTicketActionState {
  readonly error: string | null;
}

const OK: CustomerTicketActionState = { error: null };
const NO_ACCESS: CustomerTicketActionState = { error: "You don't have access to this organization's customer support workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/customer-tickets`;
}

function detailPath(tenantSlug: string, ticketId: string): string {
  return `/${tenantSlug}/customer-tickets/${ticketId}`;
}

function errorMessage(prefix: string, error: unknown): CustomerTicketActionState {
  if (error instanceof TicketMutationError) return { error: `${prefix}: ${error.message}` };
  throw error;
}

export async function createCustomerTicketAction(tenantSlug: string, _prevState: CustomerTicketActionState, formData: FormData): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const accountId = String(formData.get("accountId") ?? "").trim();
  const categoryId = String(formData.get("categoryId") ?? "").trim();
  const priority = String(formData.get("priority") ?? "normal") as TicketPriority;
  const subject = String(formData.get("subject") ?? "").trim();
  const body = String(formData.get("body") ?? "").trim();
  if (!accountId || !categoryId || !subject || !body) return { error: "Account, category, subject, and description are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createCustomerTicket(supabase, {
      tenantId: access.tenant.id,
      accountId,
      categoryId,
      priority,
      subject,
      body,
      idempotencyKey: `create-customer-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not create this ticket", error);
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

export async function replyToCustomerTicketAction(tenantSlug: string, ticketId: string, _prevState: CustomerTicketActionState, formData: FormData): Promise<CustomerTicketActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const body = String(formData.get("body") ?? "").trim();
  if (!body) return { error: "A non-empty message is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await replyToCustomerTicket(supabase, {
      ticketId,
      body,
      attachmentFileIds: null,
      idempotencyKey: `reply-customer-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not post this message", error);
  }
  revalidatePath(detailPath(tenantSlug, ticketId));
  return OK;
}

export async function transitionCustomerTicketStatusAction(
  tenantSlug: string,
  ticketId: string,
  expectedVersion: number,
  toStatus: TicketStatus,
  _prevState: CustomerTicketActionState,
  formData: FormData,
): Promise<CustomerTicketActionState> {
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
