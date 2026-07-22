"use server";

/**
 * Sign-in Server Action (PLT-135, CG-S6-PLT-032). `app/(public)/` is a shared,
 * portal-agnostic route group (`docs/architecture/09_UX_DESIGN_SYSTEM_WORKSTREAM.md`
 * §2.1) -- this checkpoint builds only the minimal real sign-in path the Tenant Admin
 * portal's own guard needs an entry point for, not a full account-recovery/SSO surface
 * (out of Prompt 135's own bounded scope, §11/§12).
 *
 * Requires a tenant slug alongside email/password (this repository's multi-tenant
 * model has no single global login -- Prompt 135 §21's own main flow: "Tenant Admin
 * signs in and manages authorized own-tenant platform configuration"). The redirect
 * target is server-constructed from the validated slug, still re-checked through
 * `validateRedirectTarget` (PLT-107) as defense in depth, the same discipline every
 * redirect in this repository follows regardless of how the target was derived.
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

  if (!email || !password || !tenantSlug) {
    return { error: "Email, password, and organization are all required." };
  }
  if (!TENANT_SLUG_PATTERN.test(tenantSlug)) {
    return { error: "That organization identifier doesn't look right." };
  }

  const supabase = await createSupabaseServerClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) {
    return { error: "Invalid email or password." };
  }

  const target = `/${tenantSlug}/admin`;
  const validation = validateRedirectTarget(target);
  if (!validation.safe) {
    return { error: "Unable to sign in to that organization." };
  }

  redirect(target);
}
