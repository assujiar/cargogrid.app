/**
 * Employee and Manager Self-Service (ESS/MSS) composed write (HRT-285,
 * CG-S12-HRT-013). This module adds exactly ONE genuinely composed
 * mutation: routing a single "decide this manager-queue item" action to
 * the correct OWNING capability's own canonical `decide*` RPC by `kind`.
 * It is a pure dispatcher -- it performs zero authority check, zero
 * validation, and zero audit write of its own; every one of those is the
 * owning capability's own RPC's job, called through its own already-
 * `VERIFIED`/`COMPLETED` mutation wrapper, unchanged (Prompt 285 business
 * rule, section 24: "every write calls the canonical domain service and
 * shares validation, approval, audit and idempotency"). If a manager can
 * SEE a queue item (via `getMssTeamWorkspace`, HRT-285's own composed
 * read) but the owning capability's own decide RPC separately requires an
 * `HRS:Approve` grant the manager does not hold, this dispatcher does not
 * paper over that -- the underlying RPC's own `insufficient_authority`
 * error propagates unchanged, exactly as it would from that capability's
 * own dedicated admin page.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { decideLeaveRequest, LeaveMutationError } from "./leave.ts";
import { decideOvertimeRequest, decideTimesheetEntry, OvertimeTimesheetMutationError } from "./overtime-timesheet.ts";
import { decideTrainingEnrollment, TrainingTalentMutationError } from "./training-talent.ts";
import type { DecideManagerApprovalQueueItemInput, DecideManagerApprovalQueueItemResult } from "../contracts/self-service/self-service.ts";
import { DecideManagerApprovalQueueItemInputSchema } from "../contracts/self-service/self-service.ts";

export type SelfServiceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export class SelfServiceMutationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SelfServiceMutationError";
  }
}

function toSelfServiceMutationError(error: unknown): SelfServiceMutationError {
  if (error instanceof LeaveMutationError || error instanceof OvertimeTimesheetMutationError || error instanceof TrainingTalentMutationError) {
    return new SelfServiceMutationError(error.message);
  }
  if (error instanceof Error) return new SelfServiceMutationError(error.message);
  return new SelfServiceMutationError(String(error));
}

export async function decideManagerApprovalQueueItem(
  client: SelfServiceMutationRpcClient,
  input: DecideManagerApprovalQueueItemInput,
): Promise<DecideManagerApprovalQueueItemResult> {
  const parsed = DecideManagerApprovalQueueItemInputSchema.parse(input);
  try {
    switch (parsed.kind) {
      case "leave":
        await decideLeaveRequest(client, {
          requestStepId: parsed.requestStepId,
          decision: parsed.decision,
          reason: parsed.reason,
          overrideCoverage: parsed.overrideCoverage,
          actorAuthUserId: parsed.actorAuthUserId,
          actorLabel: parsed.actorLabel,
        });
        return { kind: "leave", id: parsed.requestStepId };
      case "overtime":
        await decideOvertimeRequest(client, {
          requestId: parsed.requestId,
          expectedVersion: parsed.expectedVersion,
          decision: parsed.decision,
          decidedReason: parsed.decidedReason,
          approvedMinutesOverride: parsed.approvedMinutesOverride,
          actorAuthUserId: parsed.actorAuthUserId,
          actorLabel: parsed.actorLabel,
        });
        return { kind: "overtime", id: parsed.requestId };
      case "timesheet_entry":
        await decideTimesheetEntry(client, {
          entryId: parsed.entryId,
          expectedVersion: parsed.expectedVersion,
          decision: parsed.decision,
          decidedReason: parsed.decidedReason,
          approvedMinutesOverride: parsed.approvedMinutesOverride,
          actorAuthUserId: parsed.actorAuthUserId,
          actorLabel: parsed.actorLabel,
        });
        return { kind: "timesheet_entry", id: parsed.entryId };
      case "training_enrollment":
        await decideTrainingEnrollment(client, {
          enrollmentId: parsed.enrollmentId,
          expectedVersion: parsed.expectedVersion,
          decision: parsed.decision,
          decisionReason: parsed.decisionReason,
          actorAuthUserId: parsed.actorAuthUserId,
          actorLabel: parsed.actorLabel,
        });
        return { kind: "training_enrollment", id: parsed.enrollmentId };
      default: {
        const exhaustive: never = parsed;
        throw new SelfServiceMutationError(`unknown_queue_item_kind: ${JSON.stringify(exhaustive)}`);
      }
    }
  } catch (error) {
    throw toSelfServiceMutationError(error);
  }
}
