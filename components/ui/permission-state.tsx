/**
 * Permission state primitive (`docs/design-system/02_COMPONENTS.md` "Permission
 * state") -- "you do not have access to..." pattern. `description` must never leak the
 * hidden resource's shape/existence beyond what the viewer is already entitled to know
 * (`09_UX_DESIGN_SYSTEM_WORKSTREAM.md` §5 "Forbidden") -- this component renders exactly
 * the text the caller supplies and adds no further detail of its own.
 */

export function PermissionState({ description = "You don't have access to this resource." }: { readonly description?: string }) {
  return (
    <div role="alert" className="flex flex-col items-center gap-2 rounded-md border border-neutral-200 bg-neutral-50 p-8 text-center">
      <p className="text-sm font-medium text-text-primary">Access denied</p>
      <p className="max-w-sm text-sm text-text-secondary">{description}</p>
    </div>
  );
}
