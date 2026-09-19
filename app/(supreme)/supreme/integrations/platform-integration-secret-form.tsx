"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { PasswordInput } from "../../../../components/forms/password-input.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { setPlatformIntegrationSecretAction, type PlatformIntegrationSecretActionState } from "./actions.ts";

const INITIAL_STATE: PlatformIntegrationSecretActionState = { error: null };

export function PlatformIntegrationSecretForm() {
  const [state, formAction, pending] = useActionState(setPlatformIntegrationSecretAction, INITIAL_STATE);
  // ISS-2026-242: one error covers the whole save call, so every field points at it.
  const describedBy = state.error ? "platform-integration-secret-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" key={state.error ? "error" : "ok"}>
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Add or rotate a platform API key</h2>
        <p className="text-xs text-neutral-500">
          Saving an existing key name replaces its value (rotation) rather than creating a second entry. The value is encrypted at rest and never shown again once saved.
        </p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <FormField id="pis-secret-key" label="Key name">
          <Input
            id="pis-secret-key"
            name="secretKey"
            placeholder="virustotal_api_key"
            pattern="[a-z][a-z0-9_]{2,63}"
            required
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id="pis-description" label="Description (optional)">
          <Input id="pis-description" name="description" placeholder="VirusTotal free-tier API key" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id="pis-secret-value" label="Secret value">
        <PasswordInput id="pis-secret-value" name="secretValue" autoComplete="off" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="flex items-center gap-3">
        <Button type="submit" loading={pending} loadingLabel="Saving…">
          Save key
        </Button>
        {state.error ? <ValidationMessage id="platform-integration-secret-error">{state.error}</ValidationMessage> : null}
      </div>
    </form>
  );
}
