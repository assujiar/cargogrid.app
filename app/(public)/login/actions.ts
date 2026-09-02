"use server";

/**
 * Sign-in Server Action (PLT-135/`136`, CG-S6-PLT-032/`033`). `app/(public)/` is a
 * shared, portal-agnostic route group (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`
 * §2.1) -- this checkpoint builds only the minimal real sign-in path the guarded
 * portals need an entry point for, not a full account-recovery/SSO surface.
 *
 * The organization field is now optional (`PLT-136`, CG-S6-PLT-033): a Tenant Admin
 * supplies their tenant's slug and lands on `/{slug}/admin`; CargoGrid staff (Supreme
 * Admin) leave it blank and land on `/supreme`. This is one shared entry point for both
 * portals, not a second login surface -- the *portal itself* still gates on the
 * resolved principal's actual layer (`lib/portal/{tenant-admin,supreme-admin}-guard.ts`)
 * regardless of which path this action redirects to; picking the wrong path here only
 * costs an extra guard-denied render, never grants anything. The redirect target is
 * still re-checked through `validateRedirectTarget` (PLT-107) as defense in depth, the
 * same discipline every redirect in this repository follows regardless of how the
 * target was derived.
 */

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../lib/supabase/server.ts";
import { validateRedirectTarget } from "../../../lib/auth/redirect-allowlist.ts";
import { registerLoginSessionIfApplicable } from "../../../lib/auth/register-login-session.ts";
import { buildRegisterLoginSessionDeps } from "../../../lib/auth/register-login-session-deps.server.ts";

const TENANT_SLUG_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

export interface SignInFormState {
  readonly error: string | null;
}

export async function signInAction(_prevState: SignInFormState, formData: FormData): Promise<SignInFormState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const tenantSlug = String(formData.get("tenantSlug") ?? "").trim();

  if (!email || !password) {
    return { error: "Email and password are required." };
  }
  if (tenantSlug && !TENANT_SLUG_PATTERN.test(tenantSlug)) {
    return { error: "That organization identifier doesn't look right." };
  }

  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    return { error: "Invalid email or password." };
  }

  // ISS-2026-264: best-effort session registration, never a login gate -- see
  // lib/auth/register-login-session.ts's own header for the full rationale. A
  // failure here (transient RPC error, unresolvable tenant) must never block an
  // otherwise-successful sign-in.
  if (data.user) {
    try {
      const deps = await buildRegisterLoginSessionDeps();
      await registerLoginSessionIfApplicable(deps, { tenantSlug, authUserId: data.user.id, actorLabel: email });
    } catch {
      // Session tracking is a defense-in-depth enhancement layered on top of
      // authentication, not a precondition for it -- swallow and proceed.
    }
  }

  const target = tenantSlug ? `/${tenantSlug}/admin` : "/supreme";
  const validation = validateRedirectTarget(target);
  if (!validation.safe) {
    return { error: "Unable to sign in to that organization." };
  }

  redirect(target);
}

/**
 * Sign-out Server Action -- the counterpart `lib/supabase/server.ts`'s own header already
 * described as existing ("login/logout (this checkpoint's own Server Actions) work
 * correctly without it") and which in fact did not: before `ISS-2026-246` there was no
 * sign-out path anywhere in this repository, so an authenticated principal could not end
 * their own session from any portal. Built here, beside `signInAction`, because this file
 * is already the one session-lifecycle action module and `app/(public)/` is the shared,
 * portal-agnostic route group all three shells (Tenant Admin, Commercial, Supreme) reach.
 *
 * `supabase.auth.signOut()` revokes the refresh token server-side and clears the session
 * cookie through the `setAll` writer in `lib/supabase/server.ts` -- writable here because
 * a Server Action is exactly the context Next.js permits cookie writes in (that file's own
 * header). A revocation failure (backend unreachable, token already expired) must still
 * land the caller on `/login` rather than leaving them stranded inside a shell they can no
 * longer act in, so the failure is swallowed and the redirect happens regardless; the
 * cookie write is the part that actually ends this browser's session.
 *
 * `redirect()` throws its control-flow signal, so it is deliberately outside the `try`.
 */
export async function signOutAction(): Promise<void> {
  try {
    const supabase = await createSupabaseServerClient();
    await supabase.auth.signOut();
  } catch {
    // Never trap a user inside a portal because sign-out could not reach the backend.
  }

  redirect("/login");
}
