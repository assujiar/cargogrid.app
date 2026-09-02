/**
 * Description List (this checkpoint's own instruction named it; not previously scoped
 * by any CargoGrid design-system document -- `docs/design-system/08_COMPONENT_
 * INVENTORY.md` disclosed this gap). Native `<dl>`, the correct semantic element for
 * label/value pairs -- every real detail page already renders this exact shape inline
 * (e.g. the Job Order handoff summary in the showcase); this is that pattern extracted.
 *
 * `ISS-2026-246` (first real consumers: the HRIS employee detail panel and the ESS
 * "my profile" panel) added the two things every one of those hand-rolled `<dl>`s
 * already had and this primitive did not, which is precisely why none of them could
 * adopt it:
 *
 * 1. **The column count is responsive.** Every inline `<dl>` in the tree is written
 *    `grid-cols-1 sm:grid-cols-2`, never a flat `grid-cols-2` -- a two- or three-column
 *    label/value grid at 360px is unreadable, and `AGENTS.md` §"UX, performance, and
 *    accessibility" requires responsive internal ERP screens (RPD-004). This changes
 *    nothing that existed: the component had zero consumers before this task.
 * 2. **An item may span the full row** (`wide`). A postal address or a free-text reason
 *    is rendered full-width by the hand-rolled versions (`sm:col-span-2`); without this
 *    flag, adopting the primitive would have silently squeezed those into a half column.
 */

export interface DescriptionListItem {
  readonly term: string;
  readonly value: string;
  /** Render this pair across the whole row rather than in one column -- for long values (addresses, reasons). */
  readonly wide?: boolean;
}

const GRID_CLASS: Record<1 | 2 | 3, string> = {
  1: "grid-cols-1",
  2: "grid-cols-1 sm:grid-cols-2",
  3: "grid-cols-1 sm:grid-cols-3",
};

export function DescriptionList({ items, columns = 2 }: { readonly items: readonly DescriptionListItem[]; readonly columns?: 1 | 2 | 3 }) {
  return (
    <dl className={`grid ${GRID_CLASS[columns]} gap-x-6 gap-y-2 text-sm`}>
      {items.map((item) => (
        <div key={item.term} className={item.wide ? "sm:col-span-full" : undefined}>
          <dt className="text-xs font-medium text-text-secondary">{item.term}</dt>
          <dd className="text-text-primary">{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}
