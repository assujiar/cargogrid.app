import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getMyEmployeeProfile, EmployeeQueryError } from "../../../../../../server/queries/employee.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { MyProfilePanel } from "./my-profile-panel.tsx";
import { requestMyProfileChangeAction } from "./actions.ts";

/**
 * Own-profile read/request-change view (HRT-274, section 15's "own read/request-
 * change view"; section 20 main-alternative-flow "employee ... requests personal-data
 * correction"). Unmasked (it is always the caller's own data) -- app.get_my_employee_
 * profile itself resolves ownership by identity match, never a client-supplied id.
 */
export default async function MyEmployeeProfilePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let profile: Awaited<ReturnType<typeof getMyEmployeeProfile>> = null;
  try {
    profile = await getMyEmployeeProfile(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof EmployeeQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your employee profile. Please try again." />;
  }
  if (!profile) {
    return <EmptyState title="No employee profile linked to your account yet" description="Ask HR to link your Platform user to your employee record." />;
  }

  return <MyProfilePanel profile={profile} requestChangeAction={requestMyProfileChangeAction.bind(null, tenantSlug, profile.masterRecordId)} />;
}
