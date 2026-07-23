"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import {
  updateOpportunityRequirementsAction,
  updateOpportunityValueAction,
  transitionOpportunityStageAction,
  cloneOpportunityAction,
} from "../actions.ts";
import { OPPORTUNITY_STAGES, type OpportunityStage, type OpportunityRequirements } from "../../../../../../server/contracts/opportunity/opportunity.ts";

/** Requirements/value/stage/clone action panel (COM-147) -- mirrors COM-143/144/146's own `*-actions-panel.tsx` pattern (bound Server Actions called directly via `useTransition`). */
export function OpportunityActionsPanel({
  tenantSlug,
  opportunityId,
  recordVersion,
  stage,
  requirements,
  showValueForm,
}: {
  tenantSlug: string;
  opportunityId: string;
  recordVersion: number;
  stage: OpportunityStage;
  requirements: OpportunityRequirements;
  showValueForm: boolean;
}) {
  const [serviceType, setServiceType] = useState(requirements.serviceType ?? "");
  const [cargoDescription, setCargoDescription] = useState(requirements.cargoDescription ?? "");
  const [origin, setOrigin] = useState(requirements.origin ?? "");
  const [destination, setDestination] = useState(requirements.destination ?? "");
  const [targetReadyDate, setTargetReadyDate] = useState(requirements.targetReadyDate ?? "");
  const [nextAction, setNextAction] = useState("");
  const [valueAmount, setValueAmount] = useState("");
  const [valueCurrency, setValueCurrency] = useState("");
  const [newStage, setNewStage] = useState<OpportunityStage>(stage);
  const [closeReason, setCloseReason] = useState("");
  const [cloneName, setCloneName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const isClosed = stage === "won" || stage === "lost";

  return (
    <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Requirements</h3>
        <input placeholder="Service type" value={serviceType} onChange={(e) => setServiceType(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input placeholder="Cargo description" value={cargoDescription} onChange={(e) => setCargoDescription(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input placeholder="Origin" value={origin} onChange={(e) => setOrigin(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input placeholder="Destination" value={destination} onChange={(e) => setDestination(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="date" placeholder="Target ready date" value={targetReadyDate} onChange={(e) => setTargetReadyDate(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input placeholder="Next action" value={nextAction} onChange={(e) => setNextAction(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <Button
          type="button"
          variant="secondary"
          disabled={isClosed}
          loading={pending}
          loadingLabel="Saving…"
          onClick={() =>
            startTransition(async () => {
              const result = await updateOpportunityRequirementsAction(
                tenantSlug,
                opportunityId,
                recordVersion,
                { serviceType, cargoDescription, origin, destination, targetReadyDate },
                nextAction,
              );
              setError(result.error);
            })
          }
        >
          Save requirements
        </Button>
      </div>

      {showValueForm ? (
        <div className="flex flex-col gap-2">
          <h3 className="text-sm font-medium text-neutral-900">Value</h3>
          <div className="flex gap-2">
            <input type="number" min={0} placeholder="Amount" value={valueAmount} onChange={(e) => setValueAmount(e.target.value)} disabled={isClosed} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
            <input placeholder="Currency (e.g. IDR)" value={valueCurrency} onChange={(e) => setValueCurrency(e.target.value.toUpperCase())} disabled={isClosed} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>
          <Button
            type="button"
            variant="secondary"
            disabled={isClosed || !valueAmount.trim() || !/^[A-Z]{3}$/.test(valueCurrency)}
            loading={pending}
            loadingLabel="Saving…"
            onClick={() =>
              startTransition(async () => {
                const result = await updateOpportunityValueAction(tenantSlug, opportunityId, recordVersion, Number(valueAmount), valueCurrency);
                setError(result.error);
              })
            }
          >
            Set value
          </Button>
        </div>
      ) : null}

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Stage</h3>
        <select value={newStage} onChange={(e) => setNewStage(e.target.value as OpportunityStage)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
          {OPPORTUNITY_STAGES.map((s) => (
            <option key={s} value={s}>
              {s.replace(/_/g, " ")}
            </option>
          ))}
        </select>
        {newStage === "won" || newStage === "lost" ? (
          <input placeholder="Close reason (required)" value={closeReason} onChange={(e) => setCloseReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        ) : null}
        <Button
          type="button"
          disabled={isClosed || ((newStage === "won" || newStage === "lost") && !closeReason.trim())}
          loading={pending}
          loadingLabel="Updating…"
          onClick={() =>
            startTransition(async () => {
              const result = await transitionOpportunityStageAction(tenantSlug, opportunityId, recordVersion, newStage, closeReason.trim() || null);
              setError(result.error);
            })
          }
        >
          Update stage
        </Button>
      </div>

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Clone</h3>
        <input placeholder="New opportunity name (optional)" value={cloneName} onChange={(e) => setCloneName(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <Button
          type="button"
          variant="secondary"
          loading={pending}
          loadingLabel="Cloning…"
          onClick={() =>
            startTransition(async () => {
              const result = await cloneOpportunityAction(tenantSlug, opportunityId, cloneName.trim());
              setError(result.error);
            })
          }
        >
          Clone opportunity
        </Button>
      </div>
    </div>
  );
}
