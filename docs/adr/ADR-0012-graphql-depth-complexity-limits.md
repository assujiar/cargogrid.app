# ADR-0012 — GraphQL depth and complexity limit values

Status: ACCEPTED
Date: 2026-07-19   Approver: Runtime build agent (Phase 1 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-017` (the depth/complexity numeric-limit sub-question only; the persisted-operation registration mechanism sub-question remains open, see Consequences)   Owning phase/task: Phase 1 (`CG-S6-PLT-027`, Prompt 130, REST and GraphQL Platform API Foundation)

## Question

`docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` §14 (`ADR-CAND-ARCH-017`) asks: what fixed depth limit and per-field complexity weighting should reject an over-expensive GraphQL query before it touches the database (§5: "exact numeric limits `ADR_REQUIRED`")? The candidate was previously `BLOCKED` on "needs enforcement surface" (`docs/adr/README.md` §5.2) — this task is that surface (`08_*.md` line 244's own atomic-backlog row: "GraphQL foundation... depth/complexity limiter (resolves `ADR-CAND-ARCH-017`)... Depends on: API/webhook/job foundation" — this checkpoint).

## Options

1. **Depth limit 8; complexity budget 1000 units via a per-field-type cost table (SELECTED — the candidate's own recommendation, `08_*.md` line 233).**
   - Cost table: scalar field = 1 unit; object field = 2 units (a nested type traversal, cheaper than a list but costlier than a leaf); list/connection field = 10 base units + 1 unit per requested item (the `first`/`limit` argument, itself capped at 100 by the same pagination bound `ADR_REQUIRED` elsewhere in this checkpoint's own `server/policies/pagination.ts`) — the list weighting is deliberately the dominant cost term, since an unbounded nested list is the concrete mechanism `08_*.md` §5 names ("the GraphQL-side counterpart to REST's explicit filter allowlist... preventing an unbounded nested query from becoming the equivalent of an arbitrary SQL-like filter").
   - Trade-off: the 1000-unit budget is a disclosed construction, not a blueprint-sourced exact number — reasoned from Tech Arch §32.7's already-ratified 500ms common-query-plan threshold (`08_*.md` §12, line 201) under an assumed ~0.5ms per complexity unit, the same order-of-magnitude approach `ADR-0011` used for its own webhook auto-disable threshold. A depth of 8 is conservative enough to permit realistic nested reads (e.g. `tenant → shipments → milestones → documents`, 4 levels, well under the ceiling) while rejecting a deliberately or accidentally recursive/adversarial query shape.
   - Trade-off against: no CargoGrid-specific measured traffic exists yet (this repository is still Phase 1 Platform Core, no live tenant traffic, no GraphQL server even wired up yet) — the candidate's own text anticipates this explicitly: "tuned from measured Phase-1/2 traffic rather than guessed once and left static." These values are a deliberately revisitable starting point, not a permanent constant.
2. **Defer numeric values indefinitely until a live GraphQL server exists to measure against.**
   - Trade-off: this is functionally the status quo the candidate has already sat in since Phase 0 (`BLOCKED` → `ADR_REQUIRED`) — deferring further leaves the scoring *algorithm itself* untestable, when the algorithm (not the live wiring) is exactly the part this checkpoint can build and prove for real, the same reasoning `ADR-0011` applied to HMAC signature computation. Rejected — the algorithm doesn't need a live server to be real and tested, only the numbers need eventual traffic-informed revision, which this ADR already anticipates.

## Decision

**Depth limit: 8. Complexity budget: 1000 units**, scored via a per-field-type cost table (scalar=1, object=2, list=10+1×requested-item-count, requested-item-count capped at 100). Implemented as a real, pure, tested TypeScript function — `server/policies/graphql-complexity.ts`'s `scoreQueryComplexity()`/`checkQueryDepth()` — operating on a minimal field-selection tree shape (`{ name, args?, children? }`) any real GraphQL execution layer's parsed AST can be mapped onto, rather than depending on a `graphql` npm package this repository does not yet install (no live GraphQL server exists anywhere in this repository yet, `08_*.md` line 11's own "zero GraphQL schema" disclosure) — proven directly against representative shallow/deep/wide/paginated query shapes in `server/policies/graphql-complexity.test.ts`, not merely asserted.

## Evidence

- `docs/architecture/08_API_INTEGRATION_WORKSTREAM.md` §5 ("GraphQL-specific controls," depth/complexity/persisted-operations/batching/field-auth/introspection/subscriptions), §12 (performance budgets, the 500ms common-query threshold this budget is reasoned from), §14 (`ADR-CAND-ARCH-017`'s exact question/recommendation), §15 line 244 (the atomic-backlog row naming this exact resolution point).
- `docs/adr/README.md` §5.2 — `ADR-CAND-ARCH-017` previously `BLOCKED` ("needs enforcement surface"), now this checkpoint's own enforcement surface.
- `docs/architecture/06_RLS_RBAC_WORKSTREAM.md` §3 — the 8-stage evaluation flow, stage 5 of which (`08_*.md` §5's "Field-level authorization") this checkpoint's `server/policies/api-request-context.ts` composes for both REST and GraphQL identically, so a masked field's complexity cost is scored the same regardless of which interface requested it.

## Consequences

- **API:** `scoreQueryComplexity()`/`checkQueryDepth()` reject an over-budget/over-deep query with a real, typed error shape (this checkpoint's own `ApiErrorSchema`) before any resolver would run — proven for a shallow query (passes), a query at exactly the depth ceiling (passes), a query one level past it (rejected), a wide paginated list requesting the maximum page size nested inside another list (rejected on complexity), and a query requesting the maximum allowed page size at the boundary (passes).
- **Performance:** these limits are the concrete, testable answer to `08_*.md` §5's "GraphQL-side counterpart to REST's explicit filter allowlist" — proven to reject the abuse shape (unbounded nested lists) without needing a live server or real tenant data to demonstrate it.
- **Security:** closes the introspection-driven/adversarial-query-shape risk class `08_*.md` §5 names, independent of and prior to this checkpoint's separate persisted-operation-registry sub-question (still open, below).
- **Migration/rollback:** additive — no prior GraphQL complexity mechanism exists anywhere in this repository to migrate away from.
- **Downstream impact / what remains open:** `ADR-CAND-ARCH-017`'s persisted-operation-registration-mechanism sub-question (`08_*.md` §5's "persisted-query allowlist... query hash → registered query text") is **not** resolved by this ADR — no live GraphQL server exists yet to register a persisted operation against (the "GraphQL foundation" atomic-backlog slice, `08_*.md` line 244, a later task than this one). Resolver-batching (DataLoader-equivalent) and introspection environment-gating are likewise real requirements this ADR does not implement, since both require an actual GraphQL execution runtime this repository does not yet have.

## Propagation

Referenced by: `docs/build-log/phase-01/PLT-130.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-017` partially `ACCEPTED` — depth/complexity numeric limits only) and §6 (index). Does not alter any CPD/RPD or any other `docs/architecture/**` decision.
