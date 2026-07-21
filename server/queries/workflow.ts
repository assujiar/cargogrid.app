/**
 * Workflow instance read queries (PLT-122, CG-S6-PLT-019). Thin, typed wrapper around
 * app.get_workflow_instance_history
 * (supabase/migrations/20260717140000_create_workflow_engine.sql) -- the view-model
 * Prompt 122 §15 calls for ("reusable transition/action/timeline view models").
 */

import {
  GetWorkflowInstanceHistoryInputSchema,
  parseWorkflowTransitionHistoryEntry,
  type GetWorkflowInstanceHistoryInput,
  type WorkflowTransitionHistoryEntry,
} from "../contracts/workflow/workflow.ts";

export interface WorkflowQueryRpcClient {
  rpc(
    fn: "get_workflow_instance_history",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class WorkflowQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "WorkflowQueryError";
  }
}

/** Ordered oldest-first (app.get_workflow_instance_history()'s own `order by occurred_at`). Authority-gated -- raises insufficient_authority if the actor is not an active member of the instance's tenant (nor Supreme Admin). */
export async function getWorkflowInstanceHistory(
  client: WorkflowQueryRpcClient,
  input: GetWorkflowInstanceHistoryInput,
): Promise<WorkflowTransitionHistoryEntry[]> {
  const parsedInput = GetWorkflowInstanceHistoryInputSchema.parse(input);
  const { data, error } = await client.rpc("get_workflow_instance_history", {
    p_instance_id: parsedInput.instanceId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });

  if (error) {
    throw new WorkflowQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new WorkflowQueryError("get_workflow_instance_history returned a non-array result");
  }
  return data.map((row) => parseWorkflowTransitionHistoryEntry(row as Record<string, unknown>));
}
