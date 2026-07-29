"use client";

/**
 * Finance Configuration client forms (FIN-191, CG-S9-FIN-002). Same
 * `useActionState`/bound-action split every prior capability's own create-form
 * already uses (e.g. `commercial/margin-rules/create-margin-rule-form.tsx`).
 * Five small, single-purpose forms rather than one monolithic form -- each maps
 * to exactly one server action / one Finance Configuration lifecycle step
 * (draft -> set items -> publish, or discard / rollback).
 */

import { useActionState, useEffect, useRef, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceConfigFormState } from "./actions.ts";

const INITIAL_STATE: FinanceConfigFormState = { error: null };

type BoundAction = (prevState: FinanceConfigFormState, formData: FormData) => Promise<FinanceConfigFormState>;

export function CreateFinanceConfigDraftForm({ action, disabled }: { action: BoundAction; disabled?: boolean }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <p className="text-xs text-text-secondary">Requires FIN:Edit and Tenant Admin/Supreme authority to draft; FIN:Approve and Tenant Admin/Supreme authority to publish.</p>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Creating…" disabled={disabled} className="w-fit">
        Start a new draft
      </Button>
    </form>
  );
}

/**
 * Unsaved-change protection: this form tracks whether the textarea has diverged
 * from the last-saved value and registers a real `beforeunload` handler while
 * dirty -- the browser's own native "leave site? changes you made may not be
 * saved" prompt, the same real (not simulated) guard `docs/architecture/
 * 09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5 requires. Cleared immediately once the
 * save action completes successfully (state.error === null and value matches
 * what was submitted).
 */
export function FinanceConfigItemsForm({
  action,
  initialItemsJson,
  disabled,
}: {
  action: BoundAction;
  initialItemsJson: string;
  disabled?: boolean;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const [value, setValue] = useState(initialItemsJson);
  const [savedValue, setSavedValue] = useState(initialItemsJson);
  const dirty = value !== savedValue;
  const valueRef = useRef(value);
  const wasPendingRef = useRef(pending);

  useEffect(() => {
    valueRef.current = value;
  }, [value]);

  useEffect(() => {
    if (!dirty) return;
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener("beforeunload", handler);
    return () => window.removeEventListener("beforeunload", handler);
  }, [dirty]);

  // Marks the form clean exactly once, on the pending=true -> pending=false
  // transition of a submit that completed without error -- never on an
  // ordinary keystroke (this effect's own deps exclude `value`; it reads the
  // latest value via `valueRef` instead, the standard "read latest without
  // re-running on every change" ref pattern).
  useEffect(() => {
    if (wasPendingRef.current && !pending && state.error === null) {
      setSavedValue(valueRef.current);
    }
    wasPendingRef.current = pending;
  }, [pending, state.error]);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <label htmlFor="itemsJson" className="text-sm font-medium text-text-primary">
        Items (JSON object, key -&gt; value)
      </label>
      <textarea
        id="itemsJson"
        name="itemsJson"
        rows={10}
        value={value}
        onChange={(event) => setValue(event.target.value)}
        disabled={disabled}
        className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs"
        aria-describedby="itemsJson-hint"
      />
      <p id="itemsJson-hint" className="text-xs text-text-secondary">
        Each key is validated against this class&apos;s own structural rules when you publish (e.g. rounding mode/precision, numbering format tokens). Invalid JSON or an unsafe value is rejected before saving.
      </p>
      {dirty ? <p className="text-xs text-warning">Unsaved changes -- save before publishing or leaving this page.</p> : null}
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" disabled={disabled} className="w-fit">
        Save items
      </Button>
    </form>
  );
}

export function PublishFinanceConfigVersionForm({ action, disabled }: { action: BoundAction; disabled?: boolean }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Publishing…" disabled={disabled} className="w-fit">
        Publish
      </Button>
    </form>
  );
}

export function DiscardFinanceConfigDraftForm({ action, disabled }: { action: BoundAction; disabled?: boolean }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <label htmlFor="discard-reason" className="text-sm font-medium text-text-primary">
        Reason (required)
      </label>
      <input id="discard-reason" name="reason" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Discarding…" disabled={disabled} className="w-fit">
        Discard draft
      </Button>
    </form>
  );
}

export function RollbackFinanceConfigVersionForm({ action, disabled }: { action: BoundAction; disabled?: boolean }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <label htmlFor="rollback-reason" className="text-sm font-medium text-text-primary">
        Reason (required)
      </label>
      <input id="rollback-reason" name="reason" type="text" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rolling back…" disabled={disabled} className="w-fit">
        Roll back to this version
      </Button>
    </form>
  );
}
