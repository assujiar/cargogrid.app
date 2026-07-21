/**
 * GraphQL depth and complexity limiter (PLT-130, CG-S6-PLT-027; ADR-0012, resolving
 * ADR-CAND-ARCH-017's numeric-limit sub-question: depth limit 8, complexity budget
 * 1000 units via a per-field-type cost table). "The GraphQL-side counterpart to REST's
 * explicit filter allowlist... preventing an unbounded nested query from becoming the
 * equivalent of an arbitrary SQL-like filter" (docs/architecture/08_API_INTEGRATION_
 * WORKSTREAM.md §5).
 *
 * Operates on a minimal field-selection tree shape any real GraphQL execution layer's
 * parsed AST can be mapped onto -- this repository has no `graphql` package dependency
 * and no live GraphQL server (08_*.md line 11), so this module deliberately does not
 * parse raw GraphQL query text itself (building a bespoke parser here would be exactly
 * the "generic integration hub" Prompt 130 §12 forbids). It scores an already-
 * structured selection tree a future resolver-aware execution layer would produce from
 * its own real AST.
 */

export const MAX_QUERY_DEPTH = 8;
export const MAX_QUERY_COMPLEXITY = 1000;
export const MAX_LIST_ITEM_COUNT = 100;

export const SCALAR_FIELD_COST = 1;
export const OBJECT_FIELD_COST = 2;
export const LIST_FIELD_BASE_COST = 10;
export const LIST_FIELD_PER_ITEM_COST = 1;

export interface QueryField {
  readonly name: string;
  readonly isList?: boolean;
  /** The `first`/`limit` argument, if isList -- capped at MAX_LIST_ITEM_COUNT regardless of what a caller claims. */
  readonly requestedItemCount?: number;
  readonly children?: readonly QueryField[];
}

export class QueryTooDeepError extends Error {
  readonly depth: number;
  constructor(depth: number) {
    super(`query depth ${depth} exceeds the maximum allowed depth of ${MAX_QUERY_DEPTH}`);
    this.name = "QueryTooDeepError";
    this.depth = depth;
  }
}

export class QueryTooComplexError extends Error {
  readonly complexity: number;
  constructor(complexity: number) {
    super(`query complexity ${complexity} exceeds the maximum allowed budget of ${MAX_QUERY_COMPLEXITY}`);
    this.name = "QueryTooComplexError";
    this.complexity = complexity;
  }
}

/** A field with no children is depth 1 relative to itself; each nested selection level adds 1. */
export function computeQueryDepth(field: QueryField, currentDepth = 1): number {
  if (!field.children || field.children.length === 0) return currentDepth;
  return Math.max(...field.children.map((child) => computeQueryDepth(child, currentDepth + 1)));
}

function cappedItemCount(field: QueryField): number {
  return Math.min(field.requestedItemCount ?? 1, MAX_LIST_ITEM_COUNT);
}

/** A list field's own children are evaluated once per requested item -- their cost is multiplied by the (capped) item count, mirroring the real execution cost of resolving that many rows' worth of nested fields. */
export function computeFieldCost(field: QueryField): number {
  const hasChildren = Boolean(field.children && field.children.length > 0);
  const ownCost = field.isList ? LIST_FIELD_BASE_COST + LIST_FIELD_PER_ITEM_COST * cappedItemCount(field) : hasChildren ? OBJECT_FIELD_COST : SCALAR_FIELD_COST;
  const childrenCost = (field.children ?? []).reduce((sum, child) => sum + computeFieldCost(child), 0);
  const multiplier = field.isList ? cappedItemCount(field) : 1;
  return ownCost + childrenCost * multiplier;
}

export function computeQueryComplexity(roots: readonly QueryField[]): number {
  return roots.reduce((sum, field) => sum + computeFieldCost(field), 0);
}

/** Throws QueryTooDeepError on the first root field exceeding MAX_QUERY_DEPTH. */
export function checkQueryDepth(roots: readonly QueryField[]): void {
  for (const root of roots) {
    const depth = computeQueryDepth(root);
    if (depth > MAX_QUERY_DEPTH) {
      throw new QueryTooDeepError(depth);
    }
  }
}

/** Throws QueryTooComplexError if the total scored complexity exceeds MAX_QUERY_COMPLEXITY; otherwise returns the computed complexity. */
export function checkQueryComplexity(roots: readonly QueryField[]): number {
  const complexity = computeQueryComplexity(roots);
  if (complexity > MAX_QUERY_COMPLEXITY) {
    throw new QueryTooComplexError(complexity);
  }
  return complexity;
}
