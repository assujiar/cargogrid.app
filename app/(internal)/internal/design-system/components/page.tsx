"use client";

import { useMemo, useState } from "react";
import {
  COMPONENT_REGISTRY,
  CATEGORY_LABELS,
  type ComponentCategory,
  type ComponentStatus,
} from "../../../../../lib/design-system/component-registry.ts";
import { slugifyComponentName } from "../slugify.ts";
import { ComponentStatusBadge } from "./component-status-badge.tsx";
import { CopyImport } from "../copy-import.tsx";
import { ViewportFrame } from "../viewport-frame.tsx";
import { ButtonShowcase, BannerShowcase, BadgeShowcase, StatusBadgeShowcase } from "./implemented-showcases.tsx";

const LIVE_SHOWCASES: Partial<Record<string, () => React.JSX.Element>> = {
  Button: ButtonShowcase,
  Banner: BannerShowcase,
  Badge: BadgeShowcase,
  StatusBadge: StatusBadgeShowcase,
};

const STATUSES: readonly ComponentStatus[] = ["IMPLEMENTED", "DOCUMENTED_ONLY", "BLOCKED", "NOT_NAMED"];
const CATEGORIES = Object.keys(CATEGORY_LABELS) as ComponentCategory[];

export default function ComponentsPage() {
  const [categoryFilter, setCategoryFilter] = useState<ComponentCategory | "all">("all");
  const [statusFilter, setStatusFilter] = useState<ComponentStatus | "all">("all");

  const filtered = useMemo(
    () =>
      COMPONENT_REGISTRY.filter(
        (entry) => (categoryFilter === "all" || entry.category === categoryFilter) && (statusFilter === "all" || entry.status === statusFilter),
      ),
    [categoryFilter, statusFilter],
  );

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold">Components</h1>
        <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">
          {COMPONENT_REGISTRY.length} catalogued (Layout, Navigation, Actions, Forms, Data Display, Data Entry, Feedback,
          Overlays, Charts and Analytics, Status and Workflow — Tables and Domain Components have their own dedicated
          pages). Only <code>Button</code>, <code>Banner</code>, <code>Badge</code>, and <code>StatusBadge</code> are real
          in this category set; everything else is disclosed as documented-only, blocked, or not previously named,
          citing exactly where that status comes from.
        </p>
      </div>

      <div className="flex flex-wrap gap-4">
        <label className="flex flex-col gap-1 text-xs font-medium text-[var(--ds-text-secondary)]">
          Category
          <select
            value={categoryFilter}
            onChange={(event) => setCategoryFilter(event.target.value as ComponentCategory | "all")}
            className="rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] px-2 py-1 text-sm text-[var(--ds-text)]"
          >
            <option value="all">All categories</option>
            {CATEGORIES.map((category) => (
              <option key={category} value={category}>
                {CATEGORY_LABELS[category]}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs font-medium text-[var(--ds-text-secondary)]">
          Status
          <select
            value={statusFilter}
            onChange={(event) => setStatusFilter(event.target.value as ComponentStatus | "all")}
            className="rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] px-2 py-1 text-sm text-[var(--ds-text)]"
          >
            <option value="all">All statuses</option>
            {STATUSES.map((status) => (
              <option key={status} value={status}>
                {status}
              </option>
            ))}
          </select>
        </label>
      </div>

      <p className="text-xs text-[var(--ds-text-secondary)]" role="status">
        Showing {filtered.length} of {COMPONENT_REGISTRY.length}.
      </p>

      <div className="flex flex-col gap-4">
        {filtered.map((entry) => {
          const LiveShowcase = LIVE_SHOWCASES[entry.name];
          return (
            <article
              key={entry.name}
              id={slugifyComponentName(entry.name)}
              className="scroll-mt-4 rounded-md border border-[var(--ds-border)] bg-[var(--ds-surface)] p-4"
            >
              <div className="flex flex-wrap items-center justify-between gap-2">
                <h2 className="text-base font-semibold">{entry.name}</h2>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-[var(--ds-text-secondary)]">{CATEGORY_LABELS[entry.category]}</span>
                  <ComponentStatusBadge status={entry.status} />
                </div>
              </div>
              <p className="mt-1 text-sm text-[var(--ds-text-secondary)]">{entry.purpose}</p>

              {entry.sourceFile && entry.importSnippet ? (
                <div className="mt-3">
                  <CopyImport importSnippet={entry.importSnippet} sourceFile={entry.sourceFile} />
                </div>
              ) : null}

              {LiveShowcase ? (
                <div className="mt-3">
                  <ViewportFrame>
                    <LiveShowcase />
                  </ViewportFrame>
                </div>
              ) : null}

              <dl className="mt-3 grid grid-cols-1 gap-x-6 gap-y-1 text-xs sm:grid-cols-2">
                {entry.variants ? (
                  <div>
                    <dt className="font-medium text-[var(--ds-text-secondary)]">Variants</dt>
                    <dd>{entry.variants.join(", ")}</dd>
                  </div>
                ) : null}
                {entry.sizes ? (
                  <div>
                    <dt className="font-medium text-[var(--ds-text-secondary)]">Sizes</dt>
                    <dd>{entry.sizes.join(", ")}</dd>
                  </div>
                ) : null}
                {entry.states ? (
                  <div>
                    <dt className="font-medium text-[var(--ds-text-secondary)]">States</dt>
                    <dd>{entry.states.join(", ")}</dd>
                  </div>
                ) : null}
                {entry.tokensUsed ? (
                  <div>
                    <dt className="font-medium text-[var(--ds-text-secondary)]">Tokens used</dt>
                    <dd>{entry.tokensUsed.join(", ")}</dd>
                  </div>
                ) : null}
                {entry.consumers ? (
                  <div className="sm:col-span-2">
                    <dt className="font-medium text-[var(--ds-text-secondary)]">Consumers</dt>
                    <dd>{entry.consumers.length > 0 ? entry.consumers.join("; ") : "None — built but not yet used anywhere."}</dd>
                  </div>
                ) : null}
                {entry.a11y ? (
                  <div className="sm:col-span-2">
                    <dt className="font-medium text-[var(--ds-text-secondary)]">Accessibility</dt>
                    <dd>{entry.a11y}</dd>
                  </div>
                ) : null}
                {entry.responsive ? (
                  <div className="sm:col-span-2">
                    <dt className="font-medium text-[var(--ds-text-secondary)]">Responsive</dt>
                    <dd>{entry.responsive}</dd>
                  </div>
                ) : null}
              </dl>

              {entry.duplicateNote ? (
                <p className="mt-2 rounded-md border border-warning/30 bg-warning/10 p-2 text-xs text-[var(--ds-text)]">
                  {entry.duplicateNote}
                </p>
              ) : null}

              <p className="mt-2 text-xs text-[var(--ds-text-secondary)]">Source: {entry.citation}</p>
            </article>
          );
        })}
      </div>
    </div>
  );
}
