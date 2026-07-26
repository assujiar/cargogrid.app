"use client";

import { useShowcaseChrome } from "./chrome-context.tsx";

export function ThemeToggle() {
  const { theme, setTheme } = useShowcaseChrome();

  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs font-medium text-[var(--ds-text-secondary)]">Showcase theme preview</span>
      <button
        type="button"
        aria-pressed={theme === "dark"}
        onClick={() => setTheme(theme === "light" ? "dark" : "light")}
        className="rounded-md border border-[var(--ds-border)] px-3 py-1.5 text-left text-sm text-[var(--ds-text)]"
      >
        {theme === "light" ? "Preview dark chrome" : "Preview light chrome"}
      </button>
      <p className="text-xs text-[var(--ds-text-secondary)]">
        Previews this showcase&apos;s own reading chrome only — CargoGrid has no dark theme token set defined yet (see
        Foundations), so the real components below do not change appearance.
      </p>
    </div>
  );
}
