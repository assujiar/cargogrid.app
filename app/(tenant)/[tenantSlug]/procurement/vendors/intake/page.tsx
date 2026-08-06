import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveConfig, type ConfigQueryRpcClient } from "../../../../../../server/queries/config.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { IntakePanel } from "./intake-panel.tsx";
import { createVendorIntakeTokenAction } from "../actions.ts";
import { setVendorSelfRegistrationEnabledAction } from "./actions.ts";

const SELF_REGISTRATION_KEY = "procurement.vendor_self_registration.enabled";

/**
 * Vendor intake configuration and invitation issuance (PRC-251, CG-S11-PRC-002).
 * Self-registration is off by default (BP-A08) and toggled per tenant via the
 * existing Configuration Engine; invitation tokens are single-use, one-time-visible
 * bearer secrets (app.create_vendor_intake_token never stores the raw value) -- there
 * is no persisted "list every issued token" RPC in this capability's own scope, so
 * this page shows only the current self-registration state and an issuance form, not
 * a token history table (disclosed simplification, not a missing capability -- the
 * database itself never exposes a list read for token rows beyond RLS-scoped SELECT).
 */
export default async function VendorIntakeSettingsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabaseClient = await createSupabaseServerClient();
  // Same thenable-to-Promise adapter the sibling actions.ts uses.
  const supabase: ConfigQueryRpcClient = { rpc: async (fn, args) => await supabaseClient.rpc(fn, args) };

  let selfRegistrationEnabled = false;
  let loadFailed = false;
  try {
    const resolved = await resolveConfig(supabase, { configTypeCode: "feature", tenantId: access.tenant.id, companyId: null, branchId: null, roleId: null, userId: null });
    selfRegistrationEnabled = Boolean(resolved?.items[SELF_REGISTRATION_KEY]);
  } catch {
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading intake settings. Please try again." />;
  }

  return (
    <IntakePanel
      selfRegistrationEnabled={selfRegistrationEnabled}
      tenantSlug={tenantSlug}
      toggleAction={setVendorSelfRegistrationEnabledAction.bind(null, tenantSlug)}
      issueTokenAction={createVendorIntakeTokenAction.bind(null, tenantSlug)}
    />
  );
}
