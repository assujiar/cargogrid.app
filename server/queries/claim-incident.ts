/**
 * Advanced Claim and Incident Operations read queries (ATW-025, CG-S10-ATW-025).
 * Thin, typed wrappers around app.get_claim_case/app.list_claim_cases/app.
 * list_claim_items/app.list_claim_evidence/app.get_claim_investigation_history/app.
 * get_claim_responsibility_review/app.list_claim_recovery_records
 * (supabase/migrations/20260730340000_create_advanced_tms_claim_incident_operations.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ListClaimCasesInputSchema,
  parseClaimCaseExtension,
  parseClaimCaseListRow,
  parseClaimItem,
  parseClaimEvidenceLink,
  parseClaimInvestigationFinding,
  parseClaimResponsibilityReview,
  parseClaimRecoveryRecord,
  parseClaimSettlementReadinessEvaluation,
  parseClaimSettlementReadinessHandoff,
  type ListClaimCasesInput,
  type ClaimCaseExtension,
  type ClaimCaseListRow,
  type ClaimItem,
  type ClaimEvidenceLink,
  type ClaimInvestigationFinding,
  type ClaimResponsibilityReview,
  type ClaimRecoveryRecord,
  type ClaimSettlementReadinessEvaluation,
  type ClaimSettlementReadinessHandoff,
} from "../contracts/claim-incident/claim-incident.ts";

export type ClaimIncidentQueryClient = Pick<SupabaseClient, "rpc">;

export class ClaimIncidentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ClaimIncidentQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC-gated (OPS:View) + record-scoped. */
export async function getClaimCase(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string): Promise<ClaimCaseExtension> {
  const { data, error } = await client.rpc("get_claim_case", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentQueryError("get_claim_case returned no row");
  }
  return parseClaimCaseExtension(row);
}

/** Bounded (default 50, hard-capped 200 server-side), cursor-paginated on (updatedAt, id), record-scoped. */
export async function listClaimCases(client: ClaimIncidentQueryClient, input: ListClaimCasesInput): Promise<ClaimCaseListRow[]> {
  const parsedInput = ListClaimCasesInputSchema.parse(input);
  const { data, error } = await client.rpc("list_claim_cases", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_claim_stage_filter: parsedInput.claimStageFilter ?? null,
    p_exception_type_filter: parsedInput.exceptionTypeFilter ?? null,
    p_exception_severity_filter: parsedInput.exceptionSeverityFilter ?? null,
    p_exception_status_filter: parsedInput.exceptionStatusFilter ?? null,
    p_shipment_order_id_filter: parsedInput.shipmentOrderIdFilter ?? null,
    p_cursor_updated_at: parsedInput.cursorUpdatedAt ?? null,
    p_cursor_id: parsedInput.cursorId ?? null,
    p_limit: parsedInput.limit ?? 50,
  });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseClaimCaseListRow);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped. Money fields masked without OPS:View cost. */
export async function listClaimItems(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string, limit?: number): Promise<ClaimItem[]> {
  const { data, error } = await client.rpc("list_claim_items", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit ?? 50 });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseClaimItem);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped. */
export async function listClaimEvidence(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string, limit?: number): Promise<ClaimEvidenceLink[]> {
  const { data, error } = await client.rpc("list_claim_evidence", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit ?? 50 });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseClaimEvidenceLink);
}

/** Full, oldest-first investigation history, record-scoped. */
export async function getClaimInvestigationHistory(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string): Promise<ClaimInvestigationFinding[]> {
  const { data, error } = await client.rpc("get_claim_investigation_history", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseClaimInvestigationFinding);
}

/** The CURRENT responsibility review only, record-scoped. Money fields masked without OPS:View cost. */
export async function getClaimResponsibilityReview(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string): Promise<ClaimResponsibilityReview> {
  const { data, error } = await client.rpc("get_claim_responsibility_review", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentQueryError("get_claim_responsibility_review returned no row");
  }
  return parseClaimResponsibilityReview(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped. Money fields masked without OPS:View cost. */
export async function listClaimRecoveryRecords(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string, limit?: number): Promise<ClaimRecoveryRecord[]> {
  const { data, error } = await client.rpc("list_claim_recovery_records", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit ?? 50 });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseClaimRecoveryRecord);
}

/** The CURRENT settlement-readiness evaluation only, record-scoped. evidence.finalReserveAmount masked without OPS:View cost. */
export async function getClaimSettlementReadiness(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string): Promise<ClaimSettlementReadinessEvaluation> {
  const { data, error } = await client.rpc("get_claim_settlement_readiness", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ClaimIncidentQueryError("get_claim_settlement_readiness returned no row");
  }
  return parseClaimSettlementReadinessEvaluation(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped, ordered by handoffSeq desc (the authoritative most-recent-handoff ordering). Carries no dollar amount of its own -- no masking. */
export async function listClaimSettlementReadinessHandoffs(client: ClaimIncidentQueryClient, caseId: string, actorAuthUserId: string, limit?: number): Promise<ClaimSettlementReadinessHandoff[]> {
  const { data, error } = await client.rpc("list_claim_settlement_readiness_handoffs", { p_case_id: caseId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit ?? 50 });
  if (error) {
    throw new ClaimIncidentQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseClaimSettlementReadinessHandoff);
}
