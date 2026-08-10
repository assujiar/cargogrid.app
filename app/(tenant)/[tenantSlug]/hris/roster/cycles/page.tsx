import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listRosterCycles, getRosterCycleDetail, listShiftTemplates, ShiftRosterQueryError } from "../../../../../../server/queries/shift-roster.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { RosterCyclePanel } from "./roster-cycle-panel.tsx";
import { createRosterCycleAction, setRosterCycleSlotAction, publishRosterCycleAction, generateRosterScheduleAssignmentsAction } from "./actions.ts";
import type { RosterCycleDetail } from "../../../../../../server/contracts/shift-roster/shift-roster.ts";

/**
 * Rotating roster cycle authoring (HRT-279, decision 3) plus the real,
 * reachable UI caller for app.generate_roster_schedule_assignments (decision
 * 8) -- without this, batch schedule generation would only be callable at
 * the database-admin level (taxonomy C-20).
 */
export default async function RosterCyclesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let cycles: RosterCycleDetail[] = [];
  let shiftTemplates: Awaited<ReturnType<typeof listShiftTemplates>> = [];
  try {
    const [cycleRows, templates] = await Promise.all([listRosterCycles(supabase, access.tenant.id, access.authUserId), listShiftTemplates(supabase, access.tenant.id, access.authUserId)]);
    shiftTemplates = templates;
    const details = await Promise.all(cycleRows.map((c) => getRosterCycleDetail(supabase, c.id, access.authUserId)));
    cycles = details.filter((d): d is RosterCycleDetail => d !== null);
  } catch (error) {
    if (!(error instanceof ShiftRosterQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading roster cycles. Please try again." />;
  }

  return (
    <RosterCyclePanel
      cycles={cycles}
      shiftTemplates={shiftTemplates.filter((t) => t.publishedVersionId)}
      createRosterCycleAction={createRosterCycleAction.bind(null, tenantSlug)}
      setRosterCycleSlotAction={(rosterCycleId: string) => setRosterCycleSlotAction.bind(null, tenantSlug, rosterCycleId)}
      publishRosterCycleAction={(rosterCycleId: string, expectedVersion: number) => publishRosterCycleAction.bind(null, tenantSlug, rosterCycleId, expectedVersion)}
      generateRosterScheduleAssignmentsAction={(rosterCycleId: string) => generateRosterScheduleAssignmentsAction.bind(null, tenantSlug, rosterCycleId)}
    />
  );
}
