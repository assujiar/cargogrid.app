/**
 * Account Reentry Panel (COM-161, CG-S7-COM-020). Advisory-only rendering of
 * app.find_existing_accounts_for_lead / app.find_existing_accounts_for_prospect's own
 * candidate list -- never a block, matching the underlying functions' own non-blocking
 * discipline. Renders nothing when there are zero candidates (the common case), so it
 * never adds visual noise to a genuinely new Lead/Prospect.
 */

import { Alert } from "../../../../../components/ui/alert.tsx";
import type { Account } from "../../../../../server/contracts/account/account.ts";

export interface AccountReentryPanelProps {
  readonly tenantSlug: string;
  readonly accounts: readonly Account[];
}

export function AccountReentryPanel({ tenantSlug, accounts }: AccountReentryPanelProps) {
  if (accounts.length === 0) {
    return null;
  }

  return (
    <Alert tone="warning">
      <p className="font-medium">Possible existing customer</p>
      <p className="mt-1">
        {accounts.length === 1 ? "An account with a matching name already exists" : `${accounts.length} accounts with a matching name already exist`} in this
        tenant. Consider working this relationship within the existing account instead of re-entering it as new.
      </p>
      <ul className="mt-2 flex flex-col gap-1">
        {accounts.map((account) => (
          <li key={account.id}>
            <a href={`/${tenantSlug}/commercial/accounts/${account.id}`} className="font-medium underline">
              {account.legalName}
            </a>
            {account.tradeName ? <span className="text-text-secondary"> ({account.tradeName})</span> : null}
          </li>
        ))}
      </ul>
    </Alert>
  );
}
