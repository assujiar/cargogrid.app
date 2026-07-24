/**
 * Server-side tenant portal theme resolution (CargoGrid Design System Expansion,
 * docs/design-system/01_TOKENS_AND_THEME.md §4). Bridges the real Supabase RPC
 * (`server/queries/white-label.ts`'s `evaluateTenantBrand`, `app.evaluate_tenant_brand`)
 * to the pure `resolvePortalTheme` function, request-memoized with `React.cache()` --
 * the same pattern `lib/portal/resolve-tenant-admin-access.server.ts` already
 * establishes for the access guard itself.
 *
 * Any failure (missing/unreachable Supabase, RPC error, malformed response) falls back
 * to the CargoGrid default theme rather than throwing -- ADR-0017 §4: "on any
 * tenant-resolution failure, render CargoGrid default, never a partial/flash-of-invalid
 * theme, never leak the internal resolution error to the response." The underlying error
 * is intentionally swallowed here, not logged to the response or thrown up to the page.
 */

import { cache } from "react";
import { createSupabaseServerClient } from "../supabase/server.ts";
import { evaluateTenantBrand, type WhiteLabelQueryRpcClient } from "../../server/queries/white-label.ts";
import { resolvePortalTheme, type PortalThemeResult } from "../theme/resolve-portal-theme.ts";

export const resolveTenantPortalThemeForRequest = cache(async (tenantId: string): Promise<PortalThemeResult> => {
  try {
    const supabase = await createSupabaseServerClient();
    // Adapts the real Supabase client to `WhiteLabelQueryRpcClient`'s plain-`Promise`
    // shape -- `supabase.rpc()` itself returns a thenable `PostgrestFilterBuilder`, not
    // a structural `Promise` (missing `catch`/`finally`), which an `async` wrapper
    // normalizes without changing behavior.
    const client: WhiteLabelQueryRpcClient = { rpc: async (fn, args) => await supabase.rpc(fn, args) };
    const brand = await evaluateTenantBrand(client, { tenantId });
    return resolvePortalTheme(brand);
  } catch {
    return resolvePortalTheme(null);
  }
});
