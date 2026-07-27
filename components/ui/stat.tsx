/**
 * Stat (this checkpoint's own instruction named it; not previously scoped by any
 * CargoGrid design-system document -- disclosed gap, `docs/design-system/
 * 08_COMPONENT_INVENTORY.md`). The inline, non-card counterpart to `KpiCard` -- a bare
 * label/value pair for placing inside an existing `Card`/`DescriptionList` context
 * rather than its own bounded tile.
 */

export function Stat({ label, value }: { readonly label: string; readonly value: string }) {
  return (
    <div className="flex flex-col">
      <span className="text-xs text-text-secondary">{label}</span>
      <span className="text-lg font-semibold text-text-primary">{value}</span>
    </div>
  );
}
