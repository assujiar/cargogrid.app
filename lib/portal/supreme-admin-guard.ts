/**
 * Supreme Admin portal entry guard (PLT-136, CG-S6-PLT-033). Simpler than
 * `tenant-admin-guard.ts`: Supreme Admin membership is tenant-independent
 * (`app.resolve_access_context(auth_user_id, null)` resolves a live Supreme Admin
 * grant globally, before any tenant-scoped lookup -- PLT-108's own migration, "a live
 * Supreme Admin grant always resolves first and alone"), so there is no slug/RLS
 * lookup step here at all.
 *
 * Portal-entry gating only (a coarse, layer-level check) -- not a substitute for
 * RBAC/RLS enforcement inside any individual query a page makes, unchanged. Pure
 * business logic, decoupled from the concrete Supabase client, the same
 * `RpcClient`-interface pattern this repository's `server/queries|mutations/*.ts` and
 * `tenant-admin-guard.ts` already use -- fully unit-testable with mocked
 * collaborators, no live database required.
 */

export interface ResolvedSupremeContextResult {
  readonly layer: string;
}

export interface SupremeAdminGuardDeps {
  /** Resolves to the authenticated principal's `auth.users.id`, or `null` if unauthenticated. Backed by `supabase.auth.getUser()` (RLS-scoped client) -- never `getSession()`. */
  getCurrentUserId(): Promise<string | null>;
  /** Calls `app.resolve_access_context(auth_user_id, null)` via the service-role client (PLT-108) -- `service_role`-only. Returns `null` if the identity holds no active principal membership at all (the function raises `no_active_membership`/`ambiguous_context` for those cases; the real wiring in `supreme-admin-guard-deps.server.ts` catches both and maps them to `null` here). */
  resolveGlobalAccessContext(authUserId: string): Promise<ResolvedSupremeContextResult | null>;
}

export type SupremeAdminGuardResult =
  | { readonly status: "unauthenticated" }
  | { readonly status: "forbidden"; readonly layer: string }
  | { readonly status: "allowed"; readonly authUserId: string; readonly layer: "supreme_admin" };

const REQUIRED_LAYER = "supreme_admin";

export async function resolveSupremeAdminAccess(deps: SupremeAdminGuardDeps): Promise<SupremeAdminGuardResult> {
  const authUserId = await deps.getCurrentUserId();
  if (!authUserId) {
    return { status: "unauthenticated" };
  }

  const context = await deps.resolveGlobalAccessContext(authUserId);
  if (!context || context.layer !== REQUIRED_LAYER) {
    return { status: "forbidden", layer: context?.layer ?? "none" };
  }

  return { status: "allowed", authUserId, layer: "supreme_admin" };
}
