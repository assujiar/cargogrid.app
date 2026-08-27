/**
 * Post-sign-in session registration (ISS-2026-264, Step 16 historical-issue-backlog
 * remediation). `app.user_sessions`/`app.register_user_session` (IAE-027,
 * `20260807100000_create_intelligence_enterprise_mfa_session_controls.sql`) existed with
 * a real revoke path (`app.revoke_all_actor_sessions`) but was never called from
 * anywhere in this application -- `docs/runtime/KNOWN_ISSUES.md` `ISS-2026-264` found
 * that session revocation therefore had zero real enforcement effect anywhere (nothing
 * ever consulted `app.user_sessions.status`), and this file's own investigation found
 * the deeper reason why: no session row was ever being created in the first place.
 *
 * Pure logic, decoupled from the concrete Supabase clients -- the same `*Deps`-interface
 * pattern `lib/portal/commercial-guard.ts` and friends already use, unit-testable with
 * mocked collaborators, no live database required. The real wiring lives in
 * `register-login-session-deps.server.ts`.
 *
 * Deliberately best-effort, never a login gate: the caller (`app/(public)/login/actions.ts`)
 * wraps this in a try/catch so any failure here (a transient RPC error, an unresolvable
 * tenant) never blocks a legitimate sign-in -- session tracking is a defense-in-depth
 * enhancement layered on top of authentication, not a precondition for it. A tenant
 * slug of `""` (the Supreme Admin path, PLT-136) is a deliberate no-op: Supreme Admin
 * membership is tenant-independent and `app.user_sessions.tenant_id` is `NOT NULL`, so
 * there is structurally nothing to register against -- unaffected, since
 * `app.evaluate_permission`'s own Supreme Admin branch already resolves and returns
 * before it would ever reach a session check (see `20260826110000_harden_evaluate_
 * permission_session_revocation_enforcement.sql`).
 */

export interface RegisterLoginSessionTenantLookup {
  readonly id: string;
}

export interface RegisterLoginSessionAccessContext {
  readonly layer: string;
}

export interface RegisterLoginSessionDeps {
  findTenantBySlug(slug: string): Promise<RegisterLoginSessionTenantLookup | null>;
  resolveAccessContext(authUserId: string, tenantId: string): Promise<RegisterLoginSessionAccessContext | null>;
  registerSession(tenantId: string, authUserId: string, actorLabel: string): Promise<void>;
}

export interface RegisterLoginSessionParams {
  readonly tenantSlug: string;
  readonly authUserId: string;
  readonly actorLabel: string;
}

/**
 * Registers a tracked session for a real, resolved tenant membership after a successful
 * sign-in. Silently does nothing (never throws for these cases) when: the sign-in was
 * the tenant-independent Supreme Admin path (blank slug); the slug does not resolve to
 * a real tenant; or the identity holds no active principal membership in that tenant --
 * in every one of these cases there is nothing to register a session against, and the
 * existing portal guards remain the real authorization boundary regardless.
 */
export async function registerLoginSessionIfApplicable(deps: RegisterLoginSessionDeps, params: RegisterLoginSessionParams): Promise<void> {
  if (!params.tenantSlug) {
    return;
  }

  const tenant = await deps.findTenantBySlug(params.tenantSlug);
  if (!tenant) {
    return;
  }

  const context = await deps.resolveAccessContext(params.authUserId, tenant.id);
  if (!context) {
    return;
  }

  await deps.registerSession(tenant.id, params.authUserId, params.actorLabel);
}
