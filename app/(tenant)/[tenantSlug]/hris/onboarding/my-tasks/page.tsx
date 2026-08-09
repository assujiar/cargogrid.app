import { notFound } from "next/navigation";
import Link from "next/link";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listMyOnboardingTasks, OnboardingQueryError } from "../../../../../../server/queries/onboarding.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";

/**
 * Task-owner self-service (HRT-277, section 15/26) -- an employee/manager/IT/
 * Finance/Operations task owner's own assigned onboarding/offboarding tasks,
 * identity-match-gated (app.list_my_onboarding_tasks), never requiring HRS:View.
 */
export default async function MyOnboardingTasksPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let tasks: Awaited<ReturnType<typeof listMyOnboardingTasks>> = [];
  try {
    tasks = await listMyOnboardingTasks(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    if (!(error instanceof OnboardingQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your assigned tasks. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">My assigned onboarding/offboarding tasks</h1>
      {tasks.length === 0 ? (
        <EmptyState title="No assigned tasks" description="You have no not-yet-completed onboarding/offboarding tasks assigned to you." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="p-2">Task</th>
                <th className="p-2">Type</th>
                <th className="p-2">Due</th>
                <th className="p-2">Status</th>
                <th className="p-2">Case</th>
              </tr>
            </thead>
            <tbody>
              {tasks.map((task) => (
                <tr key={task.id} className="border-t border-neutral-100">
                  <td className="p-2">{task.title}</td>
                  <td className="p-2 text-xs">
                    {task.taskType.replace(/_/g, " ")}
                    {task.handoffCategory ? ` — ${task.handoffCategory}` : ""}
                  </td>
                  <td className="p-2 text-xs">{task.dueAt ? new Date(task.dueAt).toLocaleDateString() : "—"}</td>
                  <td className="p-2">
                    <div className="flex items-center gap-2">
                      {task.isOverdue ? <StatusBadge tone="danger" label="overdue" /> : null}
                      <StatusBadge tone={task.status === "blocked" ? "warning" : "neutral"} label={task.status.replace(/_/g, " ")} />
                    </div>
                  </td>
                  <td className="p-2">
                    <Link href={`/${tenantSlug}/hris/onboarding/${task.caseId}`} className="text-primary underline">
                      Open case
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
