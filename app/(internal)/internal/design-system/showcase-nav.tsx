"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useMemo, useState } from "react";
import { COMPONENT_REGISTRY, CATEGORY_LABELS } from "../../../../lib/design-system/component-registry.ts";
import { slugifyComponentName } from "./slugify.ts";
import { ThemeToggle } from "./theme-toggle.tsx";
import { ViewportControl } from "./viewport-frame.tsx";

const NAV_GROUPS: readonly { readonly href: string; readonly label: string }[] = [
  { href: "/internal/design-system/foundations", label: "Foundations" },
  { href: "/internal/design-system/components", label: "Components" },
  { href: "/internal/design-system/tables", label: "Tables" },
  { href: "/internal/design-system/domain-components", label: "Domain Components" },
  { href: "/internal/design-system/domain-examples", label: "Business Examples" },
  { href: "/internal/design-system/patterns", label: "Patterns" },
  { href: "/internal/design-system/duplicates", label: "Duplicates & migration map" },
  { href: "/internal/design-system/accessibility", label: "Accessibility" },
  { href: "/internal/design-system/responsive-preview", label: "Responsive preview" },
];

export function ShowcaseNav() {
  const pathname = usePathname();
  const [query, setQuery] = useState("");

  const matches = useMemo(() => {
    const trimmed = query.trim().toLowerCase();
    if (trimmed.length === 0) {
      return [];
    }
    return COMPONENT_REGISTRY.filter(
      (entry) => entry.name.toLowerCase().includes(trimmed) || entry.purpose.toLowerCase().includes(trimmed),
    ).slice(0, 8);
  }, [query]);

  return (
    <nav aria-label="Design System Showcase" className="flex w-full flex-shrink-0 flex-col gap-4 lg:w-64">
      <div className="flex flex-col gap-1">
        <label htmlFor="ds-search" className="text-xs font-medium text-text-secondary">
          Search components
        </label>
        <input
          id="ds-search"
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="e.g. Table, Input, Dialog…"
          className="rounded-md border border-border-default bg-surface px-3 py-1.5 text-sm text-text-primary"
        />
        {matches.length > 0 ? (
          <ul className="flex flex-col gap-0.5 rounded-md border border-border-default bg-surface p-1 text-sm">
            {matches.map((entry) => (
              <li key={entry.name}>
                <Link
                  href={`/internal/design-system/components#${slugifyComponentName(entry.name)}`}
                  className="flex items-center justify-between gap-2 rounded px-2 py-1 hover:bg-neutral-100"
                >
                  <span>{entry.name}</span>
                  <span className="text-xs text-text-secondary">{entry.status}</span>
                </Link>
              </li>
            ))}
          </ul>
        ) : null}
      </div>

      <ul className="flex flex-col gap-0.5 text-sm">
        {NAV_GROUPS.map((group) => {
          const active = pathname === group.href;
          return (
            <li key={group.href}>
              <Link
                href={group.href}
                aria-current={active ? "page" : undefined}
                className={`block rounded-md px-3 py-1.5 ${
                  active ? "bg-primary text-neutral-50" : "text-text-primary hover:bg-neutral-100"
                }`}
              >
                {group.label}
              </Link>
            </li>
          );
        })}
      </ul>

      <div className="flex flex-col gap-2 border-t border-border-default pt-4">
        <ThemeToggle />
        <ViewportControl />
      </div>

      <p className="text-xs text-text-secondary">
        {COMPONENT_REGISTRY.filter((entry) => entry.status === "IMPLEMENTED").length} implemented ·{" "}
        {COMPONENT_REGISTRY.length} catalogued across {Object.keys(CATEGORY_LABELS).length} categories.
      </p>
    </nav>
  );
}
