/**
 * Master-data registry mutation primitives (PLT-120, CG-S6-PLT-017). Thin, typed
 * wrappers around app.register_master_type / app.create_master_record /
 * app.update_master_record / app.deactivate_master_record / app.merge_master_records
 * (supabase/migrations/20260717120000_create_master_data.sql). All service_role-only
 * (see the migration's own grant comment).
 */

import {
  RegisterMasterTypeInputSchema,
  CreateMasterRecordInputSchema,
  UpdateMasterRecordInputSchema,
  DeactivateMasterRecordInputSchema,
  MergeMasterRecordsInputSchema,
  parseMasterType,
  parseMasterRecord,
  type RegisterMasterTypeInput,
  type CreateMasterRecordInput,
  type UpdateMasterRecordInput,
  type DeactivateMasterRecordInput,
  type MergeMasterRecordsInput,
  type MasterType,
  type MasterRecord,
} from "../contracts/master-data/master-data.ts";

export interface MasterDataMutationRpcClient {
  rpc(
    fn:
      | "register_master_type"
      | "create_master_record"
      | "update_master_record"
      | "deactivate_master_record"
      | "merge_master_records",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const MASTER_DATA_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "master_record_already_exists",
  "master_record_not_found",
  "master_record_not_active",
  "stale_record_version",
  "invalid_merge",
  "unknown_master_type",
  "scope_mismatch",
] as const;
type KnownMasterDataMutationErrorCode = (typeof MASTER_DATA_KNOWN_MUTATION_ERROR_CODES)[number];
export type MasterDataMutationErrorCode = KnownMasterDataMutationErrorCode | "mutation_failed" | "invalid_response";

export class MasterDataMutationError extends Error {
  readonly code: MasterDataMutationErrorCode;

  constructor(code: MasterDataMutationErrorCode, message: string) {
    super(message);
    this.name = "MasterDataMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MasterDataMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MASTER_DATA_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownMasterDataMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseRecord(
  client: MasterDataMutationRpcClient,
  fn: "create_master_record" | "update_master_record" | "deactivate_master_record" | "merge_master_records",
  args: Record<string, unknown>,
): Promise<MasterRecord> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new MasterDataMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MasterDataMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseMasterRecord(data as Record<string, unknown>);
}

/** Idempotent -- a repeated call with an existing code returns that row, Supreme-Admin-only. */
export async function registerMasterType(client: MasterDataMutationRpcClient, input: RegisterMasterTypeInput): Promise<MasterType> {
  const parsedInput = RegisterMasterTypeInputSchema.parse(input);
  const { data, error } = await client.rpc("register_master_type", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_scope: parsedInput.scope,
    p_owner_module_code: parsedInput.ownerModuleCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new MasterDataMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MasterDataMutationError("invalid_response", "register_master_type returned no row");
  }
  return parseMasterType(data as Record<string, unknown>);
}

/** Idempotent for a repeated (masterTypeCode, tenantId, code). Authority: Supreme Admin for a global-scoped type (tenantId=null), Tenant Admin of tenantId or Supreme Admin otherwise. */
export async function createMasterRecord(client: MasterDataMutationRpcClient, input: CreateMasterRecordInput): Promise<MasterRecord> {
  const parsedInput = CreateMasterRecordInputSchema.parse(input);
  return callAndParseRecord(client, "create_master_record", {
    p_master_type_code: parsedInput.masterTypeCode,
    p_tenant_id: parsedInput.tenantId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_aliases: parsedInput.aliases,
    p_attributes: parsedInput.attributes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Optimistic-concurrency update -- rejects a stale expectedVersion rather than silently overwriting. */
export async function updateMasterRecord(client: MasterDataMutationRpcClient, input: UpdateMasterRecordInput): Promise<MasterRecord> {
  const parsedInput = UpdateMasterRecordInputSchema.parse(input);
  return callAndParseRecord(client, "update_master_record", {
    p_record_id: parsedInput.recordId,
    p_expected_version: parsedInput.expectedVersion,
    p_name: parsedInput.name,
    p_aliases: parsedInput.aliases,
    p_attributes: parsedInput.attributes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** active -> deactivated. */
export async function deactivateMasterRecord(client: MasterDataMutationRpcClient, input: DeactivateMasterRecordInput): Promise<MasterRecord> {
  const parsedInput = DeactivateMasterRecordInputSchema.parse(input);
  return callAndParseRecord(client, "deactivate_master_record", {
    p_record_id: parsedInput.recordId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Marks the source record merged (never deleted) and folds its aliases/code into the target, returning the updated target. */
export async function mergeMasterRecords(client: MasterDataMutationRpcClient, input: MergeMasterRecordsInput): Promise<MasterRecord> {
  const parsedInput = MergeMasterRecordsInputSchema.parse(input);
  return callAndParseRecord(client, "merge_master_records", {
    p_source_id: parsedInput.sourceId,
    p_target_id: parsedInput.targetId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_reason: parsedInput.reason,
    p_actor_label: parsedInput.actorLabel,
  });
}
