"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { CustomerImportActionState } from "./actions.ts";

const INITIAL_STATE: CustomerImportActionState = { error: null };

type BoundAction = (prevState: CustomerImportActionState, formData: FormData) => Promise<CustomerImportActionState>;

export function BootstrapCustomerImportForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Setting up…" className="w-fit">
        Set up customer imports for this organization
      </Button>
    </form>
  );
}

export function UploadCustomerImportSourceForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <FormField id="sourceFile" label="Customer roster CSV file" error={state.error ?? undefined}>
        <input id="sourceFile" type="file" name="sourceFile" accept=".csv,text/csv" required className="text-sm" />
      </FormField>
      <Button type="submit" loading={pending} loadingLabel="Uploading…" className="w-fit">
        Upload and start an import
      </Button>
    </form>
  );
}

export function StageAndValidateCustomerImportRowsForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Processing…" className="w-fit">
        Stage &amp; validate rows
      </Button>
    </form>
  );
}

export function CommitCustomerImportForm({ action, invalidRowCount }: { action: BoundAction; invalidRowCount: number }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      {invalidRowCount > 0 ? <Checkbox id="allowPartial" name="allowPartial" label={`Commit anyway, skipping the ${invalidRowCount} invalid row(s)`} /> : null}
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={invalidRowCount > 0 ? "secondary" : "primary"} loading={pending} loadingLabel="Committing…" className="w-fit">
        Commit this import
      </Button>
    </form>
  );
}
