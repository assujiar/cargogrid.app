import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listEmployees, EmployeeQueryError } from "../../../../../server/queries/employee.ts";
import type { EmployeeLifecycleStatus } from "../../../../../server/contracts/employee/employee.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { EmployeeDirectoryPanel } from "./employee-directory-panel.tsx";
import { createEmployeeDraftAction } from "./actions.ts";

/**
 * Employee directory (HRT-274, CG-S12-HRT-002) -- the first Phase 7 UI. Cursor-
 * paginated, server-filtered/searched (section 17: "no client-loaded full dataset").
 * The create form collects only the fields app.create_employee_draft needs for a
 * draft; org unit/manager assignment, emergency contacts, and submission happen
 * afterward on the employee's own detail page, matching the database's own
 * draft-then-enrich shape rather than a separate client-only wizard state machine
 * (mirrors app/(tenant)/[tenantSlug]/procurement/vendors/page.tsx's own identical
 * choice).
 */
export default async function EmployeeDirectoryPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string; q?: string; after?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status, q, after } = await searchParams;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as EmployeeLifecycleStatus) : null) ?? null;

  let loadFailed = false;
  let denied = false;
  let employees: Awaited<ReturnType<typeof listEmployees>> = [];
  try {
    employees = await listEmployees(supabase, access.tenant.id, access.authUserId, { statusFilter, search: q ?? null, limit: 50, afterEmployeeNumber: after ?? null });
  } catch (error) {
    if (!(error instanceof EmployeeQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else loadFailed = true;
  }

  if (denied) {
    return <ErrorState title="Access denied" description="You don't have HR permission to view the employee directory." />;
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the employee directory. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Employees</h1>
        <p className="text-xs text-neutral-500">Canonical workforce identity, linked to Platform user and organization records. One employee identity, reused across HR, self-service, and downstream HRIS capabilities.</p>
      </div>

      <EmployeeDirectoryPanel tenantSlug={tenantSlug} employees={employees} statusFilter={statusFilter} search={q ?? ""} createAction={createEmployeeDraftAction.bind(null, tenantSlug)} />
    </div>
  );
}
