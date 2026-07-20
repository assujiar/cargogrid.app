import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { resolveApiRequestContext, ApiRequestContextDenialError, type ApiRequestContextDeps } from "./api-request-context.ts";
import { RbacDenialError } from "./permission-check.ts";
import { AccessContextResolutionError } from "../queries/access-context.ts";

const AUTH_USER_ID = "123e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const MEMBERSHIP_ID = "323e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "423e4567-e89b-12d3-a456-426614174000";

const VALID_ENTITLEMENT_ROW = { allowed: true, reason: "granted", limit_value: null, package_code: "starter", evaluated_at: "2026-07-19T00:00:00.000Z" };
const DENIED_ENTITLEMENT_ROW = { allowed: false, reason: "module_not_entitled", limit_value: null, package_code: null, evaluated_at: "2026-07-19T00:00:00.000Z" };
const VALID_ACCESS_CONTEXT_ROW = {
  membership_id: MEMBERSHIP_ID,
  auth_user_id: AUTH_USER_ID,
  layer: "org_user",
  tenant_id: TENANT_ID,
  customer_account_ref: null,
  resolved_at: "2026-07-19T00:00:00.000Z",
};
const VALID_RBAC_ROW = { allowed: true, reason: "granted", permission_id: "523e4567-e89b-12d3-a456-426614174000", role_id: "623e4567-e89b-12d3-a456-426614174000", role_version_id: "723e4567-e89b-12d3-a456-426614174000", evaluated_at: "2026-07-19T00:00:00.000Z" };
const DENIED_RBAC_ROW = { allowed: false, reason: "no_active_assignment", permission_id: null, role_id: null, role_version_id: null, evaluated_at: "2026-07-19T00:00:00.000Z" };

function makeClient(fn: string, response: { data: unknown; error: { message: string } | null }) {
  return { async rpc(calledFn: string, _args: Record<string, unknown>) {
    assert.equal(calledFn, fn);
    return response;
  } };
}

function baseDeps(overrides?: Partial<ApiRequestContextDeps>): ApiRequestContextDeps {
  return {
    entitlementClient: makeClient("evaluate_entitlement", { data: VALID_ENTITLEMENT_ROW, error: null }) as ApiRequestContextDeps["entitlementClient"],
    accessContextClient: makeClient("resolve_access_context", { data: VALID_ACCESS_CONTEXT_ROW, error: null }) as ApiRequestContextDeps["accessContextClient"],
    rbacClient: makeClient("evaluate_permission", { data: VALID_RBAC_ROW, error: null }) as ApiRequestContextDeps["rbacClient"],
    ...overrides,
  };
}

describe("resolveApiRequestContext", () => {
  test("walks stages 1-3 and returns a granted context when every stage allows, with recordAccessGranted null when no record was supplied", async () => {
    const result = await resolveApiRequestContext(baseDeps(), {
      authUserId: AUTH_USER_ID,
      tenantId: TENANT_ID,
      moduleCode: "COM",
      action: "View",
    });
    assert.equal(result.entitlement.allowed, true);
    assert.equal(result.accessContext.layer, "org_user");
    assert.equal(result.rbacDecision.allowed, true);
    assert.equal(result.recordAccessGranted, null);
  });

  test("stage 1 (entitlement) denial throws ApiRequestContextDenialError and never reaches stage 2/3", async () => {
    let accessContextCalled = false;
    const deps = baseDeps({
      entitlementClient: makeClient("evaluate_entitlement", { data: DENIED_ENTITLEMENT_ROW, error: null }) as ApiRequestContextDeps["entitlementClient"],
      accessContextClient: { async rpc() { accessContextCalled = true; return { data: VALID_ACCESS_CONTEXT_ROW, error: null }; } } as ApiRequestContextDeps["accessContextClient"],
    });
    await assert.rejects(
      () => resolveApiRequestContext(deps, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, moduleCode: "COM", action: "View" }),
      (err: unknown) => {
        assert.ok(err instanceof ApiRequestContextDenialError);
        assert.equal(err.stage, "entitlement");
        assert.equal(err.reason, "module_not_entitled");
        return true;
      },
    );
    assert.equal(accessContextCalled, false);
  });

  test("stage 2 (tenant membership) denial propagates as AccessContextResolutionError, not a generic error", async () => {
    const deps = baseDeps({
      accessContextClient: makeClient("resolve_access_context", { data: null, error: { message: "no_active_membership: nothing found" } }) as ApiRequestContextDeps["accessContextClient"],
    });
    await assert.rejects(
      () => resolveApiRequestContext(deps, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, moduleCode: "COM", action: "View" }),
      AccessContextResolutionError,
    );
  });

  test("stage 3 (RBAC) denial propagates as RbacDenialError, not a generic error", async () => {
    const deps = baseDeps({
      rbacClient: makeClient("evaluate_permission", { data: DENIED_RBAC_ROW, error: null }) as ApiRequestContextDeps["rbacClient"],
    });
    await assert.rejects(
      () => resolveApiRequestContext(deps, { authUserId: AUTH_USER_ID, tenantId: TENANT_ID, moduleCode: "COM", action: "View" }),
      RbacDenialError,
    );
  });

  test("stage 5 (record access) is skipped (null) when recordOwnership is not supplied, and enforced when it is", async () => {
    const deps = baseDeps({
      recordAccessClient: { async rpc(fn: string) { assert.equal(fn, "can_access_record"); return { data: true, error: null }; } } as ApiRequestContextDeps["recordAccessClient"],
    });
    const result = await resolveApiRequestContext(deps, {
      authUserId: AUTH_USER_ID,
      tenantId: TENANT_ID,
      moduleCode: "COM",
      action: "View",
      recordOwnership: { ownerUserId: OWNER_ID },
    });
    assert.equal(result.recordAccessGranted, true);
  });

  test("stage 5 denial throws ApiRequestContextDenialError with stage=record_access", async () => {
    const deps = baseDeps({
      recordAccessClient: { async rpc() { return { data: false, error: null }; } } as ApiRequestContextDeps["recordAccessClient"],
    });
    await assert.rejects(
      () =>
        resolveApiRequestContext(deps, {
          authUserId: AUTH_USER_ID,
          tenantId: TENANT_ID,
          moduleCode: "COM",
          action: "View",
          recordOwnership: { ownerUserId: OWNER_ID },
        }),
      (err: unknown) => {
        assert.ok(err instanceof ApiRequestContextDenialError);
        assert.equal(err.stage, "record_access");
        assert.equal(err.reason, "record_access_denied");
        return true;
      },
    );
  });

  test("supplying recordOwnership without a recordAccessClient fails closed rather than silently skipping the check", async () => {
    const deps = baseDeps();
    await assert.rejects(
      () =>
        resolveApiRequestContext(deps, {
          authUserId: AUTH_USER_ID,
          tenantId: TENANT_ID,
          moduleCode: "COM",
          action: "View",
          recordOwnership: { ownerUserId: OWNER_ID },
        }),
      (err: unknown) => {
        assert.ok(err instanceof ApiRequestContextDenialError);
        assert.equal(err.stage, "record_access");
        return true;
      },
    );
  });
});
