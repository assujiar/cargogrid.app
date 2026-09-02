"use client";

/**
 * User menu primitive (`docs/design-system/02_COMPONENTS.md` "User menu") --
 * account/session actions, top-bar. Composed from `Avatar` + `DropdownMenu`.
 *
 * `ISS-2026-246` adopted it into all three real portal shells (Tenant Admin, Commercial,
 * Supreme) via `components/layout/account-menu.tsx`. Doing so exposed one latent defect
 * that only mattered once the component was on a real screen: the trigger was sized by
 * its `Avatar` alone (`h-8 w-8`, 32px), below the 44px touch-target floor
 * `docs/standards/DESIGN_SYSTEM.md` sets and `ISS-2026-247`/`ISS-2026-248` enforce. The
 * button now meets the floor while the avatar keeps its own 32px visual size --
 * `scripts/ui/check-interaction-primitives.ts` reads only an explicit `h-*` on the
 * interactive tag, so this was invisible to that gate, not exempt from the standard.
 */

import { Avatar } from "./avatar.tsx";
import { DropdownMenu, type DropdownMenuItem } from "./dropdown-menu.tsx";

export interface UserMenuProps {
  readonly name: string;
  readonly items: readonly DropdownMenuItem[];
}

export function UserMenu({ name, items }: UserMenuProps) {
  return (
    <DropdownMenu
      align="end"
      items={items}
      trigger={
        <button
          type="button"
          aria-label={`${name} account menu`}
          className="inline-flex h-11 w-11 items-center justify-center rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          <Avatar name={name} />
        </button>
      }
    />
  );
}
