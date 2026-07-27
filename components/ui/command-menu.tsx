"use client";

/**
 * Command menu primitive (`docs/design-system/02_COMPONENTS.md` "Command palette") --
 * keyboard-first global action/search launcher (Cmd/Ctrl+K). Built on Radix `Dialog`
 * (focus trap, Escape-to-close) plus a plain filtered list -- not the `cmdk` package
 * (not a dependency of this project; adding one for a single component was judged out
 * of this checkpoint's scope, matching the "no new library for one primitive" caution
 * `docs/design-system/07_GAP_ANALYSIS_AND_ROADMAP.md` already applied to charts).
 */

import { Dialog as RadixDialog } from "radix-ui";
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";

export interface CommandMenuItem {
  readonly label: string;
  readonly group?: string;
  readonly href?: string;
  readonly onSelect?: () => void;
}

export function CommandMenu({ items }: { readonly items: readonly CommandMenuItem[] }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");

  useEffect(() => {
    function handleKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setOpen((current) => !current);
      }
    }
    document.addEventListener("keydown", handleKeyDown);
    return () => document.removeEventListener("keydown", handleKeyDown);
  }, []);

  const filtered = useMemo(
    () => items.filter((item) => item.label.toLowerCase().includes(query.toLowerCase())),
    [items, query],
  );

  return (
    <RadixDialog.Root open={open} onOpenChange={setOpen}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="fixed inset-0 z-40 bg-neutral-900/40" />
        <RadixDialog.Content className="fixed left-1/2 top-24 z-50 w-full max-w-lg -translate-x-1/2 rounded-md border border-neutral-200 bg-surface shadow-lg focus:outline-none">
          <RadixDialog.Title className="sr-only">Command menu</RadixDialog.Title>
          <input
            autoFocus
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search actions and pages… (⌘K)"
            className="w-full border-b border-neutral-200 px-4 py-3 text-sm text-text-primary focus:outline-none"
          />
          <ul role="listbox" className="max-h-80 overflow-auto p-1">
            {filtered.length === 0 ? (
              <li className="px-3 py-2 text-sm text-text-secondary">No results.</li>
            ) : (
              filtered.map((item) =>
                item.href ? (
                  <li key={item.label}>
                    <Link
                      href={item.href}
                      onClick={() => setOpen(false)}
                      className="block rounded px-3 py-2 text-sm text-text-primary hover:bg-neutral-100"
                    >
                      {item.label}
                    </Link>
                  </li>
                ) : (
                  <li key={item.label}>
                    <button
                      type="button"
                      onClick={() => {
                        item.onSelect?.();
                        setOpen(false);
                      }}
                      className="block w-full rounded px-3 py-2 text-left text-sm text-text-primary hover:bg-neutral-100"
                    >
                      {item.label}
                    </button>
                  </li>
                ),
              )
            )}
          </ul>
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  );
}
