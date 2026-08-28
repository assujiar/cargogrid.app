"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { TenantDashboardActionState } from "./actions.ts";
import type { TenantDashboard, TenantDashboardStatus } from "../../../../server/contracts/tenant-dashboard/tenant-dashboard.ts";

const INITIAL_STATE: TenantDashboardActionState = { error: null };

const STATUS_TONE: Record<TenantDashboardStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

export function DashboardManagementPanel({
  tenantSlug,
  dashboards,
  createAction,
}: {
  tenantSlug: string;
  dashboards: readonly TenantDashboard[];
  createAction: (prevState: TenantDashboardActionState, formData: FormData) => Promise<TenantDashboardActionState>;
}) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {dashboards.length === 0 ? (
          <EmptyState title="No dashboards yet" description="Create your first dashboard below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[420px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Name</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Updated</th>
              </tr>
            </thead>
            <tbody>
              {dashboards.map((d) => (
                <tr key={d.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/dashboards/${d.id}`} className="text-primary underline">
                      {d.name}
                    </Link>
                  </td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[d.status]} label={d.status} />
                  </td>
                  <td className="py-1">{d.updatedAt}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new dashboard</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1">
            <label htmlFor="name" className="text-xs font-medium text-neutral-600">
              Name
            </label>
            <input id="name" name="name" type="text" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="col-span-full flex flex-col gap-1">
            <label htmlFor="description" className="text-xs font-medium text-neutral-600">
              Description (optional)
            </label>
            <textarea id="description" name="description" rows={2} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Creating…">
              Create dashboard
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
