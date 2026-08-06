import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveVendorSelfRegistrationTarget } from "../../../../../server/mutations/vendor-profile.ts";
import { VendorSelfRegistrationForm } from "./register-form.tsx";

/**
 * Public, unauthenticated vendor self-registration page (PRC-251, CG-S11-PRC-002).
 * Closes a real gap found in adversarial review: the self-registration flag
 * (app.is_vendor_self_registration_enabled), the anonymous RPC
 * (app.submit_vendor_profile_self_registration), and its mutation wrapper
 * (submitVendorProfileSelfRegistration) were all fully built and unit-tested, but no
 * public route ever called it -- only the token-based invite flow
 * (app/(public)/vendor-intake/[token]/) was reachable.
 *
 * Deliberately keyed by tenant SLUG, not tenant_id -- a slug is already a public,
 * URL-visible identifier (every tenant portal route is `/{tenantSlug}/...`), never a
 * secret. app.resolve_vendor_self_registration_target (service_role-only) is the
 * one and only slug->tenant_id resolution path and collapses "slug does not exist",
 * "tenant is not active", and "self-registration is not enabled for this tenant"
 * into the SAME uniform "not available" response below -- this page can never be
 * used to enumerate valid tenant slugs or their configuration state.
 *
 * Never reads any existing tenant/vendor data beyond that single boolean gate --
 * app.submit_vendor_profile_self_registration itself only ever writes the caller's
 * own staged submission (Prompt 251 §16).
 */
export default async function VendorSelfRegistrationPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;

  // Fails safe (renders the "not available" state, never a 500) if the resolver
  // itself is unreachable -- the same fail-closed discipline every other guard in
  // this repository follows when its own backend cannot be reached.
  const target = await (async () => {
    try {
      const client = createSupabaseServiceRoleClient();
      return await resolveVendorSelfRegistrationTarget(client, tenantSlug);
    } catch {
      return { tenantId: null, selfRegistrationEnabled: false };
    }
  })();

  if (!target.selfRegistrationEnabled || !target.tenantId) {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col gap-4 px-4 py-10">
        <h1 className="text-xl font-semibold text-neutral-900">Vendor registration is not available</h1>
        <p className="text-sm text-neutral-600">This organization is not currently accepting vendor self-registration. Please contact them directly for an invitation.</p>
      </main>
    );
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col gap-6 px-4 py-10">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor registration</h1>
        <p className="text-sm text-neutral-600">Register your company as a vendor. Your submission will be staged for review -- it does not grant automatic approval or access.</p>
      </div>
      <VendorSelfRegistrationForm tenantId={target.tenantId} />
    </main>
  );
}
