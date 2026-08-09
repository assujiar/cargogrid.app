"use server";

/**
 * Position/grade catalogue Server Actions (HRT-275, CG-S12-HRT-003). Mirrors
 * app/(tenant)/[tenantSlug]/hris/employees/actions.ts's own shape: resolve portal
 * access, call the typed mutation wrapper, translate a known mutation error into a
 * plain-language message, revalidate the affected path(s).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createPositionGrade,
  updatePositionGrade,
  setPositionGradeStatus,
  createPosition,
  updatePosition,
  setPositionStatus,
  PositionMutationError,
} from "../../../../../server/mutations/position.ts";
import type { PositionGradeStatus, PositionStatus } from "../../../../../server/contracts/position/position.ts";

export interface PositionActionState {
  readonly error: string | null;
}

const OK: PositionActionState = { error: null };
const NO_ACCESS: PositionActionState = { error: "You don't have access to this organization's HRIS workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function catalogPath(tenantSlug: string): string {
  return `/${tenantSlug}/hris/positions`;
}

export async function createPositionGradeAction(tenantSlug: string, _prevState: PositionActionState, formData: FormData): Promise<PositionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const rankRaw = String(formData.get("rank") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await createPositionGrade(supabase, {
      tenantId: access.tenant.id,
      code,
      name,
      rank: rankRaw ? Number(rankRaw) : null,
      description,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not create this grade: ${error.message}` };
    throw error;
  }

  revalidatePath(catalogPath(tenantSlug));
  return OK;
}

export async function setPositionGradeStatusAction(
  tenantSlug: string,
  id: string,
  expectedVersion: number,
  newStatus: PositionGradeStatus,
  _prevState: PositionActionState,
  _formData: FormData,
): Promise<PositionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await setPositionGradeStatus(supabase, { id, expectedVersion, newStatus, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not change this grade's status: ${error.message}` };
    throw error;
  }

  revalidatePath(catalogPath(tenantSlug));
  return OK;
}

export async function updatePositionGradeAction(
  tenantSlug: string,
  id: string,
  expectedVersion: number,
  _prevState: PositionActionState,
  formData: FormData,
): Promise<PositionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  const rankRaw = String(formData.get("rank") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await updatePositionGrade(supabase, { id, expectedVersion, name, rank: rankRaw ? Number(rankRaw) : null, description, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not save this grade: ${error.message}` };
    throw error;
  }

  revalidatePath(catalogPath(tenantSlug));
  return OK;
}

export async function createPositionAction(tenantSlug: string, _prevState: PositionActionState, formData: FormData): Promise<PositionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim();
  const gradeId = String(formData.get("gradeId") ?? "").trim() || null;
  const capacityRaw = String(formData.get("capacity") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await createPosition(supabase, {
      tenantId: access.tenant.id,
      code,
      title,
      orgUnitId,
      gradeId,
      capacity: capacityRaw ? Number(capacityRaw) : null,
      description,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not create this position: ${error.message}` };
    throw error;
  }

  revalidatePath(catalogPath(tenantSlug));
  return OK;
}

export async function updatePositionAction(tenantSlug: string, id: string, expectedVersion: number, _prevState: PositionActionState, formData: FormData): Promise<PositionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const title = String(formData.get("title") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim();
  const gradeId = String(formData.get("gradeId") ?? "").trim() || null;
  const capacityRaw = String(formData.get("capacity") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await updatePosition(supabase, {
      id,
      expectedVersion,
      title,
      orgUnitId,
      gradeId,
      capacity: capacityRaw ? Number(capacityRaw) : null,
      description,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not save this position: ${error.message}` };
    throw error;
  }

  revalidatePath(catalogPath(tenantSlug));
  revalidatePath(`${catalogPath(tenantSlug)}/${id}`);
  return OK;
}

export async function setPositionStatusAction(
  tenantSlug: string,
  id: string,
  expectedVersion: number,
  newStatus: PositionStatus,
  _prevState: PositionActionState,
  _formData: FormData,
): Promise<PositionActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await setPositionStatus(supabase, { id, expectedVersion, newStatus, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PositionMutationError) return { error: `Could not change this position's status: ${error.message}` };
    throw error;
  }

  revalidatePath(catalogPath(tenantSlug));
  revalidatePath(`${catalogPath(tenantSlug)}/${id}`);
  return OK;
}
