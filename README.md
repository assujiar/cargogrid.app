# CargoGrid

Multi-tenant SaaS ERP for 3PL/logistics operators (forwarding, cargo, trucking, warehouse, distribution, project logistics). See `docs/blueprint/` for the product/business/technical source of truth and `docs/runtime/CARGOGRID_CONTEXT.md` for the current build checkpoint.

**Status:** Phase 0 — Discovery and Foundation. No application code exists yet beyond this toolchain scaffold; feature/business-domain code is not authorized until `PHASE_0_VERIFIED` (see `docs/runtime/HANDOFF.md`).

## Stack

Next.js App Router, React, TypeScript (strict) · Supabase (Auth, PostgreSQL, RLS, Storage) · pnpm · Vercel. See `AGENTS.md` "Stack baseline" for the ratified target and `docs/adr/` for the recorded tooling decisions.

## Local development

### Prerequisites

- Node.js `>=22.11.0` (LTS "Jod" line; this repo pins `22.22.x` in the sandbox that authored it — any 22.11+ patch works).
- [pnpm](https://pnpm.io) `10.33.0` — enable via Corepack: `corepack enable && corepack prepare pnpm@10.33.0 --activate`, or install directly.
- [Docker](https://www.docker.com) — required by the Supabase CLI to run the local stack (Postgres, Auth, Storage, Studio).
- [Supabase CLI](https://supabase.com/docs/guides/cli) — invoked via `npx supabase` below; no global install required.

### One-command-ish setup

```bash
pnpm install                 # installs pinned dependencies from the committed pnpm-lock.yaml
cp .env.example .env.local   # then fill in the values `supabase start` prints below
npx supabase start           # starts local Postgres/Auth/Storage/Studio in Docker
pnpm run preflight           # verifies required env vars are set and correctly scoped to CARGOGRID_ENV
pnpm run typecheck           # tsc --noEmit
pnpm run lint                # eslint .
pnpm test                    # node --test — env schema/cross-field/redaction tests
```

`supabase start` prints an API URL, anon key, and service-role key — copy those into `.env.local` (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`). Never commit `.env.local` (already covered by `.gitignore`) and never paste a production project's keys into it — `pnpm run preflight` (backed by the typed schema in `scripts/env/`) refuses to proceed if `NEXT_PUBLIC_SUPABASE_URL`'s loopback-ness doesn't match `CARGOGRID_ENV`: `local` must point at `127.0.0.1`/`localhost`, every other tier (development/testing/staging/uat/production/sandbox — the seven environments in `docs/architecture/11_DEVOPS_WORKSTREAM.md` §2) must point at its own isolated Supabase project instead. There is no override flag — a local environment must never be pointed at a shared or production project, by design.

**Note on `dev`/`build` scripts:** they are intentionally not defined yet. No `app/` directory exists in this repository — per `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md`'s migration-wave plan, the Next.js application shell lands in Phase 1 (Platform Core), not Phase 0. `typecheck`, `lint`, `test`, and `preflight` are the only scripts meaningful at the current checkpoint; running `next dev`/`next build` today would fail with "no pages or app directory found," which is the expected state, not a defect.

### Environment variables

Every variable this repository consumes is declared, typed, and classified (`public`/`server`/`secret`) in `scripts/env/schema.ts` — that file is the source of truth, `.env.example` is only a convenience copy of its shape. `scripts/env/validate.ts` performs fail-fast, redacted validation (`pnpm run preflight`); error messages always name the failing variable and never its value. See `docs/adr/ADR-0003-environment-schema-validation-library.md` for why Zod was chosen.

### Local database

The Supabase CLI manages a disposable local Postgres instance in Docker — it is never connected to a real tenant's data. `supabase/config.toml` is the tracked project scaffold (Postgres 17, matching the ratified Supabase-managed target). As migrations and seed data are added in later phases:

```bash
npx supabase db reset   # rebuild the local DB from supabase/migrations/ + supabase/seed.sql
npx supabase stop       # stop the local stack when done
```

### Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `pnpm install` fails on an engine check | Node version `<22.11.0` | Install/switch to Node 22 LTS |
| `supabase start` fails to bind a port | Another local Postgres/Supabase instance already running | `npx supabase stop` first, or check for port `54321-54329` conflicts |
| `pnpm run preflight` fails "is required ... but is not set" | `.env.local` not created or incomplete | `cp .env.example .env.local`, fill in values from `supabase start` output |
| `pnpm run preflight` fails "must be a loopback address when CARGOGRID_ENV=local" | `.env.local` was copied from a teammate/staging/production config | Point back at your own local `supabase start` output; `CARGOGRID_ENV=local` always requires a loopback Supabase URL, with no override |
| `pnpm run preflight` fails "requires its own isolated Supabase project" | `CARGOGRID_ENV` is set to a non-`local` tier but `NEXT_PUBLIC_SUPABASE_URL` is still loopback | Set the tier's own provisioned Supabase project URL, or set `CARGOGRID_ENV=local` if you're actually developing locally |
| `pnpm run typecheck` fails on a fresh clone with no code changes | Dependency drift — the lockfile is the source of truth | `pnpm install` (do not `pnpm update`); if it still fails, this is a real regression, file it, don't work around it |

### Recovery

The toolchain files here (`package.json`, `pnpm-lock.yaml`, `tsconfig.json`, `supabase/config.toml`, `.env.example`, `scripts/`) are pure configuration and code — there is no data to lose. To reset: `git checkout -- package.json pnpm-lock.yaml tsconfig.json` and re-run `pnpm install`. See `docs/build-log/phase-00/PH0-85.md` and `PH0-86.md` for the full checkpoint records and rollback notes.
