# CargoGrid Security Baseline

**Established by:** `CG-S5-PH0-015` (Prompt 94 — Security Baseline Controls)
**Status:** Active — the controls buildable before `app/`/`server`/database exist are implemented and tested; every control that needs a real request/session/upload/route surface is fixed as a contract and explicitly `NOT_RUN` (§6), never fabricated as enforced. Closes the "Prompts 94–96" remediation this checkpoint's own source finding named (`docs/discovery/06_SECURITY_BASELINE.md` `SEC-2026-001`).

This document distills `docs/architecture/11_DEVOPS_WORKSTREAM.md` §5 (secrets), `08_API_INTEGRATION_WORKSTREAM.md` (input/error/auth patterns), `06_RLS_RBAC_WORKSTREAM.md` (RLS/RBAC — already fully specified, not re-derived), and `docs/discovery/06_SECURITY_BASELINE.md` (the Step 2 audit that raised `SEC-2026-001`) against what is actually buildable today, plus `ADR-0010` (this checkpoint).

## 1. Threat/control mapping (Prompt 94 §20 task 1/4)

| Control family | `SEC-2026-001` sub-area (`06_SECURITY_BASELINE.md`) | This checkpoint | Real subject exists? | Owner |
|---|---|---|---|---|
| Secret scanning | §6 (secrets/supply-chain) | `scripts/security/check-secrets.ts`, wired into CI | Yes — scans this repository's actual tracked files today | This checkpoint |
| Secret storage/rotation mechanism | §6, `11_*.md` §5 | `ADR-0010` (Vercel env vars + Supabase project secrets) | Yes — the mechanism decision is real; no secret value exists yet to store | This checkpoint |
| Dependency/supply-chain audit | §6, `03_*.md` §7 | Attempted, found genuinely broken upstream (§5 below) | Partially — real finding, no working automated gate yet | This checkpoint (disclosed), re-attempt owner: DevEx |
| Security headers (CSP/HSTS/X-Frame-Options/etc.) | §8 | Contract fixed (§4) | No — no HTTP response exists to attach a header to | Phase 1, first `app/` route |
| CORS/CSRF | §8 | Contract fixed (§4) | No — no API route/form exists | Phase 1 |
| Input validation | §7 | Already fixed by `08_*.md`/`CODING_STANDARDS.md` §8 (Zod-or-equivalent at every mutation boundary) — restated by reference, not re-derived | No — no mutation boundary exists yet | Phase 1 |
| Session/token/MFA | §3 | Contract restated by reference (`11_*.md`, RPD-023) | No — no auth exists | Phase 1 Platform Core |
| Upload/malware-scan | §8 | Contract restated by reference (`08_*.md` §10.2, already `VERIFIED`) | No — no upload path exists | Phase 1 |
| RLS/RBAC/IDOR/tenant isolation | §4 | Already fully specified (`06_RLS_RBAC_WORKSTREAM.md`, `VERIFIED`) — restated by reference | No — no schema/policy exists yet | Phase 1 Platform Core |
| Incident/rotation runbook | §9 | `docs/runbooks/secret-leak-incident-response.md` (this checkpoint) | Partially — real procedure, `NOT_YET_REHEARSED` against a live incident | This checkpoint |

**No control above is claimed complete beyond its own evidence** (Prompt 94 §25 validation rule) — every "No" in the "Real subject exists?" column is a residual, explicitly Phase-1-owned item, not a Phase 0 defect (matches `06_SECURITY_BASELINE.md`'s own framing: "a coverage gap by construction, not a defect ... until Phase 0/Platform Core ships without these controls").

## 2. Secret handling and rotation (`ADR-0010`, `11_*.md` §5 — reproduced, not re-derived)

- Service-role key never reaches the browser; only the publishable key crosses the Browser→Next.js boundary.
- Secrets live in Vercel Environment Variables / Supabase project secrets (`ADR-0010`), never in source code — enforced today by `scripts/security/check-secrets.ts` (§3) and the root `.gitignore` (`ISS-2026-003`, `RESOLVED` at `PH0-85`).
- Webhook secrets are hashed/masked at rest; API keys are shown exactly once at creation, never retrievable afterward (Phase 1, `08_*.md` §6/§7.3 — restated, not altered).
- **Rotation with overlap window:** a rotated key keeps its prior value valid for a fixed period so an integration does not break the instant rotation completes; a revoked (non-rotated) key fails immediately with no propagation delay. Restated as the binding procedure `docs/runbooks/secret-leak-incident-response.md` (this checkpoint) follows for the one case that needs it *now*: a secret accidentally committed to this repository.
- **Leakage prevention:** no secret/API-key/webhook-signature value ever appears in a log line (`scripts/observability/logger.ts`'s `redact()`, `PH0-93`), error response, CI artifact, or exported report — this checkpoint's own `scripts/security/check-secrets.ts` additionally never prints a matched secret's literal value in its own output (§3 — redacts its own findings, closing the "the scanner itself leaks what it found" hazard).

## 3. Secret scanning (this checkpoint, real and enforced)

`scripts/security/check-secrets.ts` (`pnpm run security:check`, wired into CI) scans every tracked file for five well-known secret shapes — chosen because each has a distinctive, low-false-positive-risk pattern, not a generic entropy heuristic that would flag this repository's own legitimate high-entropy content (lockfile integrity hashes, UUIDs, fingerprints):

| Kind | Pattern basis | Example real-world source |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIA` + 16 uppercase alphanumeric | AWS IAM access key |
| `PRIVATE_KEY_BLOCK` | PEM `-----BEGIN ... PRIVATE KEY-----` header | TLS/SSH/signing private key |
| `STRIPE_LIVE_KEY` | `sk_live_` + 16+ alphanumeric | Stripe live secret key |
| `JWT_SHAPED_TOKEN` | three base64url segments joined by `.`, starting `eyJ` | Supabase service-role/anon key, any JWT — a real disclosed limitation: this shape cannot distinguish a sensitive service-role JWT from a safe-to-expose anon-key JWT lexically (§6) |
| `GENERIC_HARDCODED_SECRET_ASSIGNMENT` | a suspicious key name (`secret`/`password`/`token`/`api[_-]?key`/`private[_-]?key`) literally assigned a ≥20-character quoted string | any hardcoded credential |

Every finding is reported as `file:line [kind]` only — the actual matched value is never printed, even redacted-partial (matches §2's leakage-prevention rule applied reflexively to the scanner itself). The scanner's own source and test file are excluded from the repository-wide scan (they intentionally contain matching fixtures to prove detection works — same self-referential-exclusion precedent `scripts/standards/check-suppressions.ts` already established for itself, `PH0-89.md` §5).

## 4. Security headers, CORS, CSRF (contract fixed now, wired Phase 1 — `NOT_RUN`)

Reproduces Tech Arch's security-header/CORS baseline by reference (no `VERIFIED` architecture document currently spells out an exact header-value table — this is itself a disclosed gap, not fabricated): once `app/` exists, Phase 1's `middleware.ts`/route handlers must set `Content-Security-Policy`, `X-Frame-Options: DENY` (or CSP `frame-ancestors 'none'`), `X-Content-Type-Options: nosniff`, `Strict-Transport-Security`, and a `Referrer-Policy`, and every mutation-capable route must enforce same-origin/CSRF-token verification for cookie-authenticated requests (REST/GraphQL mutations reachable only via `Authorization` bearer tokens are not cookie-CSRF-vulnerable by construction, but Server Actions and cookie-session-based routes are, per Next.js's own CSRF guidance) — exact values/exceptions are an `ADR_REQUIRED` item for whichever Phase 1 prompt first wires `middleware.ts`, not invented here.

## 5. Dependency/supply-chain audit (attempted this checkpoint — real finding, not fabricated)

`pnpm audit` was run against this repository's real, current lockfile (`pnpm-lock.yaml`) this checkpoint and failed with a genuine upstream error, not a local misconfiguration: pnpm `10.33.0`'s audit command calls npm's classic advisory endpoints (`registry.npmjs.org/-/npm/v1/security/audits[/quick]`), both of which now respond `410 Gone` — "This endpoint is being retired. Use the bulk advisory endpoint instead" (verified directly this checkpoint, exact error text captured). `npm audit` was also attempted as a fallback and requires a `package-lock.json`, which this repository deliberately does not carry (`ADR-0002`'s single-lockfile decision) — generating one solely to audit would introduce a second, non-authoritative lockfile, a worse outcome than the gap itself. **Decision: do not wire `pnpm audit` into a blocking CI gate at this pnpm version** — either it would fail every future PR for a reason unrelated to real vulnerabilities (the endpoint, not the dependencies, is broken), or running it with `--ignore-registry-errors` would silently no-op and present a fabricated "audited, clean" signal, exactly the "gate with no real subject" anti-pattern `docs/build-log/phase-00/PH0-88.md` §3 already established this repository never does. Recorded as `ISS-2026-007` (`docs/runtime/KNOWN_ISSUES.md`) — re-attempt owner: DevEx, once pnpm ships bulk-endpoint support (pnpm `11.13.1` is currently available upstream but upgrading the pinned major version is out of this task's scope, Prompt 94 §12's "no broad dependency upgrade").

## 6. Residual risks and disclosed limitations (Prompt 94 §25 — explicit, not falsely complete)

- **RPD-022 (Supreme Admin absolute CRUD, restated verbatim):** Supreme Admin may alter or delete any record, including audit, journal, payment, and final records — CargoGrid must never claim immutable/tamper-proof records; this is a ratified, accepted governance risk, not a defect this or any checkpoint can "fix." Disclosed here per Prompt 94 §24's binding rule, matching every prior disclosure of this exact fact (`AGENTS.md`, `docs/standards/DESIGN_SYSTEM.md` §6 is not applicable here but the pattern is consistent).
- **RPD-023 (MFA mandatory for privileged roles, restated verbatim):** Supreme Admin, tenant admin, finance approver, and credential manager must enroll — not implementable until auth exists (Phase 1), tracked as a hard requirement on that phase's auth implementation, not optional.
- **`JWT_SHAPED_TOKEN` cannot distinguish sensitive vs. safe-to-expose JWTs** (§3) — accepted as a deliberately conservative false-positive-tolerant design (flagging a safe anon-key JWT for human review costs little; missing a real service-role leak costs everything).
- **Dependency audit gap** (§5) — `ISS-2026-007`, `OPEN`, tracked with a named re-attempt condition, not silently dropped.
- **Every `NOT_RUN` row in §1** — real Phase 1 residuals, each with a named owner, none silently assumed already covered.
