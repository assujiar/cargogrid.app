"use client";

import { useActionState } from "react";
import { Button } from "../../../components/ui/button.tsx";
import { signInAction, type SignInFormState } from "./actions.ts";

const INITIAL_STATE: SignInFormState = { error: null };

export default function LoginPage() {
  const [state, formAction, pending] = useActionState(signInAction, INITIAL_STATE);

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center gap-6 px-4">
      <h1 className="text-2xl font-semibold text-neutral-900">Sign in to CargoGrid</h1>

      <form action={formAction} className="flex flex-col gap-4" noValidate>
        <div className="flex flex-col gap-1">
          <label htmlFor="tenantSlug" className="text-sm font-medium text-neutral-700">
            Organization <span className="font-normal text-neutral-500">(leave blank for CargoGrid staff)</span>
          </label>
          <input
            id="tenantSlug"
            name="tenantSlug"
            type="text"
            autoComplete="organization"
            className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="email" className="text-sm font-medium text-neutral-700">
            Email
          </label>
          <input id="email" name="email" type="email" required autoComplete="email" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="password" className="text-sm font-medium text-neutral-700">
            Password
          </label>
          <input
            id="password"
            name="password"
            type="password"
            required
            autoComplete="current-password"
            className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
          />
        </div>

        {state.error ? (
          <p role="alert" className="text-sm text-danger">
            {state.error}
          </p>
        ) : null}

        <Button type="submit" loading={pending} loadingLabel="Signing in…">
          Sign in
        </Button>
      </form>
    </main>
  );
}
