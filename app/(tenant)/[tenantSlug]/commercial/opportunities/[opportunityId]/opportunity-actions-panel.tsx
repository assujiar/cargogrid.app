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
import { Input } from "../../../../../../components/forms/input.tsx";
import { DateInput } from "../../../../../../components/forms/date-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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

  // Four independent actions (requirements / value / stage / clone) share this one
  // `error` slot, so no field can honestly claim `aria-invalid`; every control instead
  // points at the shared message (ISS-2026-242's own documented multi-action case).
  const describedBy = error ? "opportunity-actions-error" : undefined;

  const isClosed = stage === "won" || stage === "lost";

  return (
    <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? <ValidationMessage id="opportunity-actions-error">{error}</ValidationMessage> : null}

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Requirements</h3>
        <FormField id="opportunity-service-type" label={<span className="sr-only">Service type</span>}>
          <Input id="opportunity-service-type" placeholder="Service type" value={serviceType} onChange={(e) => setServiceType(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
        <FormField id="opportunity-cargo-description" label={<span className="sr-only">Cargo description</span>}>
          <Input id="opportunity-cargo-description" placeholder="Cargo description" value={cargoDescription} onChange={(e) => setCargoDescription(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
        <FormField id="opportunity-origin" label={<span className="sr-only">Origin</span>}>
          <Input id="opportunity-origin" placeholder="Origin" value={origin} onChange={(e) => setOrigin(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
        <FormField id="opportunity-destination" label={<span className="sr-only">Destination</span>}>
          <Input id="opportunity-destination" placeholder="Destination" value={destination} onChange={(e) => setDestination(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
        <FormField id="opportunity-target-ready-date" label={<span className="sr-only">Target ready date</span>}>
          <DateInput id="opportunity-target-ready-date" placeholder="Target ready date" value={targetReadyDate} onChange={(e) => setTargetReadyDate(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
        <FormField id="opportunity-next-action" label={<span className="sr-only">Next action</span>}>
          <Input id="opportunity-next-action" placeholder="Next action" value={nextAction} onChange={(e) => setNextAction(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
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
            <div className="w-32">
              <FormField id="opportunity-value-amount" label={<span className="sr-only">Amount</span>}>
                <Input type="number" inputMode="decimal" id="opportunity-value-amount" min={0} placeholder="Amount" value={valueAmount} onChange={(e) => setValueAmount(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
              </FormField>
            </div>
            <div className="w-32">
              <FormField id="opportunity-value-currency" label={<span className="sr-only">Currency</span>}>
                <Input id="opportunity-value-currency" placeholder="Currency (e.g. IDR)" value={valueCurrency} onChange={(e) => setValueCurrency(e.target.value.toUpperCase())} disabled={isClosed} aria-describedby={describedBy} />
              </FormField>
            </div>
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
        <FormField id="opportunity-stage" label={<span className="sr-only">Stage</span>}>
          <Select id="opportunity-stage" value={newStage} onChange={(e) => setNewStage(e.target.value as OpportunityStage)} disabled={isClosed} aria-describedby={describedBy}>
            {OPPORTUNITY_STAGES.map((s) => (
              <option key={s} value={s}>
                {s.replace(/_/g, " ")}
              </option>
            ))}
          </Select>
        </FormField>
        {newStage === "won" || newStage === "lost" ? (
          <FormField id="opportunity-close-reason" label={<span className="sr-only">Close reason (required)</span>}>
            <Input id="opportunity-close-reason" placeholder="Close reason (required)" value={closeReason} onChange={(e) => setCloseReason(e.target.value)} aria-describedby={describedBy} />
          </FormField>
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
        <FormField id="opportunity-clone-name" label={<span className="sr-only">New opportunity name (optional)</span>}>
          <Input id="opportunity-clone-name" placeholder="New opportunity name (optional)" value={cloneName} onChange={(e) => setCloneName(e.target.value)} aria-describedby={describedBy} />
        </FormField>
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
