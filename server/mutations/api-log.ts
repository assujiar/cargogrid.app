/**
 * API request observability mutation (PLT-130, CG-S6-PLT-027). Thin, typed wrapper
 * around app.record_api_request (supabase/migrations/20260719160000_create_api_foundation.sql)
 * -- service_role-only, the real adapter interface a future request-handling
 * middleware would call exactly once per request. This repository never calls it
 * against a fabricated live request itself (disclosed NOT_RUN -- no HTTP route or
 * GraphQL server exists anywhere in this repository yet).
 */

import { RecordApiRequestInputSchema, parseApiLog, type RecordApiRequestInput, type ApiLog } from "../contracts/api/api.ts";

export interface ApiLogMutationRpcClient {
  rpc(fn: "record_api_request", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const API_LOG_KNOWN_MUTATION_ERROR_CODES = ["api_log_invalid_actor_type", "api_log_invalid_interface", "api_log_invalid_result"] as const;
type KnownApiLogMutationErrorCode = (typeof API_LOG_KNOWN_MUTATION_ERROR_CODES)[number];
export type ApiLogMutationErrorCode = KnownApiLogMutationErrorCode | "mutation_failed" | "invalid_response";

export class ApiLogMutationError extends Error {
  readonly code: ApiLogMutationErrorCode;

  constructor(code: ApiLogMutationErrorCode, message: string) {
    super(message);
    this.name = "ApiLogMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ApiLogMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (API_LOG_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownApiLogMutationErrorCode) : "mutation_failed";
}

export async function recordApiRequest(client: ApiLogMutationRpcClient, input: RecordApiRequestInput): Promise<ApiLog> {
  const parsedInput = RecordApiRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("record_api_request", {
    p_correlation_id: parsedInput.correlationId,
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_type: parsedInput.actorType,
    p_api_key_id: parsedInput.apiKeyId,
    p_interface: parsedInput.interface,
    p_operation: parsedInput.operation,
    p_http_method: parsedInput.httpMethod,
    p_path: parsedInput.path,
    p_graphql_operation_name: parsedInput.graphqlOperationName,
    p_status_code: parsedInput.statusCode,
    p_result: parsedInput.result,
    p_error_code: parsedInput.errorCode,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_duration_ms: parsedInput.durationMs,
  });
  if (error) {
    throw new ApiLogMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ApiLogMutationError("invalid_response", "record_api_request returned no row");
  }
  return parseApiLog(data as Record<string, unknown>);
}
