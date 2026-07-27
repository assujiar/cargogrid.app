/**
 * Pure pagination-window calculation for `components/tables/pagination.tsx` (the
 * first Pagination primitive, `docs/design-system/02_COMPONENTS.md`). Extracted as a
 * plain, unit-tested `.ts` module rather than left inline in the `.tsx` component --
 * this repository's own test runner (`node --experimental-strip-types`) cannot import
 * JSX, the same discipline `lib/theme/resolve-portal-theme.ts` already established.
 */

export interface PaginationRangeInput {
  readonly page: number;
  readonly pageSize: number;
  readonly totalCount: number;
}

export interface PaginationRangeResult {
  readonly page: number;
  readonly totalPages: number;
  readonly hasPrevious: boolean;
  readonly hasNext: boolean;
  readonly items: readonly (number | "ellipsis")[];
}

/** Always includes page 1, the last page, the current page, and its immediate neighbors; collapses any gap into a single "ellipsis" marker. Inputs are clamped defensively (never throws on a malformed page/pageSize/totalCount). */
export function computePaginationRange(input: PaginationRangeInput): PaginationRangeResult {
  const pageSize = Math.max(Math.trunc(input.pageSize) || 1, 1);
  const totalCount = Math.max(Math.trunc(input.totalCount) || 0, 0);
  const totalPages = Math.max(Math.ceil(totalCount / pageSize), 1);
  const page = Math.min(Math.max(Math.trunc(input.page) || 1, 1), totalPages);

  const pagesToShow = new Set<number>([1, totalPages, page]);
  if (page - 1 >= 1) {
    pagesToShow.add(page - 1);
  }
  if (page + 1 <= totalPages) {
    pagesToShow.add(page + 1);
  }

  const sorted = [...pagesToShow].sort((a, b) => a - b);
  const items: (number | "ellipsis")[] = [];
  for (const [index, value] of sorted.entries()) {
    const previous = sorted[index - 1];
    if (index > 0 && previous !== undefined && value - previous > 1) {
      items.push("ellipsis");
    }
    items.push(value);
  }

  return {
    page,
    totalPages,
    hasPrevious: page > 1,
    hasNext: page < totalPages,
    items,
  };
}
