/**
 * Field-level and record-level access contract (PLT-114, CG-S6-PLT-011). Mirrors
 * supabase/migrations/20260716110430_create_field_record_access.sql's app.can_access_record()
 * RPC and app.users_directory view. Never a replacement for entitlement/RBAC/RLS -- the
 * final layer of the 8-stage flow's stages 5-6 (field-level policy, status/value rule).
 */

import { z } from "zod";

export const CanAccessRecordInputSchema = z.object({
  authUserId: z.string().uuid(),
  tenantId: z.string().uuid(),
  ownerUserId: z.string().uuid(),
  sharedOrgUnitIds: z.array(z.string().uuid()).default([]),
  customerAccountRef: z.string().nullable().default(null),
});
export type CanAccessRecordInput = z.input<typeof CanAccessRecordInputSchema>;

export const UserDirectoryEntrySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  authUserId: z.string().uuid(),
  displayName: z.string(),
  status: z.string(),
  orgUnitId: z.string().uuid().nullable(),
  email: z.string(),
  emailMasked: z.boolean(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type UserDirectoryEntry = z.infer<typeof UserDirectoryEntrySchema>;

/** Maps a raw app.users_directory row (snake_case) to this contract's camelCase shape. */
export function parseUserDirectoryEntry(row: Record<string, unknown>): UserDirectoryEntry {
  return UserDirectoryEntrySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    authUserId: row.auth_user_id,
    displayName: row.display_name,
    status: row.status,
    orgUnitId: row.org_unit_id,
    email: row.email,
    emailMasked: row.email_masked,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}
