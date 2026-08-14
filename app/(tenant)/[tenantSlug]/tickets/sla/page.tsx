import { notFound } from "next/navigation";
import { resolveTicketAccessForRequest } from "../../../../../lib/portal/resolve-ticket-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listSlaCalendars, listSlaCalendarVersions, listSlaPolicies, listSlaPolicyVersions, listTicketCategories, TicketQueryError } from "../../../../../server/queries/ticketing.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { SlaAdminPanel } from "./sla-admin-panel.tsx";
import {
  createSlaCalendarAction,
  createSlaCalendarVersionAction,
  addSlaCalendarBusinessHoursAction,
  addSlaCalendarHolidayAction,
  publishSlaCalendarVersionAction,
  createSlaPolicyAction,
  createSlaPolicyVersionAction,
  publishSlaPolicyVersionAction,
} from "../actions.ts";

/**
 * SLA policy/calendar administration (HRT-289, CG-S12-HRT-017). A
 * tenant-scoped configuration surface, deliberately kept under `tickets/`
 * (never a separate top-level route) -- SLA is tightly ticket-coupled, the
 * same reasoning that keeps its service-layer code inside
 * server/contracts/ticketing/ticketing.ts rather than a sibling module (see
 * that file's own header). Every write here is TKT:Edit-gated at the RPC
 * layer; this page renders the forms for any tenant member and lets the
 * server enforce the bar, exactly like the queue/category catalog forms on
 * the parent /tickets page already do.
 *
 * Deliberately does NOT expose customer_account_id/queue_id/support_queue_id
 * scope narrowing in this first surface -- channel/category/priority cover
 * the common cases; a per-customer-account or per-queue override remains
 * creatable only via a direct RPC call today. Disclosed, not hidden.
 */
export default async function SlaAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTicketAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let calendars: Awaited<ReturnType<typeof listSlaCalendars>> = [];
  let calendarVersionsByCalendar: Record<string, Awaited<ReturnType<typeof listSlaCalendarVersions>>> = {};
  let policies: Awaited<ReturnType<typeof listSlaPolicies>> = [];
  let policyVersionsByPolicy: Record<string, Awaited<ReturnType<typeof listSlaPolicyVersions>>> = {};
  let categories: Awaited<ReturnType<typeof listTicketCategories>> = [];

  try {
    [calendars, policies, categories] = await Promise.all([
      listSlaCalendars(supabase, access.tenant.id, access.authUserId),
      listSlaPolicies(supabase, access.tenant.id, access.authUserId),
      listTicketCategories(supabase, access.tenant.id, access.authUserId),
    ]);
    const calendarEntries = await Promise.all(calendars.map(async (c) => [c.id, await listSlaCalendarVersions(supabase, c.id, access.authUserId)] as const));
    calendarVersionsByCalendar = Object.fromEntries(calendarEntries);
    const policyEntries = await Promise.all(policies.map(async (p) => [p.id, await listSlaPolicyVersions(supabase, p.id, access.authUserId)] as const));
    policyVersionsByPolicy = Object.fromEntries(policyEntries);
  } catch (error) {
    if (!(error instanceof TicketQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading SLA configuration. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">SLA policies &amp; calendars</h1>
        <p className="text-xs text-neutral-500">
          A ticket&apos;s clock starts against the exact policy and calendar version published at that moment -- a later change here never rewrites a running clock.
        </p>
      </div>

      <SlaAdminPanel
        calendars={calendars}
        calendarVersionsByCalendar={calendarVersionsByCalendar}
        policies={policies}
        policyVersionsByPolicy={policyVersionsByPolicy}
        categories={categories}
        createCalendarAction={createSlaCalendarAction.bind(null, tenantSlug)}
        createCalendarVersionAction={(calendarId: string) => createSlaCalendarVersionAction.bind(null, tenantSlug, calendarId)}
        addBusinessHoursAction={(calendarVersionId: string) => addSlaCalendarBusinessHoursAction.bind(null, tenantSlug, calendarVersionId)}
        addHolidayAction={(calendarVersionId: string) => addSlaCalendarHolidayAction.bind(null, tenantSlug, calendarVersionId)}
        publishCalendarVersionAction={(versionId: string, expectedVersion: number) => publishSlaCalendarVersionAction.bind(null, tenantSlug, versionId, expectedVersion)}
        createPolicyAction={createSlaPolicyAction.bind(null, tenantSlug)}
        createPolicyVersionAction={(policyId: string) => createSlaPolicyVersionAction.bind(null, tenantSlug, policyId)}
        publishPolicyVersionAction={(versionId: string, expectedVersion: number) => publishSlaPolicyVersionAction.bind(null, tenantSlug, versionId, expectedVersion)}
      />
    </div>
  );
}
