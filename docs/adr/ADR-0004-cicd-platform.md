# ADR-0004 — CI/CD platform

Status: ACCEPTED
Date: 2026-07-15   Approver: Runtime build agent (Phase 0 governance authority, per `docs/adr/README.md` §3)   Supersedes/Superseded-by: —
Source candidate: `ADR-CAND-ARCH-024` (CI/CD-platform-product component — the package-manager component was already resolved at `ADR-0002`)   Owning phase/task: Phase 0 (`CG-S5-PH0-009`, Prompt 88, CI/CD Baseline)

## Question

`ADR-CAND-ARCH-024` (`docs/architecture/11_DEVOPS_WORKSTREAM.md` §10) calls for "a single CI/CD platform integrated with this repository's Git host," deferring the exact product to Phase 0 evaluation. Which platform?

## Options

1. **GitHub Actions (SELECTED).** Native to this repository's actual Git host.
   - Trade-off: none material — "integrated with this repository's Git host" is `ADR-CAND-ARCH-024`'s own stated criterion, and this repository's host is already GitHub, not a hypothetical choice. Zero additional vendor onboarding, zero new credential surface, workflow files live in the repository itself (`.github/workflows/`) and are reviewed exactly like any other change (§2 of `docs/git/GIT_STRATEGY.md`).
2. **A third-party CI product (CircleCI, GitLab CI, Buildkite, etc.).**
   - Trade-off: every option in this class requires connecting an external service to a GitHub-hosted repository — a second vendor relationship, a second credential/secret surface, and integration friction `ADR-CAND-ARCH-024`'s own text explicitly warns against ("integrated with this repository's Git host," not merely "compatible with").

## Decision

**GitHub Actions.** Workflow file at `.github/workflows/ci.yml`, triggered on `pull_request` (against `main`) and `push` (to `main`), running the deterministic pnpm-based pipeline this task builds (`docs/build-log/phase-00/PH0-88.md` §3–§5).

## Evidence

- `docs/architecture/11_DEVOPS_WORKSTREAM.md` `ADR-CAND-ARCH-024`: "a single CI/CD platform integrated with this repository's Git host."
- This repository's Git host is GitHub — confirmed by direct, successful use of the GitHub API throughout this build (`mcp__github__list_pull_requests`, `mcp__github__list_branches`, `owner=assujiar`, `repo=cargogrid.app`, most recently re-run this checkpoint per `docs/git/GIT_STRATEGY.md` §7's mandatory pre-flight collision check, `docs/build-log/phase-00/PH0-88.md` §2). The local git remote itself points at this sandbox's network proxy (`docs/discovery/01_REPOSITORY_INVENTORY.md` `EV-S2-REPO-006`), so the proxy URL is not used as evidence — the platform-level GitHub API access is.
- `docs/git/GIT_STRATEGY.md` §3 (merge strategy, squash-merge once branch protection exists) and §7 (pre-flight collision check via the GitHub API) already assume GitHub as the host; this ADR makes the CI-platform choice consistent with, not independent of, that existing assumption.

## Consequences

- **DB/API/UI:** none — this task validates existing tooling, it does not add a database/API/UI surface.
- **Security:** the workflow requests `permissions: contents: read` only (least privilege, §26); no secret is defined or required by any current gate (nothing in this repository yet needs one); fork PRs run under GitHub's own default `pull_request`-trigger sandboxing (read-only token, no repository secrets) — `pull_request_target` is deliberately not used (see `docs/build-log/phase-00/PH0-88.md` §4 for the explicit reasoning).
- **Performance:** pnpm store caching keyed by the lockfile hash (via `actions/setup-node`'s built-in cache support) keeps repeat installs fast; not measured as an SLA (§17).
- **Migration/rollback:** trivial — deleting `.github/workflows/ci.yml` fully disables the pipeline with no other repository effect.
- **Downstream impact:** `PH0-089` onward (coding standards, testing foundation, security baseline, etc.) may add further steps/jobs to this same workflow file rather than introducing a second CI entry point — one pipeline, extended, not duplicated (mirrors `docs/git/GIT_STRATEGY.md`'s "one canonical lineage" discipline applied to CI).

## Propagation

Referenced by: `docs/build-log/phase-00/PH0-88.md`; `docs/adr/README.md` §5.2 (marks `ADR-CAND-ARCH-024` fully `ACCEPTED` — both the package-manager component from `ADR-0002` and this platform-product component); `.github/workflows/ci.yml` itself cites this ADR in its header comment. Does not alter any CPD/RPD or any `docs/architecture/**` decision.
