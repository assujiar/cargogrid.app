"use client";

/** Tabs primitive (`docs/design-system/02_COMPONENTS.md` "Tabs") -- same-page view switch. Built on Radix `Tabs` for correct roving-tabindex keyboard behavior. */

import { Tabs as RadixTabs } from "radix-ui";
import type { ReactNode } from "react";

export interface TabItem {
  readonly value: string;
  readonly label: string;
  readonly content: ReactNode;
}

export interface TabsProps {
  readonly items: readonly TabItem[];
  readonly defaultValue?: string;
  readonly value?: string;
  readonly onValueChange?: (value: string) => void;
  /**
   * Accessible name for the tab list itself (`ISS-2026-246`, first-consumer requirement).
   * A page with more than one tab set -- or one whose tabs are not self-evident from the
   * surrounding heading -- needs this; WCAG 2.2 AA 1.3.1. Added when the employee detail
   * panel became the first real consumer: its hand-rolled `role="tablist"` already carried
   * `aria-label="Employee detail sections"`, and adopting this primitive had to keep it
   * rather than silently drop it.
   */
  readonly ariaLabel?: string;
}

export function Tabs({ items, defaultValue, value, onValueChange, ariaLabel }: TabsProps) {
  return (
    <RadixTabs.Root defaultValue={defaultValue ?? items[0]?.value} value={value} onValueChange={onValueChange}>
      <RadixTabs.List aria-label={ariaLabel} className="flex gap-1 border-b border-neutral-200">
        {items.map((item) => (
          <RadixTabs.Trigger
            key={item.value}
            value={item.value}
            className="border-b-2 border-transparent px-3 py-2 text-sm font-medium text-text-secondary data-[state=active]:border-primary data-[state=active]:text-primary"
          >
            {item.label}
          </RadixTabs.Trigger>
        ))}
      </RadixTabs.List>
      {items.map((item) => (
        <RadixTabs.Content key={item.value} value={item.value} className="pt-4">
          {item.content}
        </RadixTabs.Content>
      ))}
    </RadixTabs.Root>
  );
}
