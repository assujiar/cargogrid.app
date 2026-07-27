import { COMPONENT_REGISTRY } from "../../../../../lib/design-system/component-registry.ts";

export default function AccessibilityPage() {
  const withA11y = COMPONENT_REGISTRY.filter((entry) => entry.a11y);

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">Accessibility</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          WCAG 2.2 AA acceptance criteria are decided platform-wide in{" "}
          <code>docs/design-system/06_ACCESSIBILITY_PERFORMANCE.md</code> — this page only compiles the per-component
          accessibility behavior actually implemented and verified, cited from the same component registry driving the
          Components page.
        </p>
      </div>

      <dl className="flex flex-col gap-3">
        {withA11y.map((entry) => (
          <div key={entry.name} className="rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-3">
            <dt className="text-sm font-semibold">{entry.name}</dt>
            <dd className="mt-1 text-sm text-[var(--ds-text-secondary)]">{entry.a11y}</dd>
          </div>
        ))}
      </dl>

      <p className="text-xs text-[var(--ds-text-secondary)]">
        No automated accessibility check runs against this showcase route yet — the repository&apos;s existing{" "}
        <code>@axe-core/playwright</code> suite (<code>e2e/</code>) targets real business screens, not this internal
        tool. Reduced motion:
        this showcase&apos;s own viewport-resize transition respects <code>prefers-reduced-motion</code> via Tailwind&apos;s{" "}
        <code>motion-reduce:</code> variant (see <code>viewport-frame.tsx</code>) — no other component here uses motion.
      </p>
    </div>
  );
}
