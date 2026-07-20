/**
 * The shared 8-stage access-evaluation pipeline (docs/architecture/06_RLS_RBAC_WORKSTREAM.md
 * §3: "1 Entitlement → 2 Tenant membership → 3 RBAC action → 4 Scope check → 5
 * Field-level policy → 6 Status/value rule → 7 RLS enforcement at database → 8 Audit
 * for sensitive access") composed into one function every REST route handler and
 * GraphQL resolver calls -- "Neither interface is secondary or may bypass common
 * service/access rules" (Prompt 130 §24). This module introduces no new authority
 * logic of its own; it exclusively composes PLT-106/108/112/114's already-built,
 * already-tested primitives in the architecture's own fixed order.
 *
 * Stage coverage, disclosed rather than left implicit:
 * - Stage 1 (entitlement): `evaluateEntitlement()` (PLT-106).
 * - Stage 2 (tenant membership / four-layer context): `resolveAccessContext()` (PLT-108).
 * - Stage 3 (RBAC action): `assertPermission()` (PLT-112, `server/policies/permission-check.ts`
 *   -- the exact shared kernel `06_*.md` §3 already names for stages 3-8, reused directly).
 * - Stage 4 (scope check, 14 dimensions): **no-op, disclosed** -- no scope model exists
 *   anywhere in this repository yet (`08_API_INTEGRATION_WORKSTREAM.md` §6 defines the
 *   dimensions but no enforcement surface has been built for it).
 * - Stage 5 (field-level policy / record-level access): `canAccessRecord()` (PLT-114),
 *   invoked only when the caller supplies `recordOwnership` (no business-domain table
 *   with a real `owner_user_id` exists yet, so most callers today have nothing to pass).
 * - Stage 6 (status/value rule): **no-op, disclosed** -- domain-specific, no business
 *   entity exists yet to have a status/value rule over.
 * - Stage 7 (RLS enforcement): automatic at the database layer once the caller issues
 *   its own subsequent query -- nothing to call from this module.
 * - Stage 8 (audit): **the caller's own responsibility**, not this pipeline's -- every
 *   existing mutation module in this repository calls `app.capture_audit_event()`
 *   itself after performing its actual state change; a read-only access check does not
 *   itself create an audit_logs row (the established pattern throughout this session),
 *   so this function does not silently audit every call either.
 *
 * Disclosed NOT_RUN: wiring this into a live REST route handler or GraphQL resolver --
 * no such surface exists anywhere in this repository yet (`08_*.md` line 11). Proven
 * against injected structural clients today, the same "representative adapter" pattern
 * `permission-check.ts` itself already used.
 */

import { evaluateEntitlement, type EntitlementCache, type EntitlementRpcClient } from "../queries/entitlement.ts";
import { resolveAccessContext, type AccessContextRpcClient } from "../queries/access-context.ts";
import { canAccessRecord, type FieldAccessRpcClient } from "../queries/field-access.ts";
import { assertPermission, RbacDenialError } from "./permission-check.ts";
import type { RbacDecisionCache, RbacRpcClient } from "../queries/rbac.ts";
import type { AccessContext } from "../contracts/access-context/access-context.ts";
import type { EntitlementDecision } from "../contracts/entitlement/entitlement.ts";
import type { RbacDecision } from "../contracts/rbac/rbac.ts";

export interface ApiRequestContextDeps {
  entitlementClient: EntitlementRpcClient;
  accessContextClient: AccessContextRpcClient;
  rbacClient: RbacRpcClient;
  recordAccessClient?: FieldAccessRpcClient;
}

export interface ApiRequestContextCaches {
  entitlementCache?: EntitlementCache;
  rbacCache?: RbacDecisionCache;
}

export interface RecordOwnershipInput {
  ownerUserId: string;
  sharedOrgUnitIds?: string[];
  customerAccountRef?: string | null;
}

export interface ApiRequestContextInput {
  authUserId: string;
  tenantId: string;
  customerAccountRef?: string | null;
  moduleCode: string;
  featureCode?: string;
  action: string;
  recordOwnership?: RecordOwnershipInput;
}

export type ApiRequestContextStage = "entitlement" | "record_access";

/** Stage 2/3 failures propagate as AccessContextResolutionError/RbacDenialError directly (their own established typed-reason error classes) -- this class covers only the stages that have no such class of their own yet. */
export class ApiRequestContextDenialError extends Error {
  readonly stage: ApiRequestContextStage;
  readonly reason: string;

  constructor(stage: ApiRequestContextStage, reason: string) {
    super(`api request context denied at stage "${stage}": ${reason}`);
    this.name = "ApiRequestContextDenialError";
    this.stage = stage;
    this.reason = reason;
  }
}

export interface ResolvedApiRequestContext {
  readonly entitlement: EntitlementDecision;
  readonly accessContext: AccessContext;
  readonly rbacDecision: RbacDecision;
  /** null when the caller supplied no recordOwnership (stage 5 not applicable to this call). */
  readonly recordAccessGranted: boolean | null;
}

/** Walks stages 1 → 2 → 3 → 5 in the architecture's own fixed order, failing closed (throwing) at the first denied stage rather than continuing. Stages 4/6 are disclosed no-ops; stage 7 is automatic; stage 8 is the caller's own responsibility. */
export async function resolveApiRequestContext(
  deps: ApiRequestContextDeps,
  input: ApiRequestContextInput,
  caches?: ApiRequestContextCaches,
): Promise<ResolvedApiRequestContext> {
  // Stage 1: entitlement.
  const entitlement = await evaluateEntitlement(
    deps.entitlementClient,
    { tenantId: input.tenantId, moduleCode: input.moduleCode, featureCode: input.featureCode },
    caches?.entitlementCache,
  );
  if (!entitlement.allowed) {
    throw new ApiRequestContextDenialError("entitlement", entitlement.reason);
  }

  // Stage 2: tenant membership / four-layer context. resolveAccessContext() already
  // throws its own AccessContextResolutionError on failure -- propagated as-is.
  const accessContext = await resolveAccessContext(deps.accessContextClient, {
    authUserId: input.authUserId,
    tenantId: input.tenantId,
    customerAccountRef: input.customerAccountRef ?? null,
  });

  // Stage 3: RBAC action. assertPermission() already throws its own RbacDenialError on
  // failure -- propagated as-is (re-exported below for callers that only import this
  // module).
  const rbacDecision = await assertPermission(
    deps.rbacClient,
    { authUserId: input.authUserId, tenantId: input.tenantId, resourceModuleCode: input.moduleCode, action: input.action },
    caches?.rbacCache,
  );

  // Stage 4: scope check -- no-op, disclosed (this module's own header).

  // Stage 5: field-level policy / record-level access, only when the caller has an
  // actual record to check ownership against.
  let recordAccessGranted: boolean | null = null;
  if (input.recordOwnership) {
    if (!deps.recordAccessClient) {
      throw new ApiRequestContextDenialError("record_access", "record_ownership_supplied_without_a_record_access_client");
    }
    recordAccessGranted = await canAccessRecord(deps.recordAccessClient, {
      authUserId: input.authUserId,
      tenantId: input.tenantId,
      ownerUserId: input.recordOwnership.ownerUserId,
      sharedOrgUnitIds: input.recordOwnership.sharedOrgUnitIds ?? [],
      customerAccountRef: input.recordOwnership.customerAccountRef ?? null,
    });
    if (!recordAccessGranted) {
      throw new ApiRequestContextDenialError("record_access", "record_access_denied");
    }
  }

  // Stage 6: status/value rule -- no-op, disclosed (this module's own header).
  // Stage 7: RLS -- automatic at the database layer, nothing to call here.
  // Stage 8: audit -- the caller's own responsibility, not this pipeline's.

  return { entitlement, accessContext, rbacDecision, recordAccessGranted };
}

export { RbacDenialError };
