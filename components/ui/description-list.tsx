/**
 * Description List (this checkpoint's own instruction named it; not previously scoped
 * by any CargoGrid design-system document -- `docs/design-system/08_COMPONENT_
 * INVENTORY.md` disclosed this gap). Native `<dl>`, the correct semantic element for
 * label/value pairs -- every real detail page already renders this exact shape inline
 * (e.g. the Job Order handoff summary in the showcase); this is that pattern extracted.
 */

export interface DescriptionListItem {
  readonly term: string;
  readonly value: string;
}

export function DescriptionList({ items, columns = 2 }: { readonly items: readonly DescriptionListItem[]; readonly columns?: 1 | 2 | 3 }) {
  const gridClass = columns === 1 ? "grid-cols-1" : columns === 2 ? "grid-cols-2" : "grid-cols-3";

  return (
    <dl className={`grid ${gridClass} gap-x-6 gap-y-2 text-sm`}>
      {items.map((item) => (
        <div key={item.term}>
          <dt className="text-xs font-medium text-text-secondary">{item.term}</dt>
          <dd className="text-text-primary">{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}
