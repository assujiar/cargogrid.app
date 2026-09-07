-- CG-AUDIT-2026-09-02 D1 remediation (partial -- see this migration's own "what remains"
-- paragraph). `app.verify_mfa_step_up_challenge(p_challenge_id, p_actor_auth_user_id,
-- p_actor_label)` accepts no OTP, factor id or assertion at all: it flips a challenge row
-- from 'pending' to 'verified' as long as the challenge exists, belongs to the caller, and
-- has not expired -- the constrained principal satisfies it itself.
--
-- This is not an accident this migration's own creation (20260807100000) never noticed --
-- that migration's own header says so explicitly (design decision 1): "Real MFA FACTOR
-- enrollment/challenge-verification crypto (TOTP secret generation, WebAuthn ceremony) is
-- Supabase Auth's own native, external infrastructure... This checkpoint does NOT fabricate
-- a parallel app.mfa_factors table... app.verify_mfa_step_up_challenge records that
-- verification succeeded (reported by a caller who has itself already completed the real
-- challenge via Supabase's own client-side MFA flow); it does not re-derive or check a TOTP
-- code itself." That design boundary (Postgres cannot re-derive a TOTP secret it never
-- holds) is correct and unchanged by this fix. The GAP the audit actually found is narrower
-- and real: this function has no way to confirm a real Supabase-side MFA check ever
-- happened at all -- it simply trusts the caller's own say-so. `verify_mfa_step_up_challenge`
-- is granted directly to `authenticated` (this migration's own grant list), so any
-- authenticated session can call it straight from the app's real API surface and mark
-- itself "verified" without ever calling Supabase's real `auth.mfa.challengeAndVerify()`
-- client-side flow at all.
--
-- Fix: require the CALLING session itself to already be authenticated at AAL2 -- Supabase's
-- own Authenticator Assurance Level claim, stamped into every session's JWT by GoTrue only
-- once a real second factor has actually been verified there, entirely independent of
-- anything this repository's own schema could fabricate. `auth.jwt() ->> 'aal'` is the
-- authoritative signal this function was missing; self-asserting verification without a
-- real aal2 session is exactly the gap this closes.
--
-- Deliberately gated on `auth.uid() is not null` (mirroring `app.assert_actor_is_session_
-- identity`'s own established idiom verbatim: "engages only for a genuine authenticated
-- session, the one principal that could impersonate") rather than an unconditional
-- requirement, for a concrete, checked reason: a repository-wide audit of every one of the
-- ~30 real `app.verify_mfa_step_up_challenge` call sites across the 12 scripts/db-tests/*.sql
-- files that depend on it as a precondition for some OTHER high-risk action under test
-- (HRIS payroll, finance subledger, procurement, customer portal, import/export, and more)
-- found that every single one calls it with no simulated session at all (auth.uid() is
-- already null in every one of them, the same service-role-equivalent exemption this
-- repository's whole authority model already relies on for db-tests) -- so this gate adds
-- zero risk of the "unauthenticated but allowed" mode ADR-0027 Part C forbids introducing,
-- and needed zero changes to any of those 12 files' own tests (confirmed by a full
-- `pnpm run db:test` re-run: ALL PASSED, unchanged). In real production, PostgREST always
-- populates `request.jwt.claims` (and therefore `auth.uid()`) from the caller's real session
-- for every authenticated request -- there is no realistic external path to this function
-- with a null session identity, so this gate engages on exactly the one channel the audit's
-- own finding is about.
--
-- `auth.uid()`/`auth.jwt()` are both read defensively (`begin`/`exception`), mirroring `app.
-- assert_actor_is_session_identity`'s own established idiom -- live-caught while writing this
-- fix's own db-test regression (the identical class of bug CG-AUDIT-2026-09-02 NEW-1's own
-- migration already documents in detail): a custom/placeholder GUC like `request.jwt.claims`
-- set via `SET LOCAL` outside an explicit transaction block reverts to an empty string, not
-- unset, once the block ends, and `auth.uid()`'s own real implementation casts that value to
-- `::json` BEFORE checking whether it is empty -- calling it bare a second time here (rather
-- than relying solely on the one call already safely wrapped inside `assert_actor_is_session_
-- identity` above) crashed on exactly that leaked state during this migration's own testing.
--
-- What remains open, and why it is not closed here (the same disclosed boundary A5's own
-- remediation left open): actually enabling a real TOTP/phone factor provider is a Supabase
-- project auth-config change (`supabase/config.toml`'s `[auth.mfa.totp]`/`[auth.mfa.phone]`
-- sections, currently disabled) an operator must make against the live project, and no
-- client-side UI in this repository yet calls Supabase's real `supabase.auth.mfa.
-- challengeAndVerify()` before invoking this RPC (confirmed: `server/mutations/
-- enterprise-mfa.ts`'s own `verifyMfaStepUpChallenge` is a thin RPC pass-through with no
-- prior real MFA call). This fix makes the DATABASE gate genuinely fail closed the moment
-- either piece exists; building the enrollment/challenge UI and turning on a real provider
-- is a separate, larger product/infra task, tracked as `DEFERRED_LARGE` continuation of D1
-- in the remediation backlog, not attempted here.
--
-- `CREATE OR REPLACE FUNCTION` -- unchanged signature, no `DROP + CREATE`; confirmed via the
-- F3-taught check (case-insensitive grep for a later `ALTER FUNCTION`/`CREATE [OR REPLACE]
-- FUNCTION` naming this function) that it was never touched by any migration after its own
-- creation, so no later security-mode hardening to preserve.

create or replace function app.verify_mfa_step_up_challenge(
  p_challenge_id uuid,
  p_actor_auth_user_id uuid,
  p_actor_label text
)
returns app.mfa_step_up_challenges
language plpgsql
security definer
set search_path = app, pg_temp
as $$
declare
  v_challenge app.mfa_step_up_challenges;
  v_session_identity uuid;
  v_session_aal text;
begin
  perform app.assert_actor_is_session_identity(p_actor_auth_user_id);

  -- CG-AUDIT-2026-09-02 D1: see this migration's own header for the full reasoning. Both
  -- reads are defensive (begin/exception), mirroring app.assert_actor_is_session_identity's
  -- own idiom verbatim -- auth.uid()'s OWN real implementation casts to ::json BEFORE
  -- checking for an empty value, so calling it bare a second time here (rather than only
  -- once, already-guarded, inside assert_actor_is_session_identity above) would crash on a
  -- malformed/leaked request.jwt.claims GUC instead of degrading to "no session known."
  begin
    v_session_identity := auth.uid();
  exception
    when others then
      v_session_identity := null;
  end;
  if v_session_identity is not null then
    begin
      v_session_aal := auth.jwt() ->> 'aal';
    exception
      when others then
        v_session_aal := null;
    end;
    if coalesce(v_session_aal, '') <> 'aal2' then
      raise exception 'mfa_step_up_requires_real_aal2_session: the calling session must itself already be authenticated at AAL2 (a real second factor verified by Supabase Auth) -- self-asserting a step-up verification without one is not accepted'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  select * into v_challenge from app.mfa_step_up_challenges where id = p_challenge_id and auth_user_id = p_actor_auth_user_id and status = 'pending' for update;
  if not found then
    raise exception 'mfa_step_up_challenge_not_pending: % is not a pending challenge for this identity', p_challenge_id
      using errcode = 'no_data_found';
  end if;

  if v_challenge.challenge_expires_at < now() then
    -- Deliberately does NOT persist status = 'expired' here: a caller that
    -- wraps this call in its own exception handler (the normal, expected
    -- shape) runs inside an implicit savepoint, and Postgres rolls back
    -- EVERY statement since that savepoint -- including this function's own
    -- prior UPDATE -- once the RAISE below propagates. Persisting "expired"
    -- lazily, on the next read that notices a stale pending row past its own
    -- challenge_expires_at, is the same pattern app.authenticate_api_key
    -- (PLT-129) already established for its own past-expiry status flip.
    raise exception 'mfa_step_up_challenge_expired: % expired at %', p_challenge_id, v_challenge.challenge_expires_at
      using errcode = 'check_violation';
  end if;

  update app.mfa_step_up_challenges
  set status = 'verified', verified_at = now()
  where id = p_challenge_id
  returning * into v_challenge;

  perform app.capture_audit_event(
    v_challenge.tenant_id, p_actor_auth_user_id, p_actor_label, 'verify_mfa_step_up_challenge',
    'app.mfa_step_up_challenges', v_challenge.id, 'success', null, null, to_jsonb(v_challenge)
  );

  return v_challenge;
end;
$$;

comment on function app.verify_mfa_step_up_challenge(uuid, uuid, text) is
  'CG-AUDIT-2026-09-02 D1 (partial): now requires the calling session itself to be authenticated at AAL2 (auth.jwt()->>''aal'' = ''aal2'', Supabase''s own claim stamped only after a real second factor is verified by GoTrue) whenever a real session identity is present -- closing the "constrained principal satisfies it itself" gap the audit found, without fabricating a parallel TOTP-verification layer this repository cannot own. Still records governance state only, exactly as OPS-173/IAE-027''s own design already disclosed; still does not re-derive a TOTP code itself. Enabling a real factor provider and building the client-side challengeAndVerify() flow remain open (tracked in the remediation backlog).';
