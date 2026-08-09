"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EMPLOYEE_CHANGE_REQUEST_FIELDS, type EmployeeLifecycleStatus, type EmployeeOwnProfile } from "../../../../../../server/contracts/employee/employee.ts";
import type { MyProfileActionState } from "./actions.ts";

const INITIAL_STATE: MyProfileActionState = { error: null, success: false };

const STATUS_TONE: Record<EmployeeLifecycleStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  approved: "info",
  active: "success",
  on_leave: "warning",
  suspended: "warning",
  terminated: "danger",
  archived: "neutral",
};

const FIELD_LABELS: Record<string, string> = {
  personal_email: "Personal email",
  personal_phone: "Personal phone",
  personal_address_street: "Address: street",
  personal_address_city: "Address: city",
  personal_address_province: "Address: province",
  personal_address_postal_code: "Address: postal code",
  personal_address_country: "Address: country",
};

export function MyProfilePanel({ profile, requestChangeAction }: { profile: EmployeeOwnProfile; requestChangeAction: (prevState: MyProfileActionState, formData: FormData) => Promise<MyProfileActionState> }) {
  const [state, formAction, pending] = useActionState(requestChangeAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">
          {profile.fullName} <span className="text-sm font-normal text-neutral-500">({profile.employeeNumber})</span>
        </h1>
        <StatusBadge tone={STATUS_TONE[profile.lifecycleStatus]} label={profile.lifecycleStatus.replace(/_/g, " ")} />
      </div>

      <dl className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2">
        <div>
          <dt className="text-xs text-neutral-500">Employment type</dt>
          <dd className="text-sm">{profile.employmentType.replace(/_/g, " ")}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Hire date</dt>
          <dd className="text-sm">{profile.hireDate ?? "—"}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Work email</dt>
          <dd className="text-sm">{profile.workEmail ?? "—"}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Position</dt>
          <dd className="text-sm">{profile.positionTitle ?? "—"}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Personal email</dt>
          <dd className="text-sm">{profile.personalEmail ?? "—"}</dd>
        </div>
        <div>
          <dt className="text-xs text-neutral-500">Personal phone</dt>
          <dd className="text-sm">{profile.personalPhone ?? "—"}</dd>
        </div>
        <div className="sm:col-span-2">
          <dt className="text-xs text-neutral-500">Personal address</dt>
          <dd className="text-sm">
            {[profile.personalAddressStreet, profile.personalAddressCity, profile.personalAddressProvince, profile.personalAddressPostalCode, profile.personalAddressCountry].filter(Boolean).join(", ") || "—"}
          </dd>
        </div>
      </dl>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Request a correction</h2>
        <p className="text-xs text-neutral-500">HR reviews and applies every correction request -- you cannot edit these fields directly.</p>
        <form action={formAction} className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
            Field
            <select name="fieldKey" required defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
              <option value="" disabled>
                Select…
              </option>
              {EMPLOYEE_CHANGE_REQUEST_FIELDS.map((f) => (
                <option key={f} value={f}>
                  {FIELD_LABELS[f] ?? f}
                </option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600">
            New value
            <input name="requestedValue" type="text" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </label>
          <label className="flex flex-col gap-1 text-xs font-medium text-neutral-600 sm:col-span-2">
            Reason (optional)
            <input name="reason" type="text" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          </label>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
          ) : null}
          {state.success ? (
            <p role="status" className="col-span-full text-sm text-success">
              Correction request submitted for HR review.
            </p>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Submitting…">
              Submit request
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
