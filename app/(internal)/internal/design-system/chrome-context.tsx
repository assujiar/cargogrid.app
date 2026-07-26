"use client";

/**
 * Shared client state for the Design System Showcase's own chrome (theme preview,
 * viewport preview) -- CargoGrid UI Modernization checkpoint 3. Deliberately scoped to
 * this showcase route only, via CSS custom properties layered on top of the platform's
 * real tokens (`--color-*`), never a change to `app/globals.css` or a new Tailwind
 * `dark:` variant strategy wired app-wide.
 *
 * Disclosed gap this component does NOT paper over: CargoGrid's Design System has not
 * defined a tenant-facing dark theme token set anywhere (no entry in
 * `docs/standards/DESIGN_SYSTEM.md` §2's token table, no `.dark` class or
 * `prefers-color-scheme` block in `app/globals.css`). The "dark" state below only
 * recombines the existing neutral scale for this showcase's own reading chrome --
 * toggling it does not change how the real showcased components render, because they
 * consume `--color-*` tokens directly and none of those tokens vary by this toggle.
 */

import { createContext, useContext, useMemo, useState, type CSSProperties, type ReactNode } from "react";

export type ShowcaseTheme = "light" | "dark";
export type ShowcaseViewport = "desktop" | "tablet" | "mobile";

interface ShowcaseChromeState {
  readonly theme: ShowcaseTheme;
  readonly setTheme: (theme: ShowcaseTheme) => void;
  readonly viewport: ShowcaseViewport;
  readonly setViewport: (viewport: ShowcaseViewport) => void;
}

const ShowcaseChromeContext = createContext<ShowcaseChromeState | null>(null);

const CHROME_VARS: Record<ShowcaseTheme, CSSProperties> = {
  light: {
    ["--ds-bg" as string]: "var(--color-app-background)",
    ["--ds-surface" as string]: "var(--color-surface)",
    ["--ds-text" as string]: "var(--color-text-primary)",
    ["--ds-text-secondary" as string]: "var(--color-text-secondary)",
    ["--ds-border" as string]: "var(--color-border-default)",
  },
  dark: {
    ["--ds-bg" as string]: "var(--color-neutral-900)",
    ["--ds-surface" as string]: "var(--color-neutral-800)",
    ["--ds-text" as string]: "var(--color-neutral-50)",
    ["--ds-text-secondary" as string]: "var(--color-neutral-300)",
    ["--ds-border" as string]: "var(--color-neutral-700)",
  },
};

export function ShowcaseChromeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<ShowcaseTheme>("light");
  const [viewport, setViewport] = useState<ShowcaseViewport>("desktop");

  const value = useMemo(() => ({ theme, setTheme, viewport, setViewport }), [theme, viewport]);

  return (
    <ShowcaseChromeContext.Provider value={value}>
      <div style={CHROME_VARS[theme]} className="flex min-h-screen flex-col bg-[var(--ds-bg)] text-[var(--ds-text)]">
        {children}
      </div>
    </ShowcaseChromeContext.Provider>
  );
}

export function useShowcaseChrome(): ShowcaseChromeState {
  const context = useContext(ShowcaseChromeContext);
  if (!context) {
    throw new Error("useShowcaseChrome must be used within ShowcaseChromeProvider");
  }
  return context;
}
