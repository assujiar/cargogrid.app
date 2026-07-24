"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { publishSalesPlanAction, archiveSalesPlanAction, createSalesTargetAction } from "../actions.ts";
import { SALES_TARGET_METRIC_TYPES, type SalesTargetMetricType } from "../../../../../../server/contracts/pipeline/pipeline.ts";

/** Publish/archive/add-target action panel (COM-146) -- mirrors COM-143/144's own `*-actions-panel.tsx` pattern (bound Server Actions called directly via `useTransition`, not `useActionState`, since each takes explicit args rather than `FormData`). */
export function PlanActionsPanel({
  tenantSlug,
  planId,
  recordVersion,
  status,
}: {
  tenantSlug: string;
  planId: string;
  recordVersion: number;
  status: string;
}) {
  const [supersedesPlanId, setSupersedesPlanId] = useState("");
  const [metricType, setMetricType] = useState<SalesTargetMetricType>(SALES_TARGET_METRIC_TYPES[0]);
  const [orgUnitId, setOrgUnitId] = useState("");
  const [targetValue, setTargetValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const canPublish = status === "draft";
  const canArchive = status !== "archived";
  const canAddTarget = status === "draft";

  return (
    <div className="flex flex-col gap-4 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Plan actions</h2>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <div className="flex flex-col gap-1">
        <label htmlFor="supersedes-plan-id" className="text-sm font-medium text-neutral-700">
          Supersedes plan ID <span className="font-normal text-neutral-500">(optional -- archives that published plan on publish)</span>
        </label>
        <input
          id="supersedes-plan-id"
          type="text"
          value={supersedesPlanId}
          onChange={(event) => setSupersedesPlanId(event.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <Button
        type="button"
        disabled={!canPublish}
        loading={pending}
        loadingLabel="Publishing…"
        onClick={() =>
          startTransition(async () => {
            const result = await publishSalesPlanAction(tenantSlug, planId, recordVersion, supersedesPlanId.trim() || null);
            setError(result.error);
          })
        }
      >
        Publish
      </Button>

      <Button
        type="button"
        variant="destructive"
        disabled={!canArchive}
        loading={pending}
        loadingLabel="Archiving…"
        onClick={() =>
          startTransition(async () => {
            const result = await archiveSalesPlanAction(tenantSlug, planId, recordVersion);
            setError(result.error);
          })
        }
      >
        Archive
      </Button>

      <hr className="border-neutral-200" />

      <h3 className="text-sm font-semibold text-neutral-900">Add target</h3>
      <p className="text-xs text-neutral-500">Targets can only be added while the plan is draft.</p>

      <div className="flex flex-col gap-1">
        <label htmlFor="metric-type" className="text-sm font-medium text-neutral-700">
          Metric
        </label>
        <select
          id="metric-type"
          value={metricType}
          onChange={(event) => setMetricType(event.target.value as SalesTargetMetricType)}
          disabled={!canAddTarget}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        >
          {SALES_TARGET_METRIC_TYPES.map((metric) => (
            <option key={metric} value={metric}>
              {metric.replace(/_/g, " ")}
            </option>
          ))}
        </select>
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="target-org-unit-id" className="text-sm font-medium text-neutral-700">
          Organization unit ID <span className="font-normal text-neutral-500">(optional -- defaults to the plan&apos;s own scope)</span>
        </label>
        <input
          id="target-org-unit-id"
          type="text"
          value={orgUnitId}
          onChange={(event) => setOrgUnitId(event.target.value)}
          disabled={!canAddTarget}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="target-value" className="text-sm font-medium text-neutral-700">
          Target value
        </label>
        <input
          id="target-value"
          type="number"
          min={0}
          value={targetValue}
          onChange={(event) => setTargetValue(event.target.value)}
          disabled={!canAddTarget}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>

      <Button
        type="button"
        disabled={!canAddTarget || targetValue.trim() === ""}
        loading={pending}
        loadingLabel="Adding…"
        onClick={() =>
          startTransition(async () => {
            const result = await createSalesTargetAction(tenantSlug, planId, metricType, orgUnitId.trim() || null, Number(targetValue));
            setError(result.error);
            if (!result.error) {
              setTargetValue("");
            }
          })
        }
      >
        Add target
      </Button>
    </div>
  );
}
