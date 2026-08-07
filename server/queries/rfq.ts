/**
 * RFQ read queries (PRC-257, CG-S11-PRC-008). Thin, typed wrappers around the
 * dedicated read RPCs (supabase/migrations/20260730640000_create_procurement_
 * rfq.sql) -- mirrors server/queries/sourcing.ts exactly: every RPC already
 * carries its own explicit evaluate_permission check and (for the cost-
 * sensitive response shape) actor-parameterized masking, so this file calls
 * `.rpc(...)`, never `.from(...)`, on a base table or a view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseRfq,
  parseRfqRequirementLine,
  parseRfqInvitation,
  parseRfqClarification,
  parseRfqResponse,
  parseRfqResponseAttachment,
  parseRfqEvent,
  type Rfq,
  type RfqRequirementLine,
  type RfqInvitation,
  type RfqClarification,
  type RfqResponse,
  type RfqResponseAttachment,
  type RfqEvent,
} from "../contracts/rfq/rfq.ts";

export type RfqQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class RfqQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RfqQueryError";
  }
}

// app.list_rfqs itself clamps server-side to <=200 rows regardless of what is
// requested (PRC-256's own disclosed .limit(200) precedent) -- this
// client-side default only picks a reasonable per-request page size.
const RFQ_LIST_DEFAULT_LIMIT = 50;

/** A single RFQ. Throws on a real error; the RPC itself raises rfq_not_found/insufficient_privilege as thrown errors, never a null return. */
export async function getRfq(client: RfqQueryRpcClient, rfqId: string, actorAuthUserId: string): Promise<Rfq> {
  const { data, error } = await client.rpc("get_rfq", { p_rfq_id: rfqId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new RfqQueryError("get_rfq returned no row");
  }
  return parseRfq(data as Record<string, unknown>);
}

/** Tenant-scoped RFQ queue, optionally filtered by status. With no filter, superseded (historical) versions are excluded by default. Server-side clamped to <=200 rows. */
export async function listRfqs(
  client: RfqQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  status: string | null = null,
  limit: number = RFQ_LIST_DEFAULT_LIMIT,
): Promise<Rfq[]> {
  const { data, error } = await client.rpc("list_rfqs", { p_tenant_id: tenantId, p_status: status, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRfq(row));
}

/** Itemized requirement lines for one RFQ version. */
export async function listRfqRequirementLines(client: RfqQueryRpcClient, rfqId: string, actorAuthUserId: string): Promise<RfqRequirementLine[]> {
  const { data, error } = await client.rpc("list_rfq_requirement_lines", { p_rfq_id: rfqId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRfqRequirementLine(row));
}

/** Every invited vendor for one RFQ. */
export async function listRfqInvitations(client: RfqQueryRpcClient, rfqId: string, actorAuthUserId: string): Promise<RfqInvitation[]> {
  const { data, error } = await client.rpc("list_rfq_invitations", { p_rfq_id: rfqId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRfqInvitation(row));
}

/** Every clarification Q&A for one RFQ (broadcast + vendor-scoped). */
export async function listRfqClarifications(client: RfqQueryRpcClient, rfqId: string, actorAuthUserId: string): Promise<RfqClarification[]> {
  const { data, error } = await client.rpc("list_rfq_clarifications", { p_rfq_id: rfqId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRfqClarification(row));
}

/** Comparison read -- every response version for one RFQ, currency/totalAmount/validityUntil/commercialTerms masked behind PRC:View cost. */
export async function listRfqResponses(client: RfqQueryRpcClient, rfqId: string, actorAuthUserId: string): Promise<RfqResponse[]> {
  const { data, error } = await client.rpc("list_rfq_responses", { p_rfq_id: rfqId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRfqResponse(row));
}

/** Every private, scanned evidence file attached to one response version. */
export async function listRfqResponseAttachments(client: RfqQueryRpcClient, rfqResponseId: string, actorAuthUserId: string): Promise<RfqResponseAttachment[]> {
  const { data, error } = await client.rpc("list_rfq_response_attachments", { p_rfq_response_id: rfqResponseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRfqResponseAttachment(row));
}

/** The full lifecycle timeline (RFQ-root transitions only) for one RFQ, in occurrence order. */
export async function getRfqHistory(client: RfqQueryRpcClient, rfqId: string, actorAuthUserId: string): Promise<RfqEvent[]> {
  const { data, error } = await client.rpc("get_rfq_history", { p_rfq_id: rfqId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new RfqQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRfqEvent(row));
}
