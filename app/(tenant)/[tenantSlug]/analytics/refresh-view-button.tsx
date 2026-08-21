"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import type { AnalyticsActionState } from "./actions.ts";

const INITIAL_STATE: AnalyticsActionState = { error: null };

/** Client Component wrapper -- app.refresh_analytics_view is Supreme-only and system-wide; this button is shown to every viewer of this page, the RPC itself is the real enforcement point (mirrors every prior report/dashboard action's convention). */
export function RefreshViewButton({ action }: { action: (prevState: AnalyticsActionState, formData: FormData) => Promise<AnalyticsActionState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

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
