"use client";

/**
 * User menu primitive (`docs/design-system/02_COMPONENTS.md` "User menu") --
 * account/session actions, top-bar. No top-bar user menu exists in any real layout
 * yet (`supreme/layout.tsx`/`admin/layout.tsx` both render a static 2-link header) --
 * built now as a real, composable primitive for whichever layout adopts it first,
 * composed from `Avatar` + `DropdownMenu`.
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
        <button type="button" aria-label={`${name} account menu`} className="rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
          <Avatar name={name} />
        </button>
      }
    />
  );
}
