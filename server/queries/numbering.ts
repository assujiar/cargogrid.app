/**
 * Numbering status/preview read queries (PLT-125, CG-S6-PLT-022). Thin, typed wrappers
 * around app.get_numbering_allocation_status / app.format_numbering_value
 * (supabase/migrations/20260719110000_create_numbering_engine.sql) -- the "format
 * preview/config view models" Prompt 125 §15 calls for.
 */

import {
  GetNumberingAllocationStatusInputSchema,
  FormatNumberingPreviewInputSchema,
  parseNumberingAllocation,
  type GetNumberingAllocationStatusInput,
  type FormatNumberingPreviewInput,
  type NumberingAllocation,
} from "../contracts/numbering/numbering.ts";

export interface NumberingQueryRpcClient {
  rpc(
    fn: "get_numbering_allocation_status" | "format_numbering_value",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class NumberingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NumberingQueryError";
  }
}

/** Authority-gated -- raises insufficient_authority if the actor is not an active member of the allocation's tenant (nor Supreme Admin). */
export async function getNumberingAllocationStatus(client: NumberingQueryRpcClient, input: GetNumberingAllocationStatusInput): Promise<NumberingAllocation> {
  const parsedInput = GetNumberingAllocationStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("get_numbering_allocation_status", {
    p_allocation_id: parsedInput.allocationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new NumberingQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new NumberingQueryError("get_numbering_allocation_status returned no row");
  }
  return parseNumberingAllocation(data as Record<string, unknown>);
}

/** Pure, side-effect-free preview render of a format template against a candidate seq -- never allocates or consumes a real counter value, safe for a live "here's what your next number will look like" admin-form preview. */
export async function formatNumberingPreview(client: NumberingQueryRpcClient, input: FormatNumberingPreviewInput): Promise<string> {
  const parsedInput = FormatNumberingPreviewInputSchema.parse(input);
  const { data, error } = await client.rpc("format_numbering_value", {
    p_format: parsedInput.format,
    p_seq: parsedInput.seq,
    p_padding: parsedInput.padding,
    p_scope_code: parsedInput.scopeCode,
    // asOf is optional: omitting the key (rather than sending an explicit null) lets
    // the RPC's own `default now()` apply -- an explicit SQL NULL would override the
    // default and propagate through every replace() in app.format_numbering_value(),
    // producing a null result instead of "now".
    ...(parsedInput.asOf !== null ? { p_as_of: parsedInput.asOf } : {}),
  });
  if (error) {
    throw new NumberingQueryError(error.message);
  }
  if (typeof data !== "string") {
    throw new NumberingQueryError("format_numbering_value returned a non-string result");
  }
  return data;
}
