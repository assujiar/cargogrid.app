"use client";

/**
 * The signed-in principal's account menu in a portal top bar (`ISS-2026-246`).
 *
 * `components/ui/user-menu.tsx` documented itself as built "for whichever layout adopts it
 * first" and then had no reference anywhere in the repository. This is that adoption: the
 * three real shells -- Tenant Admin, Commercial, Supreme -- all render a top bar with the
 * tenant/portal name on the left and module navigation on the right, and none of them
 * showed who was signed in or offered any way to leave. That is a gap in the product, not
 * evidence the primitive was unnecessary.
 *
 * This component exists (rather than the layouts calling `UserMenu` directly) because
 * `UserMenu` takes `onSelect` callbacks -- client handlers -- while all three shells are
 * async Server Components. It is the client boundary, and nothing more: the label is
 * resolved server-side and passed in, so no identity lookup happens in the browser.
 *
 * Sign out is the only item. It is the one account action this repository actually has a
 * server implementation for; a "Profile"/"Settings" entry pointing at a route that does not
 * exist for every principal (`/{tenant}/hris/my/profile` requires an HRIS employee record,
 * which a Supreme Admin or a non-HRIS Tenant Admin does not have) would be exactly the
 * dead placeholder `AGENTS.md` §"File and search discipline" forbids.
 */

import { useTransition } from "react";
import { UserMenu } from "../ui/user-menu.tsx";
import { signOutAction } from "../../app/(public)/login/actions.ts";

export function AccountMenu({ name }: { readonly name: string }) {
  const [pending, startTransition] = useTransition();

  return (
    <UserMenu
      name={name}
      items={[
        {
          label: pending ? "Signing out…" : "Sign out",
          disabled: pending,
          onSelect: () => {
            // `signOutAction` redirects, so this transition ends in a navigation rather
            // than a state update -- `startTransition` keeps that navigation from
            // blocking the menu's own close animation.
            startTransition(() => {
              void signOutAction();
            });
          },
        },
      ]}
    />
  );
}
