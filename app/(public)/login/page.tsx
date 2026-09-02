"use client";

import { useActionState } from "react";
import { Button } from "../../../components/ui/button.tsx";
import { Input } from "../../../components/forms/input.tsx";
import { PasswordInput } from "../../../components/forms/password-input.tsx";
import { FormField } from "../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../components/forms/validation-message.tsx";
import { signInAction, type SignInFormState } from "./actions.ts";

const INITIAL_STATE: SignInFormState = { error: null };

export default function LoginPage() {
  const [state, formAction, pending] = useActionState(signInAction, INITIAL_STATE);

  // ISS-2026-242: sign-in returns one generic credential error covering all three fields (it
  // deliberately never says which one was wrong), so every field points at that shared message.
  const describedBy = state.error ? "login-error" : undefined;

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 px-4">
      <h1 className="text-2xl font-semibold text-neutral-900">Sign in to CargoGrid</h1>

      <form action={formAction} className="flex flex-col gap-4" noValidate>
        <FormField
          id="tenantSlug"
          label={
            <>
              Organization <span className="font-normal text-neutral-500">(leave blank for CargoGrid staff)</span>
            </>
          }
        >
          <Input id="tenantSlug" name="tenantSlug" type="text" autoComplete="organization" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>

        <FormField id="email" label="Email">
          <Input id="email" name="email" type="email" required autoComplete="email" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>

        <FormField id="password" label="Password">
          <PasswordInput id="password" name="password" required autoComplete="current-password" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>

        {state.error ? <ValidationMessage id="login-error">{state.error}</ValidationMessage> : null}

        <Button type="submit" loading={pending} loadingLabel="Signing in…">
          Sign in
        </Button>
      </form>
    </main>
  );
}
