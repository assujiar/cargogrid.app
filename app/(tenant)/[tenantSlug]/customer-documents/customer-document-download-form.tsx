"use client";

/**
 * Per-row download action (CPL-308, CG-S13-CPL-010). Each document row gets
 * its own tiny form/local state (useActionState) so one row's pending/result
 * state never bleeds into another's, mirroring CustomerEpodPanel's own
 * accessAction pattern (CPL-307) at row granularity rather than page
 * granularity.
 *
 * A non-`clean` document renders no download control at all -- business
 * rule: "Unscanned/quarantined files are never downloadable, previewed,
 * indexed or emailed." The scan status itself is still always shown by the
 * caller (customer-documents-panel.tsx's own StatusBadge, migration design
 * decision 5) -- only the ACTION is withheld here, never the status.
 */

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import type { CustomerDocumentActionState } from "./actions.ts";

const INITIAL_STATE: CustomerDocumentActionState = { error: null, confirmedAt: null };

export function CustomerDocumentDownloadForm({
  downloadable,
  action,
}: {
  downloadable: boolean;
  action: (prevState: CustomerDocumentActionState, formData: FormData) => Promise<CustomerDocumentActionState>;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  if (!downloadable) {
    return <span className="text-xs text-neutral-500">Not available for download.</span>;
  }

  return (
    <form action={formAction} className="flex flex-col gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…">
        Download
      </Button>
      {state.confirmedAt ? <p className="text-xs text-success">Access verified and logged. Live file delivery activates once this environment&apos;s storage delivery layer is provisioned.</p> : null}
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}
