/**
 * The pagination cap for `server/queries/*.ts` functions that read a base table directly.
 *
 * `ISS-2026-238` live-verified via `EXPLAIN (ANALYZE, BUFFERS)` that `listAccounts`,
 * `listCustomerContracts`, `listQuotationsForTenant` and `listFilesForTenant` each fetch **every
 * row for the tenant** and return it to the browser on every page load — no `.range()`, no
 * `.limit()`. Fast at the seeded volume, and linear in tenant data with no ceiling.
 *
 * The RPC-mediated list endpoints in this repository already cap correctly (`list_finance_invoices`
 * [200], `list_rfqs` [200], `query_audit_logs` [200], the ATW-023 customer lists [50]). The gap is
 * narrowly the handful of query functions that, per their own header comments, read the base table
 * directly because no masked view exists for it — and so never inherited that convention. This
 * module is that convention, in one place.
 *
 * **A silently capped list is worse than an unbounded one**, which is the whole reason this
 * returns a shape rather than an array. An unbounded read is slow and expensive; a silently capped
 * read is *wrong* — the reader believes they are looking at all their accounts when they are
 * looking at the newest 200, and nothing on the page says otherwise. So every bounded read reports
 * whether it truncated, and the caller is expected to say so.
 */

/**
 * 200, matching the cap the RPC layer already uses for its own transactional lists
 * (`list_finance_invoices`, `list_rfqs`, `query_audit_logs`). Deliberately the same number rather
 * than a new one: two different caps in one product would be a difference a reader has to learn
 * for no benefit.
 */
export const BOUNDED_LIST_LIMIT = 200;

export interface BoundedList<T> {
  readonly rows: readonly T[];
  /** True when the underlying table held more rows than the cap — the caller must surface this. */
  readonly truncated: boolean;
  readonly limit: number;
}

/**
 * Fetches one row past the cap to detect truncation, then drops it.
 *
 * The alternative — a `count: 'exact'` head request — costs a second scan of the whole table on
 * every page load, which is the cost this fix exists to remove. One extra row is enough to answer
 * the only question the UI actually has: "is there more than I am showing?"
 */
export function boundedRange(limit: number = BOUNDED_LIST_LIMIT): { from: number; to: number } {
  return { from: 0, to: limit };
}

export function toBoundedList<T>(rows: readonly T[], limit: number = BOUNDED_LIST_LIMIT): BoundedList<T> {
  const truncated = rows.length > limit;
  return { rows: truncated ? rows.slice(0, limit) : rows, truncated, limit };
}

/**
 * The variant for a read whose act of fetching a row has a **side effect** — specifically
 * `app.list_files_for_tenant`, which writes an `app.file_access_logs` entry per row it returns.
 *
 * `toBoundedList` detects truncation by fetching one row past the cap and discarding it. That is
 * free for a plain `select` and **wrong** here: the discarded row would leave an access-log entry
 * saying somebody viewed a file they were never shown. An audit trail that records views that did
 * not happen is worse than one that is merely incomplete.
 *
 * So this infers truncation from reaching the cap instead. It is deliberately conservative — a
 * tenant holding exactly 200 files sees "there may be more" when there is not — and that is the
 * right way to be wrong: over-warning costs a reader one unnecessary sentence, while
 * under-warning costs them the belief that they have seen everything.
 */
export function toBoundedListByCapReached<T>(rows: readonly T[], limit: number = BOUNDED_LIST_LIMIT): BoundedList<T> {
  return { rows, truncated: rows.length >= limit, limit };
}
