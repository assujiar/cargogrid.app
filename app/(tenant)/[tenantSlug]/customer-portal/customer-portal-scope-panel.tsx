"use client";

import { useState } from "react";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import type { CustomerPortalScopeContextRow } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";

const ROLE_LABEL: Record<string, string> = {
  account_admin: "Account admin",
  member: "Member",
};

function roleLabel(role: string | null): string {
  return role ? (ROLE_LABEL[role] ?? role) : "Legacy access";
}

function roleTone(role: string | null): StatusTone {
  if (role === "account_admin") return "info";
  if (role === "member") return "neutral";
  return "neutral";
}

/**
 * Account/site switcher (source prompt §"UI": "an account/site switcher if
 * more than one is active"). Every row here is already scoped server-side by
 * app.get_customer_portal_scope_context -- this panel never applies its own
 * additional filtering, and the selection below is presentational only
 * (client-side highlight, no navigation/persistence) since the full
 * dashboard/session-context wiring this selection would drive is Prompt
 * 301's own job, not this checkpoint's.
 */
export function CustomerPortalScopePanel({ memberships }: { memberships: readonly CustomerPortalScopeContextRow[] }) {
  const initialSelectedId = memberships.find((m) => m.isPrimary)?.accountId ?? memberships[0]?.accountId ?? null;
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(initialSelectedId);
  const selected = memberships.find((m) => m.accountId === selectedAccountId) ?? memberships[0] ?? null;

  return (
    <div className="flex flex-col gap-4">
      {memberships.length > 1 ? (
        <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <label htmlFor="customer-portal-account-switcher" className="text-xs font-medium text-neutral-500">
            Viewing as
          </label>
          <select
            id="customer-portal-account-switcher"
            value={selectedAccountId ?? ""}
            onChange={(event) => setSelectedAccountId(event.target.value)}
            className="w-full max-w-sm rounded border border-neutral-300 p-2 text-sm"
          >
            {memberships.map((m) => (
              <option key={m.accountId} value={m.accountId}>
                {m.accountName}
                {m.isPrimary ? " (primary)" : ""}
              </option>
            ))}
          </select>
        </div>
      ) : null}

      <div className="overflow-x-auto rounded-md border border-neutral-200">
        <table className="w-full border-collapse">
          <thead>
            <tr className="text-left text-xs font-medium text-neutral-500">
              <th className="p-2">Account</th>
              <th className="p-2">Role</th>
              <th className="p-2">Status</th>
              <th className="p-2">Primary</th>
            </tr>
          </thead>
          <tbody>
            {memberships.map((m) => (
              <tr key={m.accountId} className={`border-t border-neutral-100 ${m.accountId === selected?.accountId ? "bg-primary/5" : ""}`}>
                <td className="p-2 text-sm font-medium text-neutral-900">{m.accountName}</td>
                <td className="p-2 text-sm">
                  <StatusBadge tone={roleTone(m.role)} label={roleLabel(m.role)} />
                </td>
                <td className="p-2 text-sm">
                  <StatusBadge tone="success" label="Active" />
                </td>
                <td className="p-2 text-xs text-neutral-500">{m.isPrimary ? "Yes" : ""}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
