"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { useToastOnSettled } from "../../../../components/ui/toast.tsx";
import type { AnalyticsActionState } from "./actions.ts";

const INITIAL_STATE: AnalyticsActionState = { error: null };

/** Client Component wrapper -- app.refresh_analytics_view is Supreme-only and system-wide; this button is shown to every viewer of this page, the RPC itself is the real enforcement point (mirrors every prior report/dashboard action's convention). */
export function RefreshViewButton({ action }: { action: (prevState: AnalyticsActionState, formData: FormData) => Promise<AnalyticsActionState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  // ISS-2026-246: a refusal was already reported, a success was not -- the button simply stopped
  // saying "Refreshing…" and nothing else on the page changed, because a materialized-view
  // refresh leaves the page's own markup identical. `AnalyticsActionState` carries no success
  // flag and does not need one: a submission that settles with `error === null` succeeded, and
  // `useToastOnSettled` only ever looks at the settle edge, never at first render.
  useToastOnSettled(pending, state.error === null ? { title: "Analytics view refreshed.", tone: "success" } : null);

  return (
    <form action={formAction} className="flex flex-col items-start gap-1" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Refreshing…">
        Refresh now
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
