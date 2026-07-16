/**
 * Tenant control-plane contract (PLT-105, CG-S6-PLT-002). Typed payload/validator
 * definitions for the tenant lifecycle RPCs, per docs/architecture/04_REPOSITORY_TARGET_STRUCTURE.md
 * §11's recommendation (adopted as a Platform Core WBS convention at CG-S6-PLT-001,
 * see docs/build-log/phase-01/00_PLATFORM_CORE_WBS.md §3): server/contracts/ exists
 * as a first-class folder from Phase 1, not retrofitted once a second consumer needs it.
 *
 * Mirrors supabase/migrations/20260716075355_create_tenants.sql's app.tenants columns
 * and the two RPC functions it defines — the SQL migration is the source of truth for
 * shape and constraints; this file is a typed client-side view of that same contract,
 * not an independent redefinition.
 */

import { z } from "zod";

export const TENANT_STATUSES = ["provisioning", "active", "suspended", "terminated"] as const;
export const TenantStatusSchema = z.enum(TENANT_STATUSES);
export type TenantStatus = z.infer<typeof TenantStatusSchema>;

export const TenantSchema = z.object({
  id: z.string().uuid(),
  slug: z.string(),
  name: z.string(),
  canonicalStatus: TenantStatusSchema,
  planSnapshot: z.record(z.string(), z.unknown()),
  idempotencyKey: z.string(),
  requestedBy: z.string().nullable(),
  reason: z.string().nullable(),
  legalHold: z.boolean(),
  recordVersion: z.number().int().positive(),
  effectiveFrom: z.string().nullable(),
  effectiveUntil: z.string().nullable(),
  activatedAt: z.string().nullable(),
  deactivatedAt: z.string().nullable(),
  terminatedAt: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type Tenant = z.infer<typeof TenantSchema>;

const SLUG_PATTERN = /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/;

export const ProvisionTenantInputSchema = z.object({
  slug: z.string().regex(SLUG_PATTERN, "slug must be lowercase alphanumeric with internal hyphens only"),
  name: z.string().min(1),
  idempotencyKey: z.string().min(1),
  requestedBy: z.string().min(1),
  planSnapshot: z.record(z.string(), z.unknown()).optional(),
});
export type ProvisionTenantInput = z.infer<typeof ProvisionTenantInputSchema>;

export const TransitionTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  newStatus: TenantStatusSchema,
  reason: z.string().min(1),
  requestedBy: z.string().min(1),
});
export type TransitionTenantInput = z.infer<typeof TransitionTenantInputSchema>;

/**
 * Maps a raw app.tenants row (snake_case, as returned by the Postgres RPC functions)
 * to this contract's camelCase shape. The one translation seam between the database's
 * own naming convention and the application layer's — kept in one place so it is never
 * duplicated or allowed to silently drift per column.
 */
export function parseTenantRow(row: Record<string, unknown>): Tenant {
  return TenantSchema.parse({
    id: row.id,
    slug: row.slug,
    name: row.name,
    canonicalStatus: row.canonical_status,
    planSnapshot: row.plan_snapshot,
    idempotencyKey: row.idempotency_key,
    requestedBy: row.requested_by,
    reason: row.reason,
    legalHold: row.legal_hold,
    recordVersion: row.record_version,
    effectiveFrom: row.effective_from,
    effectiveUntil: row.effective_until,
    activatedAt: row.activated_at,
    deactivatedAt: row.deactivated_at,
    terminatedAt: row.terminated_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
