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
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    return { error: "Invalid email or password." };
  }

  const target = tenantSlug ? `/${tenantSlug}/admin` : "/supreme";
  const validation = validateRedirectTarget(target);
  if (!validation.safe) {
    return { error: "Unable to sign in to that organization." };
  }

  redirect(target);
}
