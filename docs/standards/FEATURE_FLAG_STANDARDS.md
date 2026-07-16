# CargoGrid Feature Flag Foundation

**Established by:** `CG-S5-PH0-019` (Prompt 98 — Feature Flag Foundation)
**Status:** Active — a real, tested, deterministic evaluation engine exists today (`scripts/feature-flags/flags.ts`). **No `feature_flags` table, admin UI, or CI-wired repository check exists** — `05_DATABASE_SCHEMA_WORKSTREAM.md` §4 places `feature_flags` in the Phase 1 "Platform API/job/flag/spatial core" migration wave (no database exists yet, Phase 0 greenfield); no real flag is defined for a real feature yet, so — unlike `scripts/security/check-secrets.ts`/`scripts/docs/check-doc-links.ts`/`scripts/data-classification/check-registry.ts` — there is no real repository content for a CI-wired checker to validate against today (disclosed difference from this build's established pattern, not an oversight, §6).

This document distills `docs/architecture/11_DEVOPS_WORKSTREAM.md` §9.2 (Tech Arch §27.4's 8-dimension capability set, already `VERIFIED`) and `docs/architecture/12_RELEASE_TRAIN.md` §6 (internal progressive-exposure sequencing) — not re-derived — plus `01_MODULE_DEPENDENCY_MAP.md`'s `DUP-012` ("flags never bypass security"), the standing rule every design decision below is checked against.

## 1. The 8 targeting dimensions (Tech Arch §27.4, reproduced verbatim)

Tenant, module, feature, environment, role/user cohort, rollout percentage, effective date, rollback. `scripts/feature-flags/flags.ts`'s `FlagDefinition` type has one field per dimension — no dimension is dropped, and no ninth is added without extending `11_*.md` §9.2 first (the same "fixed catalogue, extend the source before the implementation" discipline `OBSERVABILITY_STANDARDS.md` §1 already applies to its own fixed dashboard/alert catalogue).

## 2. Deterministic evaluation precedence (this checkpoint's own construction, disclosed)

Neither `11_*.md` §9.2 nor `12_*.md` §6 names an explicit order when multiple dimensions could independently decide an evaluation (e.g. a tenant is both on the explicit deny-list *and* within the rollout percentage). This document fixes that order, most-authoritative first — a genuine construction, not a quotation:

1. **Kill switch** (`killSwitch: true`) — always `false`, unconditionally. This is the "rollback" dimension (§9.2's 8th item) and the mechanism `12_RELEASE_TRAIN.md` §7/`11_*.md` §4.4's "Feature (feature flag disable)" rollback row actually triggers — it must be able to override every other rule with no exception, or it is not a real kill switch.
2. **Environment gate** — if the current environment is not in `flag.environments`, `false`. A flag never accidentally reaches an environment it was not enabled for, regardless of tenant/cohort/rollout state.
3. **Effective-date window** — outside `[effectiveFrom, effectiveUntil]`, `false`. An expired or not-yet-started flag behaves identically to a disabled one.
4. **Explicit tenant override** — `tenantDenyList` wins over `tenantAllowList` wins over cohort/rollout (an explicit "never for this tenant" or "always for this tenant" decision is a deliberate operator action and outranks a statistical rollout).
5. **Cohort match** — if `flag.cohorts` is non-empty and the evaluation context's cohorts share no member with it, `false`.
6. **Rollout percentage** — a deterministic bucket (§3) below `flag.rolloutPercentage` → `true`, else `false`.
7. **Default** — `false` if nothing above resolved the decision (fail-closed, not fail-open — an unrecognized/unhandled state never silently grants exposure).

## 3. Deterministic rollout bucketing (not random)

`bucketFor(tenantId, flagId)` hashes `tenantId + flagId` (`node:crypto`, SHA-256, first 4 bytes as an unsigned integer mod 100) into a stable `[0, 100)` bucket — the same tenant always lands in the same bucket for the same flag, so a rollout is reproducible and auditable (Prompt 98 §25: "deterministic... semantics"), unlike `Math.random()`, which would make a given tenant's exposure state unpredictable across evaluations within the same rollout percentage.

## 4. Unknown flag, stale cache, and unavailable-provider behavior (§22/§23, binding)

- **Unknown flag:** `evaluateWithFallback()` returns `{ enabled: <caller-supplied safe default>, unknown: true, degraded: false }` for a flag ID with no matching `FlagDefinition` — never throws, never silently defaults to `true` (fail-closed).
- **Provider/registry unavailable:** the same function, called with `flags: undefined`, returns `{ enabled: <safe default>, unknown: true, degraded: true }` — `degraded: true` is the caller's signal to log/alert (via `scripts/observability/logger.ts`'s `event: "flag.evaluation_degraded"`, Phase 1 wiring) without blocking the product flow the flag gates (the identical safe-degrade discipline `scripts/observability/logger.ts`/`scripts/product-analytics/analytics.ts` already proved for their own signal types).
- **Invalid definition:** `validateFlagRegistry()` rejects a `rolloutPercentage` outside `[0, 100]`, an `effectiveFrom` after `effectiveUntil`, a missing `owner`, and a duplicate flag `id` — an invalid definition never reaches `evaluate()` in the first place (validated at registry-load time, not per-evaluation).

## 5. Cache and invalidation

`FlagCache` (`scripts/feature-flags/flags.ts`) is a bounded, TTL-based in-memory cache keyed by flag ID — `get()` returns `undefined` (a cache miss, triggering a fresh evaluation) once an entry's age exceeds its TTL, so a stale flag state is never served past its own declared freshness window (§23: "stale cache fails safely" — safely here means "expires and re-evaluates," not "silently serves indefinitely"). Real distributed invalidation (a config-version bump propagating across server instances) is Phase 1 scope, once `07_CONFIGURATION_ENGINE_WORKSTREAM.md`'s `config_versions` mechanism exists to drive it — `FlagCache`'s single-process TTL model is the correct foundation shape that mechanism wraps, not a placeholder with different semantics (the same "real foundation, not a placeholder" discipline `Deduplicator`/`pseudonymizeId` already established in `scripts/product-analytics/analytics.ts`).

## 6. Security invariant (`DUP-012`, restated verbatim — the one rule every other section is checked against)

"Flags never bypass security" — a flag controls *whether* a code path is reachable, never *whether* the 8-stage evaluation flow (`06_RLS_RBAC_WORKSTREAM.md` §3) or any RLS/RBAC/audit control runs once that path is reached. Concretely, `evaluate()`/`evaluateWithFallback()` take no authorization decision as input and return no authorization decision as output — they return only `boolean`/`unknown`/`degraded`, never a permission grant, and nothing in `scripts/feature-flags/flags.ts` reads or writes any RLS/RBAC/session state. This is a structural guarantee (the module has no import path to anything authorization-related), not merely a documented promise.

## 7. What is `NOT_RUN` yet (named, not silently skipped)

| Item | Why not real yet | Owning future task |
|---|---|---|
| `feature_flags` persistence table | No database exists (`05_DATABASE_SCHEMA_WORKSTREAM.md` §4, Phase 1 migration wave) | Phase 1 Platform Core |
| Admin management UI | No UI exists; Prompt 98 §15 forbids one "unless later authorized" | Phase 1+, if/when authorized |
| Distributed cache invalidation | No `config_versions` mechanism is wired yet | Phase 1, `07_CONFIGURATION_ENGINE_WORKSTREAM.md` |
| Real flag definitions for a real feature | No feature exists to flag yet | Each Phase 1+ capability prompt that ships behind a flag, per `12_RELEASE_TRAIN.md` §6 |
| CI-wired repository checker (the pattern `check-secrets.ts`/`check-doc-links.ts`/`check-registry.ts` established) | No real flag registry content exists yet to validate — a checker with nothing real to check would be the same "fabricated gate" anti-pattern `PH0-88.md` §3 already rejected | Added once Phase 1's first real `FlagDefinition` exists |
| `docs/runbooks/deployment-rollback.md` (feature-flag-disable row) | Not yet authored — `11_DEVOPS_WORKSTREAM.md` §8.5's 9-runbook catalogue already names it; this checkpoint does not invent a second, competing flag-specific runbook | Phase 0/1 DevOps environment task (`11_*.md` §11's "Deployment pipeline + rollback runbooks" backlog slice) |

## 8. Test evidence this checkpoint

`scripts/feature-flags/flags.test.ts` proves: (1) the kill switch overrides every other dimension, including a 100% rollout; (2) environment/effective-date/tenant-override/cohort gates each independently reject and accept correctly; (3) rollout bucketing is deterministic (same tenant+flag always buckets identically across repeated calls) and roughly uniform across many synthetic tenant IDs (a statistical sanity check, not a cryptographic proof); (4) `evaluateWithFallback()` never throws for an unknown flag or an unavailable registry, and correctly sets `unknown`/`degraded`; (5) `validateFlagRegistry()` rejects each of the four named invalid-definition classes; (6) `FlagCache` expires an entry past its TTL and serves a fresh miss, never a stale hit.
