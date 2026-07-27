/**
 * Pagination primitive (CargoGrid UI Modernization checkpoint,
 * `docs/design-system/02_COMPONENTS.md`). Server-renderable (plain `next/link` hrefs,
 * no client-side state) -- the caller supplies `buildHref`, so this component stays
 * agnostic to whichever other query params (future filters/sort) a given list screen
 * carries. Page-window math lives in `lib/tables/pagination-range.ts` (unit-tested
 * there; `.tsx` files have no test runner in this repository yet).
 *
 * Renders nothing when there is only one page -- a single-page list has no pagination
 * decision to make.
 */

import Link from "next/link";
import { computePaginationRange } from "../../lib/tables/pagination-range.ts";

export interface PaginationProps {
  readonly page: number;
  readonly pageSize: number;
  readonly totalCount: number;
  /** Builds the href for a given target page, e.g. `(p) => `/${tenantSlug}/commercial/leads?page=${p}`` -- keeps this component agnostic to whatever other query params the caller's screen carries. */
  readonly buildHref: (targetPage: number) => string;
}

export function Pagination({ page, pageSize, totalCount, buildHref }: PaginationProps) {
  const range = computePaginationRange({ page, pageSize, totalCount });
  if (range.totalPages <= 1) {
    return null;
  }

  return (
    <nav aria-label="Pagination" className="flex flex-wrap items-center gap-1 text-sm">
      <PaginationControl href={buildHref(range.page - 1)} label="Previous" disabled={!range.hasPrevious} />
      {range.items.map((item, index) =>
        item === "ellipsis" ? (
          <span key={`ellipsis-${index}`} aria-hidden="true" className="px-2 text-neutral-400">
            …
          </span>
        ) : (
          <PaginationControl key={item} href={buildHref(item)} label={String(item)} current={item === range.page} />
        ),
      )}
      <PaginationControl href={buildHref(range.page + 1)} label="Next" disabled={!range.hasNext} />
    </nav>
  );
}

function PaginationControl({
  href,
  label,
  current = false,
  disabled = false,
}: {
  readonly href: string;
  readonly label: string;
  readonly current?: boolean;
  readonly disabled?: boolean;
}) {
  if (disabled) {
    return (
      <span aria-disabled="true" className="cursor-not-allowed rounded-md px-2.5 py-1 text-neutral-300">
        {label}
      </span>
    );
  }

  if (current) {
    return (
      <span aria-current="page" className="rounded-md bg-primary px-2.5 py-1 font-medium text-neutral-50">
        {label}
      </span>
    );
  }

  return (
    <Link href={href} className="rounded-md px-2.5 py-1 text-neutral-700 hover:bg-neutral-100">
      {label}
    </Link>
  );
}
