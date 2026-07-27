/**
 * Timeline / Activity item primitives (`docs/design-system/02_COMPONENTS.md`
 * "Timeline", "Activity item / Audit item") -- chronological event list; backend audit
 * logging already exists (`audit_logs`) but no UI renders it yet. `beforeValue`/
 * `afterValue` are optional, for the Supreme Admin before/after disclosure
 * (`09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §7) -- omitted entirely for a normal (non-audit)
 * timeline entry, never rendered as an empty diff.
 */

export interface ActivityItemData {
  readonly at: string;
  readonly actor: string;
  readonly event: string;
  readonly beforeValue?: string;
  readonly afterValue?: string;
}

export function ActivityItem({ item }: { readonly item: ActivityItemData }) {
  return (
    <li>
      <span className="text-xs text-text-secondary">{new Date(item.at).toLocaleString()}</span>
      <p className="text-sm text-text-primary">
        <strong>{item.actor}</strong> — {item.event}
      </p>
      {item.beforeValue !== undefined && item.afterValue !== undefined ? (
        <p className="text-xs text-text-secondary">
          <span className="line-through">{item.beforeValue}</span> → {item.afterValue}
        </p>
      ) : null}
    </li>
  );
}

export function Timeline({ items }: { readonly items: readonly ActivityItemData[] }) {
  return (
    <ol className="flex flex-col gap-3 border-l-2 border-neutral-200 pl-4">
      {items.map((item, index) => (
        <ActivityItem key={`${item.at}-${index}`} item={item} />
      ))}
    </ol>
  );
}
