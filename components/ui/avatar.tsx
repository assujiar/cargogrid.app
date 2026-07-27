"use client";

/**
 * Avatar primitive (`docs/design-system/02_COMPONENTS.md` "Avatar") -- user/entity
 * image or initials. Built on Radix `Avatar`, which needs a client boundary for its
 * own image-load-failure detection (falls back to initials automatically if `src`
 * 404s or is omitted).
 */

import { Avatar as RadixAvatar } from "radix-ui";

export interface AvatarProps {
  readonly name: string;
  readonly imageUrl?: string;
}

function initialsOf(name: string): string {
  const parts = name.trim().split(/\s+/);
  const first = parts[0]?.[0] ?? "";
  const last = parts.length > 1 ? (parts[parts.length - 1]?.[0] ?? "") : "";
  return (first + last).toUpperCase();
}

export function Avatar({ name, imageUrl }: AvatarProps) {
  return (
    <RadixAvatar.Root className="inline-flex h-8 w-8 items-center justify-center overflow-hidden rounded-full bg-neutral-200 text-xs font-medium text-neutral-700">
      {imageUrl ? <RadixAvatar.Image src={imageUrl} alt={name} className="h-full w-full object-cover" /> : null}
      <RadixAvatar.Fallback delayMs={imageUrl ? 300 : 0}>{initialsOf(name)}</RadixAvatar.Fallback>
    </RadixAvatar.Root>
  );
}
