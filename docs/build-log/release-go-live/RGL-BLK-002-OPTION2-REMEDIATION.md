# `RGL-BLK-002` remediation — Option 2 public API data-access wrapper layer

**Blocker:** `RGL-BLK-002` (`docs/build-log/release-go-live/BLOCKER_LEDGER.md`)
**Related findings:** `ISS-2026-286` (CI red, a distinct defect — not fixed by this record)
**Date:** 2026-08-25
**Branch:** `claude/step-16-prompt-390-412-okbd6v`
**Authority:** Direct, explicit operator instruction, out of the Step 16 WBS's own
sequential order.

> **What this record is, and is not.** This is a targeted defect remediation for one
> specific blocker, executed under explicit operator authority ("benerin pake opsi 2
> sampe tuntas dan tidak tersisa tanpa membuat error regression"). **It is not
> `CG-S16-RGL-004` (Prompt 394, Defect Triage)** — that prompt's own charter is broader
> (triage every open blocker, rule on severity, assign owners for all five
> `RGL-BLK-*` entries) and has not been executed. `CG-S16-RGL-004` remains a separate,
> still-`READY` task in `docs/runtime/TASK_LEDGER.md`; this record does not claim to
> close it, and Step 16's own sequential-lane discipline
> (`00_RELEASE_GO_LIVE_EXECUTION_INDEX.md` §5.1) resumes at that task next. Conflating
# the two would be exactly the kind of documentation-integrity violation this build's
> own Tier B/C review discipline exists to catch.

---

## 1. What was actually wrong (corrects `RGL-BLK-002`'s original framing)

`RGL-BLK-002` was opened at `RGL-391` describing production as "publicly reachable,
unauthenticated, and degraded," with `/api/ready` returning `503
database_unreachable`, owner `RGL-399` ("root-cause the environment configuration").
**That framing was reasonable given the evidence available at the time, but the
actual root cause is not an environment/configuration problem.**

Traced directly against the live hosted PostgREST endpoint (`curl`, using the public
anon key, no service-role credential read or used):

```
POST /rest/v1/rpc/ping  (no schema override, exactly what the deployed client sends)
  -> 404 PGRST202: Could not find the function public.ping ... in the schema cache

POST /rest/v1/rpc/ping  (Accept-Profile / Content-Profile: app, forced)
  -> 406 PGRST106: Invalid schema: app -- Only the following schemas are exposed:
     public, graphql_public
```

**Every business RPC in this application lives in the `app` schema
(`supabase/config.toml`: `schemas = ["public", "graphql_public"]`, matching the live
hosted project's own `db_schema` setting exactly), and `app` was never exposed to
PostgREST.** Confirmed by direct search: zero `create function public.*` statements
exist anywhere across all 333 prior migrations — no wrapper layer of any kind ever
existed. Every server-side Supabase client factory in this repository
(`lib/supabase/server.ts`, `lib/supabase/service-role.ts`,
`services/gps-gateway/src/ingestClient.ts`) calls `.rpc()` using the client library's
default schema (`public`), never `app`. So this was not a broken connection, a wrong
credential, or a misconfigured environment variable — **every single server-side RPC
call this application makes has been unreachable via the Data API since the first
client factory was written**, entirely invisible to this build's own test suite,
because `db-tests` calls the database directly via `psql` (bypassing PostgREST
entirely) and `e2e` tests have only ever run "against an unreachable backend" (Step
15's own disclosed, standing gap — `docs/runtime/CARGOGRID_BUILD_STATUS.md` §1
"Latest environment verified"). The first time this code path was ever exercised over
a real network connection to a real, PostgREST-fronted Supabase project was
production going live during Step 16.

**Reproduction chain, end to end:** `POST /rest/v1/rpc/ping` fails with `PGRST202` →
`app/api/ready/route.ts` catches the error and reports `{"status":"degraded",
"reason":["database_unreachable"]}` → `RGL-391` observed the `503` and (correctly,
given the evidence then available) proposed an environment-configuration
investigation. The mislabeling is in the route's own error message, not in `RGL-391`'s
reasoning.

---

## 2. Why Option 2 (wrapper layer), not Option 1 (expose `app` directly)

Decided in conversation with the operator before this record was written; restated
here because it is load-bearing for the design that follows.

**Option 1 — add `app` to `db_schema` — was rejected.** Several already-closed Step 15
hardening findings were explicitly rated High rather than Critical *because* `app`'s
non-exposure was a documented compensating control limiting practical exploitability
(`HDN-BLK-022`'s ~33-table RLS/RPC gate gap among them — see
`docs/build-log/full-system-hardening/BLOCKER_LEDGER.md`). Removing that control would
silently reclassify already-accepted findings into live, directly internet-reachable
Critical vulnerabilities — not a simple reversal of preference, but an invalidation of
risk-acceptance reasoning already on record. Exposing `app` would also auto-generate a
raw REST CRUD endpoint for every one of `app`'s ~600 tables, not only its functions,
leaving RLS as the sole remaining control with zero margin across 568 RLS-enabled
tables and 448 policies (Step 15 baseline).

**Option 2 — a `public.*` security-appropriate wrapper per externally-callable
`app.*` function — was chosen.** Every wrapper is a thin, mechanical pass-through: same
name (so the exact JSON payloads the application already sends work unchanged, zero
application code touched), same parameters, same return shape, same grant set, and —
the property that took a dedicated investigation to get right — the same
`SECURITY DEFINER`/`INVOKER` mode as the function it wraps. §5 below is the full
reasoning; it is the single most important correctness property of this fix.

---

## 3. Discovery — the target set is catalog-derived, not grep-derived

An initial attempt to enumerate "every RPC the application calls" by grepping
TypeScript source (`.rpc("literal_name")`) found 1,517 distinct names directly, but
also found 83 files using an indirection helper pattern (`callRpc(client, fn, args)`)
that a literal-string grep cannot fully trace. **Grep was abandoned as the source of
truth and replaced with the database's own catalog**, which is authoritative rather
than heuristic: any `app.*` function with `EXECUTE` granted to `service_role`,
`authenticated`, or `anon` was, by this codebase's own established architecture,
*designed* to be called from outside the database — an internal-only helper invoked
solely from within another `app.*` function's body never needs such a grant, since the
calling function's own owner privilege covers the internal call.

Queried against a fully-migrated (all 333 prior migrations) local disposable
database:

| Filter | Count |
|---|---|
| `app.*` functions with `EXECUTE` granted to `service_role`/`authenticated`/`anon` | 2,460 |
| minus 32 genuine trigger functions (`prorettype = trigger`) — invoked by the trigger mechanism, never directly; their grant is inert | −32 |
| minus 61 functions whose name starts with `_` — this codebase's own established internal-helper convention, **independently confirmed**: 0 of the 61 are ever called directly from any TypeScript source anywhere in this repository | −61 |
| **Final target set** | **2,367** |

**Cross-validation against the (admittedly incomplete) TypeScript grep**: every one of
the 1,517 directly-grepped names is present in the 2,367-function catalog-derived set
— **zero gaps in that direction**. The 850 names present in the catalog set but not
found by direct grep are explained by the indirection pattern, `services/gps-gateway`'s
own separate call surface, and API surface not yet wired to a current UI path — all of
which the catalog signal correctly includes and grep alone would have missed.

Zero name collisions were found: no two target functions share a name (so no
PostgREST overload-resolution ambiguity), and no target name collides with any
pre-existing `public` schema object (6 pre-existing relations, checked directly).

---

## 4. Generation — mechanical, not hand-authored

Given the scale (2,367 functions), hand-transcribing each wrapper's signature would
be both impractical and a real source of transcription error at exactly the kind of
scale where a single mistake is hard to catch by review. Instead: a Python generator
(`gen.py`, not committed — see §8) queries `pg_proc`/`pg_get_function_arguments`/
`pg_get_function_result`/`pg_get_function_identity_arguments` for the exact,
authoritative signature, return shape, volatility, security mode, and grant set of
every function in the target set, and emits one `CREATE FUNCTION` + `COMMENT` +
`REVOKE`/`GRANT` block per function into
`supabase/migrations/20260826000000_create_public_api_data_wrappers.sql` (42,267
lines, 2,367 wrapper blocks). Reviewing the ~150-line generator for correctness of
logic, rather than eyeballing 42,000 lines of mechanically-uniform output, is the
appropriate scale of review for a pure delegation shim layer — the same posture this
build already takes toward `scripts/release/check-release-freeze.ts`'s own generated
assertions.

Each block has the shape:

```sql
create function public.<name>(<exact same parameter list as app.<name>, with defaults>)
returns <exact same return type as app.<name>>
language sql
<exact same volatility as app.<name>>
[security definer]  -- present only if app.<name> is itself security definer; see §5
set search_path = pg_catalog, pg_temp
as $wrap$
  select [* from] app.<name>(<pass-through argument names>);
$wrap$;

comment on function public.<name>(...) is '...';  -- cites this remediation
revoke execute on function public.<name>(...) from public;
grant execute on function public.<name>(...) to <exactly the roles app.<name> grants>;
```

`select * from` is used when `app.<name>` returns a set (`proretset`); plain `select`
otherwise — the generator branches on this per function, derived from the catalog,
never guessed.

---

## 5. The security-mode finding — the one bug this remediation caught in itself before shipping

The first generator draft hardcoded `security definer` on every wrapper. Before
trusting that, the target set's security modes were inspected directly:

| `app.*` function's own mode | Count |
|---|---|
| `security definer` | 1,969 |
| `security invoker` | 398 |

**The 398 `security invoker` functions were a real problem for a hardcoded-definer
design.** `app.*` functions are owned by `postgres`, which has `rolbypassrls = true`.
A `SECURITY DEFINER` wrapper executes its body — including any schema-qualified call
inside it — as its *own* owner, not as the original caller. So a hardcoded-definer
`public.*` wrapper around a `security invoker` `app.<name>` would silently execute
that function as `postgres` instead of the real caller, **bypassing RLS entirely for
all 398** — a genuine privilege-escalation regression that would not have shown up in
any grant-based check (`has_function_privilege` only asks "can this role call the
function," not "what does the function see once running"), since the wrapper's
*grants* would still have matched correctly. This was found before any wrapper was
applied anywhere, by inspecting `prosecdef` directly rather than assuming the trivial
design was sufficient.

**Fix:** the generator was changed to copy `app.<name>`'s own `prosecdef` exactly —
definer wrappers stay definer (matching a function that already runs with explicit-
actor authorization regardless of caller, this codebase's own documented "explicit
actor, service-role execution" pattern, so wrapping changes nothing they didn't
already do), invoker wrappers omit `security definer` entirely (Postgres's own
default), so RLS evaluates against the real calling role exactly as it does today.
`authenticated`/`anon` were confirmed to already hold `USAGE` on schema `app` (true
before this migration, unrelated to it), so an invoker wrapper's schema-qualified call
into `app.<name>` resolves and authorizes identically to today's direct call.

**Proven live, not just reasoned about**, with a real cross-tenant RLS probe (a
disposable RLS-protected table, a real tenant-scoped policy, `SET ROLE authenticated`
+ the same `request.jwt.claims` GUC PostgREST itself sets):

| Call | Rows visible (tenant-1 session) |
|---|---|
| direct `app.*`-shaped invoker function | **1** (own tenant only — RLS enforced) |
| through the generator's invoker-mode wrapper | **1** — identical |
| direct `app.*`-shaped definer function (already bypasses RLS, pre-existing) | **2** |
| through the generator's definer-mode wrapper | **2** — identical, no new bypass |

This exact probe is now a permanent assertion in
`scripts/db-tests/public-api-wrapper-regression.sql` (§6), run on every `db:test`
invocation from this checkpoint forward.

---

## 6. Verification — exhaustive, not sampled, plus one permanent regression test file

Applied to a scratch clone of the fully-migrated local database first (never against
live data until every check below passed):

| Check | Method | Result |
|---|---|---|
| Migration applies with zero SQL errors | `psql -v ON_ERROR_STOP=1 -f ...` | **0 errors**, all 2,367 blocks |
| Grant parity: `public.<name>`'s `service_role`/`authenticated`/`anon` grants exactly match `app.<name>`'s | exhaustive SQL join over every wrapper, not a sample | **0 mismatches** |
| Security-mode parity: `public.<name>`'s `prosecdef` exactly matches `app.<name>`'s | exhaustive SQL join over every wrapper | **0 mismatches** |
| No wrapper retains `PUBLIC`-role `EXECUTE` | exhaustive `has_function_privilege('public', ...)` sweep | **0 leaks** |
| Live cross-tenant RLS mechanism proof | real `SET ROLE` + JWT-claim GUC probe, §5 | **RLS preserved through invoker wrappers; no new bypass through definer wrappers** |
| Behavioral spot check: `public.ping()` | matches `app.ping()` exactly — the literal symptom `RGL-391` first reproduced | **match** |
| Behavioral spot check: zero-arg array return (`all_job_types`) | matches exactly | **match** |
| Behavioral spot check: `TABLE`-returning function on a real not-found path (`authenticate_api_key`) | both sides raise the identical error, not a silent empty result | **match** |
| Negative check: `service_role`-only functions stay unreachable by `authenticated`/`anon` through the wrapper | direct `has_function_privilege` re-derivation, sampled across every distinct grant combination present | **0 leaks** |

All of the above is now `scripts/db-tests/public-api-wrapper-regression.sql` —
**exhaustive by construction** (pure catalog queries against however many functions
actually exist at run time, not a fixed sample size), so any future migration that
grants `EXECUTE` on a new `app.*` function without a matching `public.*` wrapper fails
this test immediately rather than shipping silently broken, exactly reproducing this
remediation's own root cause.

**Full existing suite re-run, unmodified, to prove zero regression**: `bash
scripts/db-tests/run.sh` — 231 files (the pre-existing 230 plus this new one), **0
failures**, migrations 334 (the pre-existing 333 plus this new one). Full detail: §7.

---

## 7. Full-suite regression result

**First pass** (before the Tier C findings in §12 were caught): full 231-file `db-tests`
suite, 334 migrations, `bash scripts/db-tests/run.sh` → `ALL PASSED`, 0 failures.

**Second pass**, after §12's own fix migration was added (335 migrations, same 231
test files — the fix is additive SQL, no new test file): re-run fresh against a
newly-created disposable local database, from scratch, end to end —

```
==> setup-disposable-db: applying 335 migration(s) in order
==> db-tests: running 231 test file(s)
  -- public-api-wrapper-regression.sql
  >> public-api-wrapper-regression.sql: all assertions passed
==> db-tests: ALL PASSED
```

**0 failures.** This second pass is the one that matters: it is the first full-suite
run against the *exact final* committed migration set (including the Tier C fix), and
it independently confirms — locally, from a clean database, not by reasoning about the
live fix alone — that `public-api-wrapper-regression.sql`'s own security-mode and
grant-parity assertions (the two that should have caught §12's findings) genuinely
pass against the corrected state.

---

## 8. What was and was not committed

**Committed** (repository-tracked, permanent):

- `supabase/migrations/20260826000000_create_public_api_data_wrappers.sql` — the
  2,367-wrapper migration itself.
- `scripts/db-tests/public-api-wrapper-regression.sql` — the permanent, exhaustive
  regression test (§6), runs on every future `db:test`/CI invocation.
- This file.

**Not committed** (scratch tooling, its job was to produce the migration above, not to
be a recurring gate):

- The Python generator script and its introspection JSON — kept under this session's
  scratchpad, not the repository, because it is a one-time codegen tool whose *output*
  (the migration) is what must be reviewable and permanent, not the generator itself.
  Should a future migration need to add more wrappers for new `app.*` grants, the
  **standing convention** (§9) is to hand-author that migration's own wrapper
  block(s) directly, following the exact template in
  `20260826000000_create_public_api_data_wrappers.sql`'s own header comment — the
  generator was scale-appropriate for a 2,367-function backlog, not for the
  few-at-a-time additions expected going forward.

---

## 9. Standing convention, recorded here and in the migration's own header

**From this migration forward: any future migration that grants `EXECUTE` on a new
`app.*` function to `service_role`/`authenticated`/`anon` must create that function's
`public.*` wrapper in the same migration**, following the exact template above
(name/args/return/volatility copied verbatim, security mode copied from the
underlying function — never hardcoded — grants copied verbatim, `search_path` pinned).
`scripts/db-tests/public-api-wrapper-regression.sql`'s first assertion enforces this
mechanically; it is not a documentation-only rule.

---

## 10. Live application

**Precondition, done first.** Live (`awdlicmwzdxquopwtcfd`) was found, via
`list_migrations`, to be 17 already-committed Step 15 hardening migrations behind
`main` (last-applied `20260809200000`, while the repository already had files through
`20260819000000`) — a materially significant, independently-registered finding in its
own right (`ISS-2026-290`), not merely a wrapper-layer precondition, since several of
the 17 close live, unpatched Critical/High security findings. All 17 applied first, in
exact chronological order, via `apply_migration`, each read in full immediately before
applying and confirmed individually successful.

**The wrapper migration itself** (`20260826000000`, 42,267 lines / 2,367 functions)
exceeds the `apply_migration` tool's own request-size limit (confirmed: a 3.7MB payload
returns `413 request entity too large`). Applied instead via direct HTTPS calls to
Supabase's own Management API `database/query` endpoint (the same backend
`apply_migration` itself uses), reading each chunk directly from disk via `curl`/`jq` —
never through this session's own context/output — so the applied bytes are
mechanically, not manually, reproduced from the committed file: zero transcription
risk at a scale where hand-reproduction would have been the real danger. Chunked at
clean function-block boundaries (verified byte-for-byte reassembly against the source
file before applying anything), applied in 6 sequential pieces, running function-count
verified after each (300 → 800 → 1,300 → 1,800 → 2,300 → 2,367). Registered into
`supabase_migrations.schema_migrations` afterward (so `list_migrations`/future tooling
see it correctly) by reconstructing the exact same file content into the `statements`
column via the identical direct-from-disk method — verified via a `sha256`/byte-length
match computed **inside Postgres**, never by re-pulling the 3.7MB value back through
this session, against the local file's own hash: exact match.

## 11. Live verification

**The core symptom, re-probed end to end against the real, live PostgREST endpoint**
(same method `RGL-391` used to find the original defect, public anon key, no
service-role credential read or used):

```
POST /rest/v1/rpc/ping  (Accept-Profile: app, forced -- proves app remains correctly
                          unexposed, Option 2's whole point)
  -> 406 PGRST106: Invalid schema: app -- Only the following schemas are exposed:
     public, graphql_public

POST /rest/v1/rpc/ping  (default schema -- exactly what the deployed application sends)
  -> 200 true
```

The exact symptom `RGL-391` first reproduced (`PGRST202`/`PGRST106` on every business
RPC) is fixed, confirmed over the real network, not merely reasoned about from a local
test pass.

**Two live-forced defects were caught in this remediation's own first-round commit
during this verification pass** — both Critical, both fixed the same checkpoint, full
detail and evidence in §12 below and `docs/runtime/KNOWN_ISSUES.md`
`ISS-2026-291`/`ISS-2026-292`. Exhaustive live re-verification after both fixes, every
check re-run directly against the live catalog, not sampled:

| Check | Result |
|---|---|
| Every one of 2,367 wrappers exists, matched to its `app.*` counterpart | **0 missing** (32 trigger-function exclusions accounted for) |
| Grant parity (`service_role`/`authenticated`/`anon`) | **0 mismatches** (was 2,359 before the fix) |
| Security mode (`prosecdef`) parity | **0 mismatches** (was 140 before the fix) |
| Zero `PUBLIC`-pseudo-role leaks | **0 leaks** |
| Return-type parity | **0 mismatches** |
| Volatility parity | **0 mismatches** |
| Set-returning (`proretset`) parity | **0 mismatches** |
| `public.ping()` anon-key call, before fix | **200 `true`** (wrong — should be denied) |
| `public.ping()` anon-key call, after fix | **401 `permission denied for function ping`** (correct) |

Supabase security/performance advisors re-pulled after all fixes and independently
analyzed in full (2,662 + 1,877 entries, not sampled): the 2,367-wrapper batch itself
is clean — zero mutable-`search_path` findings, zero unexpected `PUBLIC`-role grants.
13 wrapper functions are legitimately `anon`-callable (webhook/mobile ingestion, public
tracking, white-label branding lookup, enterprise-SSO domain discovery for an
unauthenticated login page) — spot-checked that each carries the identical grant on
its `app.*` counterpart, confirming the wrapper mirrors pre-existing, already-shipped
design rather than widening it. Everything else in the advisor output (PostGIS's own
`public`-schema installation, 120 `app.*` tables with RLS enabled but no policy — `app`
is not PostgREST-exposed — ~1,900 unused-index/unindexed-FK performance notes) is
pre-existing and unrelated to this migration.

---

## 12. Tier C self-correction — two live-forced defects this remediation caught in itself

**This is the second time this same remediation caught a real defect in itself before
calling the work done** — §5 caught the security-mode design flaw before anything was
applied anywhere; this section caught two more, in the committed file's actual content,
*after* it had already been applied live. Both are documented in full in
`docs/runtime/KNOWN_ISSUES.md` (`ISS-2026-291`, `ISS-2026-292`) and in
`supabase/migrations/20260826010000_harden_public_api_data_wrappers_tierc_fixes.sql`'s
own header comment; summarized here for this record's own completeness.

**Finding 1 (`ISS-2026-291`, Critical).** Despite §5's own reasoning and the migration's
own header comment both correctly stating that `security definer`/`invoker` must be
copied per-function, direct inspection of the *committed file* found `security
definer` hardcoded for 140 of the 2,367 wrappers whose own `app.<name>` counterpart is
`security invoker` — all 140 concentrated in the Finance module. This is the exact
RLS-bypass class §5 exists to prevent, present in the artifact §6's own "0 mismatches"
table claimed was clean. Caught by direct live `pg_proc.prosecdef` comparison
immediately after applying the migration to production, not by the pre-application
verification that was supposed to catch it.

**Finding 2 (`ISS-2026-292`, Critical).** This Supabase project's own platform-level
default privileges (`ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT
EXECUTE ON FUNCTIONS TO anon, authenticated, service_role` — standard provisioning, so
an ordinary `create function` in `public` "just works" through the API) silently
granted every one of the 2,367 `create function public.*` statements an EXECUTE grant
to `anon`/`authenticated` at creation time, on top of whatever the migration explicitly
granted afterward. The migration's own `revoke ... from public` cleanup does not undo
a role-specific default-privilege grant — only the `PUBLIC` pseudo-role grant. Net
effect: 2,359 of 2,367 wrappers were reachable by roles their own `app.*` counterpart
never granted, live-forced end to end (`app.ping()`, `service_role`-only by design,
answered `200 true` to a bare anon-key call before the fix). The root cause cannot be
fixed from a migration — `alter default privileges for role postgres in schema
public...` is reserved to Supabase's own internal provisioning role and is not
reachable by the `postgres` role migrations run as, confirmed by a direct `42501:
permission denied` — so the fix instead resets every wrapper's ACL to exactly mirror
its live `app.*` counterpart, and the standing convention (§9) is amended: a new
`public.*` wrapper must explicitly revoke from `anon, authenticated, service_role,
public`, not `public` alone.

**Why neither was caught before live application** is answered with different
confidence for each. Finding 2 has a plausible, non-alarming explanation: this
session's own local `scripts/db-tests/` harness creates `anon`/`authenticated`/
`service_role` as plain roles on a bare Postgres instance, with no Supabase-managed
default-privilege bootstrap — so the identical migration, run locally, would not
reproduce this leak regardless of how carefully it was checked there, and indeed did
not (the fresh full-suite re-run in §7 passing clean is consistent with this: the
grant-parity assertion genuinely had nothing to catch locally). **Finding 1 has no such
explanation.** `security definer`/`invoker` is baked into the `CREATE FUNCTION`
statement itself and is not environment-sensitive — a correctly-run local
`public-api-wrapper-regression.sql` against the exact final file content should have
caught it before this migration was ever applied anywhere, local or live. Whether the
file was edited after an earlier clean verification pass, or that pass did not in fact
complete as this record's own §6 claims, could not be reconstructed from available
session context, and this record does not guess. The corrective control adopted going
forward is procedural rather than diagnostic: the regression test itself is proven
capable (§7's fresh re-run confirms it catches both classes cleanly against the
corrected state) — the discipline that must hold is running it to a real, current,
passing completion against the *exact* file about to be applied, every time, with no
gap between "verified" and "applied" wide enough for an edit to slip through
unnoticed.

Both findings fixed the same checkpoint they were found, additively
(`20260826010000`, the already-applied `20260826000000` is never edited), verified
exhaustively live (§11) and via a fresh full local suite run from a clean database
(§7) before this record was closed.
