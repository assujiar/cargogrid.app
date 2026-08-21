/**
 * Dashboard Builder contract (IAE-003, Prompt 331). Mirrors
 * supabase/migrations/20260802020000_create_intelligence_dashboard_builder.sql's
 * app.tenant_dashboards/app.tenant_dashboard_versions/app.tenant_dashboard_widgets
 * shape. A widget always binds to an existing, active app.report_types code
 * (IAE-002) -- there is no raw-SQL widget shape.
 */

import { z } from "zod";

export const TENANT_DASHBOARD_STATUSES = ["draft", "published", "archived"] as const;
export const TenantDashboardStatusSchema = z.enum(TENANT_DASHBOARD_STATUSES);
export type TenantDashboardStatus = z.infer<typeof TenantDashboardStatusSchema>;

export const TENANT_DASHBOARD_VERSION_STATUSES = ["draft", "published", "superseded"] as const;
export const TenantDashboardVersionStatusSchema = z.enum(TENANT_DASHBOARD_VERSION_STATUSES);
export type TenantDashboardVersionStatus = z.infer<typeof TenantDashboardVersionStatusSchema>;

export const TenantDashboardSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  name: z.string(),
  description: z.string(),
  status: TenantDashboardStatusSchema,
  currentVersionId: z.string().uuid().nullable(),
  createdByAuthUserId: z.string().uuid(),
  createdBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type TenantDashboard = z.infer<typeof TenantDashboardSchema>;

export function parseTenantDashboard(row: Record<string, unknown>): TenantDashboard {
  return TenantDashboardSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    name: row.name,
    description: row.description,
    status: row.status,
    currentVersionId: row.current_version_id,
    createdByAuthUserId: row.created_by_auth_user_id,
    createdBy: row.created_by,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Free-form grid-position hint (columns/breakpoints) -- never a query. The widgets table is the real content. */
export const TenantDashboardLayoutSchema = z.record(z.string(), z.unknown());
export type TenantDashboardLayout = z.infer<typeof TenantDashboardLayoutSchema>;

export const TenantDashboardVersionSchema = z.object({
  id: z.string().uuid(),
  dashboardId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  layout: TenantDashboardLayoutSchema,
  status: TenantDashboardVersionStatusSchema,
  publishedByAuthUserId: z.string().uuid().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type TenantDashboardVersion = z.infer<typeof TenantDashboardVersionSchema>;

export function parseTenantDashboardVersion(row: Record<string, unknown>): TenantDashboardVersion {
  return TenantDashboardVersionSchema.parse({
    id: row.id,
    dashboardId: row.dashboard_id,
    versionNumber: row.version_number,
    layout: row.layout ?? {},
    status: row.status,
    publishedByAuthUserId: row.published_by_auth_user_id,
    publishedBy: row.published_by,
    publishedAt: row.published_at,
    createdAt: row.created_at,
  });
}

/** A widget's own bag of parameter overrides -- validated server-side against the bound report's parameter_schema via app.validate_report_parameters (IAE-002). This schema only bounds the value shape to safe, flat, non-recursive primitives. */
export const WidgetParameterOverridesSchema = z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()]));
export type WidgetParameterOverrides = z.input<typeof WidgetParameterOverridesSchema>;

export const TenantDashboardWidgetSchema = z.object({
  id: z.string().uuid(),
  dashboardVersionId: z.string().uuid(),
  reportTypeCode: z.string(),
  title: z.string(),
  position: z.record(z.string(), z.unknown()),
  parameterOverrides: WidgetParameterOverridesSchema,
  displayOrder: z.number().int().nonnegative(),
  createdAt: z.string(),
});
export type TenantDashboardWidget = z.infer<typeof TenantDashboardWidgetSchema>;

export function parseTenantDashboardWidget(row: Record<string, unknown>): TenantDashboardWidget {
  return TenantDashboardWidgetSchema.parse({
    id: row.id,
    dashboardVersionId: row.dashboard_version_id,
    reportTypeCode: row.report_type_code,
    title: row.title,
    position: row.position ?? {},
    parameterOverrides: row.parameter_overrides ?? {},
    displayOrder: row.display_order,
    createdAt: row.created_at,
  });
}

export const CreateTenantDashboardDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  name: z.string().min(1),
  description: z.string().default(""),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateTenantDashboardDraftInput = z.input<typeof CreateTenantDashboardDraftInputSchema>;

export const AddDashboardWidgetInputSchema = z.object({
  dashboardVersionId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  title: z.string().min(1),
  position: z.record(z.string(), z.unknown()).default({}),
  parameterOverrides: WidgetParameterOverridesSchema.default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddDashboardWidgetInput = z.input<typeof AddDashboardWidgetInputSchema>;

export const RemoveDashboardWidgetInputSchema = z.object({
  widgetId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RemoveDashboardWidgetInput = z.input<typeof RemoveDashboardWidgetInputSchema>;

export const PublishTenantDashboardVersionInputSchema = z.object({
  dashboardId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishTenantDashboardVersionInput = z.input<typeof PublishTenantDashboardVersionInputSchema>;

export const RollbackTenantDashboardInputSchema = z.object({
  dashboardId: z.string().uuid(),
  targetVersionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RollbackTenantDashboardInput = z.input<typeof RollbackTenantDashboardInputSchema>;
