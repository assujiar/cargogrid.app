# Production configuration checklist (dashboard-only, per fresh Supabase project)

**Audience:** DevOps/on-call, Release engineering — see `docs/standards/DOCUMENTATION_STANDARDS.md` §2
**Status:** `ACTIVE`
**Owner:** DevOps / Security
**Since:** Phase 15 (`HDN-378`, Prompt 378 Security Hardening)

> This is a **checklist**, not an instance of `docs/templates/SUPPORT_RUNBOOK_TEMPLATE.md` — every item here is a one-time, dashboard/Management-API-only setting required on any fresh Supabase project before or at go-live, not an incident-shaped scenario. It exists under `docs/runbooks/` because that is where this repository's operational docs live, alongside the incident-shaped runbooks it complements (`docs/runbooks/incident-response.md`, `docs/runbooks/key-rotation.md`).

Every item below is a genuine gap between "what a SQL migration can express" and "what the project actually needs" — confirmed by checking `supabase/migrations/` for a corresponding mechanism before listing it here, not assumed.

## Checklist

- [ ] **1. Auth → Password Protection → enable leaked-password protection.** Closes the `auth_leaked_password_protection` Supabase advisory (confirmed present in `docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md` — 1 finding — and carried forward as a dashboard-only item in `docs/build-log/full-system-hardening/HARDENING_MATRIX.md` row 6). This is genuinely **dashboard/Management-API-only** — no migration can set it: a repository-wide check of `supabase/migrations/*.sql` finds no `auth.config`-shaped table anywhere (`auth.users`, `auth.identities`, etc. are Supabase-managed and appear only as foreign-key targets, never as a settings table this repository creates or alters) — Supabase's own auth configuration lives outside the `public`/`app` schema migration surface entirely. Enable it once per project, before go-live; it does not need to be re-applied per deploy.

- [ ] **2. `spatial_ref_sys`'s `rls_disabled_in_public` advisory — accepted, not actionable today.** This is the one Supabase security advisory at `ERROR` severity (`docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md` line 127) and it **cannot** be closed with `ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY` — the table is owned by the (non-relocatable, in this project's current PostGIS version) `postgis` extension, and `postgres` is not superuser on a hosted Supabase project, so that statement fails with a permission-denied error every time it's attempted. This is an **expected, accepted gap**, not a missed step — confirmed in both `docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md` §6 ("Dashboard settings, not migrations... `spatial_ref_sys` cannot have RLS enabled — it belongs to the PostGIS extension and `postgres` is not superuser on a hosted project") and `docs/build-log/full-system-hardening/BLOCKER_LEDGER.md`/`HARDENING_MATRIX.md` row 3. The only real fix is a full PostGIS relocation (`DROP EXTENSION postgis CASCADE` + recreate into a non-`public` schema), which would also require backfilling every live `geography`-typed column across every table that has one — a materially larger, out-of-scope task, not something to attempt as part of routine go-live configuration. **Do not spend go-live time trying to close this advisory** — record it as accepted and move on.

- [ ] **3. (Reserved) Future dashboard-only items.** Nothing else is known to belong here as of this checkpoint. Add an item here whenever a setting is confirmed to be Dashboard/Management-API-only (not expressible as a SQL migration under `supabase/migrations/`) **and** required for every fresh environment — the same bar items 1 and 2 above were held to. Do not add a per-tenant or per-deploy operational step here; this list is specifically for the class of setting a `supabase/migrations/*.sql` file structurally cannot express.

## Revision history

| Date | Version | Change | Author |
|---|---|---|---|
| 2026-08-24 | 0.1.0 | Initial — created at `HDN-378` (Step 15 Full-System-Hardening, Security Hardening). Items 1–2 verified against `docs/build-log/phase-09/LIVE_SUPABASE_MIGRATION_REPORT.md` and `docs/build-log/full-system-hardening/HARDENING_MATRIX.md`; confirmed no `auth.config`-shaped table exists anywhere in `supabase/migrations/`. | Claude Code (runtime build agent) |
