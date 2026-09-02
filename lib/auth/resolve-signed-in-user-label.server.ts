/**
 * Resolves a display label for the currently signed-in principal, for portal chrome only
 * (`ISS-2026-246`).
 *
 * Every portal guard in `lib/portal/` deliberately returns an `authUserId` and nothing
 * else -- a uuid is the right currency for an authorization decision and the wrong thing
 * to print in a header. This helper is the presentation-side counterpart: it asks the
 * RLS-scoped client for the principal's own `auth.users` record and returns the email,
 * which is the only human-readable identifier this repository stores for a Platform user
 * (there is no profile/display-name table -- `server/queries/` has none, and inventing one
 * to render a nicer header would be a schema change, not chrome).
 *
 * `React.cache()` dedupes it across the layout and every nested Server Component in a
 * single render pass, exactly as `lib/portal/resolve-*-access.server.ts` already does for
 * the guards -- the header must not cost a second `auth.getUser()` round trip per page.
 *
 * Returns `null` rather than throwing when there is no session or the backend is
 * unreachable: this is chrome, and a portal must still render (and its guard must still
 * be the thing that decides access) when a decorative label cannot be resolved. It is
 * **never** an authorization signal -- a non-null label means "we could read a session",
 * not "this principal may be here", which every layout below still asks its own guard.
 */

import { cache } from "react";
import { createSupabaseServerClient } from "../supabase/server.ts";

export const resolveSignedInUserLabelForRequest = cache(async (): Promise<string | null> => {
  try {
    const supabase = await createSupabaseServerClient();
    const { data, error } = await supabase.auth.getUser();
    if (error || !data.user) return null;
    return data.user.email ?? null;
  } catch {
    return null;
  }
});
