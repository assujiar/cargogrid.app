/**
 * Server-only guard — Prompt 86 §15 (UI/UX impact): "Expose only approved
 * public variables; never serialize server secrets."
 *
 * No real bundler exists yet (no `app/` directory — Phase 1 scope, per
 * `docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md`'s migration-wave
 * plan), so a literal client-bundle scan is not yet possible. This guard is
 * the runtime-checkable equivalent available today: it throws if code that
 * requests `server`/`secret`-classified values is ever evaluated in a
 * browser context (`typeof window !== "undefined"`). Once Phase 1 lands a
 * real Next.js build, `PH0-088`/Phase-1 CI should additionally add a static
 * bundle-content scan for `SUPABASE_SERVICE_ROLE_KEY`-shaped strings — that
 * is a distinct, heavier check this module does not attempt to fake.
 */

export function assertServerOnly(callerLabel: string): void {
  if (typeof window !== "undefined") {
    throw new Error(
      `${callerLabel} accessed server-only environment values from a browser context. ` +
        `This is a real bug: secret/server-classified variables must never be read outside a server boundary.`,
    );
  }
}
