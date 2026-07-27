/**
 * Milestone Management mutation primitives (OPS-173, CG-S8-OPS-007). Thin, typed
 * wrappers around app.create_milestone_template_draft / app.set_milestone_template_sequence
 * / app.publish_milestone_template_version / app.ingest_milestone_event
 * (supabase/migrations/20260727140000_create_operations_milestone_management.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateMilestoneTemplateDraftInputSchema,
  SetMilestoneTemplateSequenceInputSchema,
  PublishMilestoneTemplateVersionInputSchema,
  IngestMilestoneEventInputSchema,
  parseMilestoneTemplateVersion,
  parseMilestoneEvent,
  type CreateMilestoneTemplateDraftInput,
  type SetMilestoneTemplateSequenceInput,
  type PublishMilestoneTemplateVersionInput,
  type IngestMilestoneEventInput,
  type MilestoneTemplateVersion,
  type MilestoneEvent,
} from "../contracts/milestone-management/milestone-management.ts";

export type MilestoneManagementMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const MILESTONE_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES = [
  "invalid_mode",
  "milestone_template_not_found",
  "invalid_transition",
  "milestone_invalid_sequence",
  "milestone_unknown_code",
  "milestone_duplicate_code",
  "stale_version",
  "insufficient_authority",
  "milestone_invalid_source",
  "shipment_order_not_found",
  "reason_required",
  "milestone_event_not_found",
] as const;
type KnownMilestoneManagementMutationErrorCode = (typeof MILESTONE_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type MilestoneManagementMutationErrorCode = KnownMilestoneManagementMutationErrorCode | "mutation_failed" | "invalid_response";

export class MilestoneManagementMutationError extends Error {
  readonly code: MilestoneManagementMutationErrorCode;

  constructor(code: MilestoneManagementMutationErrorCode, message: string) {
    super(message);
    this.name = "MilestoneManagementMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MilestoneManagementMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MILESTONE_MANAGEMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownMilestoneManagementMutationErrorCode)
    : "mutation_failed";
}

function parseRpcTemplateVersion(data: unknown, rpcName: string): MilestoneTemplateVersion {
  if (!data || typeof data !== "object") {
    throw new MilestoneManagementMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseMilestoneTemplateVersion(data as Record<string, unknown>);
}

/** Idempotent: a repeated call while a draft already exists for this (tenant, mode) returns that same draft. */
export async function createMilestoneTemplateDraft(
  client: MilestoneManagementMutationRpcClient,
  input: CreateMilestoneTemplateDraftInput,
): Promise<MilestoneTemplateVersion> {
  const parsedInput = CreateMilestoneTemplateDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_milestone_template_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_mode: parsedInput.mode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MilestoneManagementMutationError(classifyError(error.message), error.message);
  }
  return parseRpcTemplateVersion(data, "create_milestone_template_draft");
}

/** Only ever mutates a draft -- each sequence element's own code is validated against app.milestone_codes immediately. */
export async function setMilestoneTemplateSequence(
  client: MilestoneManagementMutationRpcClient,
  input: SetMilestoneTemplateSequenceInput,
): Promise<MilestoneTemplateVersion> {
  const parsedInput = SetMilestoneTemplateSequenceInputSchema.parse(input);
  const { data, error } = await client.rpc("set_milestone_template_sequence", {
    p_version_id: parsedInput.versionId,
    p_sequence: parsedInput.sequence,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MilestoneManagementMutationError(classifyError(error.message), error.message);
  }
  return parseRpcTemplateVersion(data, "set_milestone_template_sequence");
}

/** Publish-time structural gate (non-empty, every code real, no duplicate) plus optimistic concurrency; supersedes the prior published version for the same (tenant, mode). */
export async function publishMilestoneTemplateVersion(
  client: MilestoneManagementMutationRpcClient,
  input: PublishMilestoneTemplateVersionInput,
): Promise<MilestoneTemplateVersion> {
  const parsedInput = PublishMilestoneTemplateVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_milestone_template_version", {
    p_version_id: parsedInput.versionId,
    p_expected_version: parsedInput.expectedVersion,
    p_supersedes_version_id: parsedInput.supersedesVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MilestoneManagementMutationError(classifyError(error.message), error.message);
  }
  return parseRpcTemplateVersion(data, "publish_milestone_template_version");
}

/** The one path that ingests a milestone event -- idempotent on (tenant, shipmentOrderId, idempotencyKey). A correction (correctsEventId set) requires a non-empty reason. */
export async function ingestMilestoneEvent(client: MilestoneManagementMutationRpcClient, input: IngestMilestoneEventInput): Promise<MilestoneEvent> {
  const parsedInput = IngestMilestoneEventInputSchema.parse(input);
  const { data, error } = await client.rpc("ingest_milestone_event", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_milestone_code: parsedInput.milestoneCode,
    p_event_time: parsedInput.eventTime,
    p_received_time: parsedInput.receivedTime,
    p_location: parsedInput.location,
    p_source: parsedInput.source,
    p_reason: parsedInput.reason,
    p_corrects_event_id: parsedInput.correctsEventId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MilestoneManagementMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MilestoneManagementMutationError("invalid_response", "ingest_milestone_event returned no row");
  }
  return parseMilestoneEvent(data as Record<string, unknown>);
}
