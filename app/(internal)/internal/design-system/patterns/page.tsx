import { PATTERN_REGISTRY } from "../../../../../lib/design-system/pattern-registry.ts";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";

export default function PatternsPage() {
  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Pattern gallery</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          Reference pointers to real existing pages, not new business modules and not fabricated demo pages standing
          in for a pattern this repository has never built.
        </p>
      </div>

      <div className="flex flex-col gap-3">
        {PATTERN_REGISTRY.map((pattern) => (
          <article key={pattern.name} className="rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-4">
            <div className="flex items-center justify-between gap-2">
              <h2 className="text-base font-semibold">{pattern.name}</h2>
              <StatusBadge
                tone={pattern.status === "REAL_REFERENCE" ? "success" : "neutral"}
                label={pattern.status === "REAL_REFERENCE" ? "Real reference exists" : "Not built"}
              />
            </div>
            <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">{pattern.description}</p>
            {pattern.referenceFile ? (
              <p className="mt-2 text-xs">
                Reference: <code>{pattern.referenceFile}</code>
              </p>
            ) : null}
            {pattern.note ? <p className="mt-1 text-xs text-[var(--ds-text-secondary)]">{pattern.note}</p> : null}
          </article>
        ))}
      </div>
    </div>
  );
}
