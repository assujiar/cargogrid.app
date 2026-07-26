import { COMPONENT_REGISTRY } from "../../../../../lib/design-system/component-registry.ts";
import { ComponentStatusBadge } from "../components/component-status-badge.tsx";

export default function DomainComponentsPage() {
  const entries = COMPONENT_REGISTRY.filter((entry) => entry.category === "DomainComponents");

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Domain Components</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          Domain-aware compositions built from shared primitives (<code>components/domain/</code> in
          `09_UX_DESIGN_SYSTEM_WORKSTREAM.md`&apos;s own naming) — none exist yet. <code>components/domain/</code> does
          not exist in this repository (confirmed empty this checkpoint); every domain-specific screen today builds its
          own page-local form/panel instead.
        </p>
      </div>

      {entries.map((entry) => (
        <article key={entry.name} className="rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-4">
          <div className="flex items-center justify-between gap-2">
            <h2 className="text-base font-semibold">{entry.name}</h2>
            <ComponentStatusBadge status={entry.status} />
          </div>
          <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">{entry.purpose}</p>
          {entry.duplicateNote ? (
            <p className="mt-2 rounded-md border border-warning/30 bg-warning/10 p-2 text-xs">{entry.duplicateNote}</p>
          ) : null}
          <p className="mt-2 text-xs text-[var(--ds-text-secondary)]">Source: {entry.citation}</p>
        </article>
      ))}
    </div>
  );
}
