import { TOKEN_CATEGORIES, type TokenCategory } from "../../../../../lib/design-system/tokens.ts";

const STATUS_LABEL: Record<TokenCategory["status"], string> = {
  IMPLEMENTED: "Implemented",
  DECIDED_NOT_IMPLEMENTED: "Decided, not implemented",
  FRAMEWORK_DEFAULT: "Tailwind framework default",
  NOT_DECIDED: "Not decided anywhere in this repository",
};

/**
 * Foundations (CargoGrid UI Modernization checkpoint 3). Every swatch below renders
 * through the real Tailwind utility class or `var(--x)` reference named in
 * `lib/design-system/tokens.ts` -- unit-tested there to actually exist in
 * `app/globals.css` -- never a hardcoded/approximated copy of the value.
 */
export default function FoundationsPage() {
  return (
    <div className="flex flex-col gap-8">
      <div>
        <h1 className="text-xl font-semibold">Foundations</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          Read live from <code>app/globals.css</code> (Tailwind v4 <code>@theme</code>) — the single runtime token
          source. Categories this repository has not decided or implemented are shown as real, disclosed gaps, not
          approximated.
        </p>
      </div>

      {TOKEN_CATEGORIES.map((category) => (
        <section key={category.key} className="flex flex-col gap-3">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="text-base font-semibold">{category.title}</h2>
            <span className="text-xs text-[var(--ds-text-secondary)]">
              {STATUS_LABEL[category.status]} · {category.sourceFile}
            </span>
          </div>
          {category.note ? <p className="text-sm text-[var(--ds-text-secondary)]">{category.note}</p> : null}

          {category.items.length === 0 ? (
            <p className="rounded-md border border-dashed border-[var(--ds-border)] p-3 text-sm text-[var(--ds-text-secondary)]">
              No tokens exist for this category — nothing to render.
            </p>
          ) : category.key === "neutral" ||
            category.key === "semantic" ||
            category.key === "brand" ||
            category.key === "surface" ? (
            <div className="flex flex-wrap gap-3">
              {category.items.map((item) => (
                <div key={item.cssVar} className="flex w-32 flex-col gap-1">
                  <div
                    className={`h-12 w-full rounded-md border border-[var(--ds-border)] ${item.utilityClass?.startsWith("hover:") ? "" : item.utilityClass}`}
                    style={item.utilityClass?.startsWith("hover:") ? { background: `var(${item.cssVar})` } : undefined}
                  />
                  <span className="text-xs font-medium">{item.label}</span>
                  <code className="text-xs text-[var(--ds-text-secondary)]">{item.cssVar}</code>
                </div>
              ))}
            </div>
          ) : category.key === "typography-family" ? (
            <div className="flex flex-col gap-2">
              {category.items.map((item) => (
                <p key={item.cssVar} className={`${item.utilityClass} text-lg`}>
                  {item.label} — The quick brown fox jumps over the lazy dog.
                </p>
              ))}
            </div>
          ) : category.key === "typography-scale" ? (
            <div className="flex flex-col gap-1">
              {category.items.map((item) => (
                <p key={item.cssVar} className={item.utilityClass}>
                  <code className="mr-2 text-[var(--ds-text-secondary)]">{item.cssVar}</code>
                  {item.label} — CargoGrid Design System
                </p>
              ))}
            </div>
          ) : category.key === "radius" ? (
            <div className="flex flex-wrap gap-3">
              {category.items.map((item) => (
                <div key={item.cssVar} className="flex flex-col items-center gap-1">
                  <div className={`h-12 w-12 border-2 border-primary bg-surface ${item.utilityClass}`} />
                  <span className="text-xs">{item.label}</span>
                </div>
              ))}
            </div>
          ) : category.key === "shadow" ? (
            <div className="flex flex-wrap gap-4">
              {category.items.map((item) => (
                <div key={item.cssVar} className={`h-16 w-24 rounded-md bg-surface ${item.utilityClass}`}>
                  <span className="flex h-full items-center justify-center text-xs">{item.label}</span>
                </div>
              ))}
            </div>
          ) : category.key === "density" ? (
            <div className="flex flex-col gap-2">
              {category.items.map((item) => (
                <div
                  key={item.cssVar}
                  style={{ height: `var(${item.cssVar})` }}
                  className="flex items-center rounded border border-[var(--ds-border)] bg-surface px-3 text-xs"
                >
                  {item.label} — <code className="ml-1">{item.cssVar}</code>
                </div>
              ))}
            </div>
          ) : category.key === "breakpoint" || category.key === "spacing" ? (
            <ul className="flex flex-wrap gap-3 text-sm">
              {category.items.map((item) => (
                <li key={item.cssVar} className="rounded-md border border-[var(--ds-border)] px-3 py-1">
                  {item.label}
                </li>
              ))}
            </ul>
          ) : (
            <ul className="flex flex-col gap-1 text-sm">
              {category.items.map((item) => (
                <li key={item.cssVar}>
                  <code>{item.cssVar}</code> — {item.label}
                </li>
              ))}
            </ul>
          )}
        </section>
      ))}
    </div>
  );
}
