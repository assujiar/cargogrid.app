/**
 * Accordion primitive (`docs/design-system/02_COMPONENTS.md` "Accordion") --
 * collapsible content sections. Native `<details>`/`<summary>`, server-safe, zero
 * client JS -- correct keyboard/screen-reader behavior for free, no Radix needed.
 */

import type { ReactNode } from "react";

export interface AccordionItem {
  readonly title: string;
  readonly content: ReactNode;
  readonly defaultOpen?: boolean;
  /**
   * Stable identity when the titles are not unique (`ISS-2026-246`, first-consumer
   * requirement). One section per record -- a payslip, an invoice, a shipment leg -- is
   * this primitive's most common real shape, and two such records can easily produce the
   * same title string ("net pay 8,500,000 IDR" twice in a year). Keying on the title
   * alone would then hand two `<details>` elements the same React key, and because
   * open/closed is uncontrolled DOM state, the wrong panel opens. Defaults to `title`,
   * which stays correct for the fixed, hand-written section lists.
   */
  readonly id?: string;
}

export function Accordion({ items }: { readonly items: readonly AccordionItem[] }) {
  return (
    <div className="flex flex-col divide-y divide-neutral-200 rounded-md border border-neutral-200">
      {items.map((item) => (
        <details key={item.id ?? item.title} open={item.defaultOpen} className="group p-3">
          <summary className="cursor-pointer text-sm font-medium text-text-primary marker:content-none">
            <span aria-hidden="true" className="mr-2 inline-block transition-transform group-open:rotate-90">
              ▸
            </span>
            {item.title}
          </summary>
          <div className="mt-2 pl-5 text-sm text-text-secondary">{item.content}</div>
        </details>
      ))}
    </div>
  );
}
