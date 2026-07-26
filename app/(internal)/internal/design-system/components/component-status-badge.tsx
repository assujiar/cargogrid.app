import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import type { ComponentStatus } from "../../../../../lib/design-system/component-registry.ts";

const STATUS_TONE: Record<ComponentStatus, "success" | "neutral" | "danger" | "warning"> = {
  IMPLEMENTED: "success",
  DOCUMENTED_ONLY: "neutral",
  BLOCKED: "danger",
  NOT_NAMED: "warning",
};

const STATUS_LABEL: Record<ComponentStatus, string> = {
  IMPLEMENTED: "Implemented",
  DOCUMENTED_ONLY: "Documented only",
  BLOCKED: "Blocked",
  NOT_NAMED: "Not named in this repo",
};

/** Dogfoods the real StatusBadge to show each catalogue entry's own status — the showcase's status filter (`ComponentStatus`) drives the same tone mapping. */
export function ComponentStatusBadge({ status }: { readonly status: ComponentStatus }) {
  return <StatusBadge tone={STATUS_TONE[status]} label={STATUS_LABEL[status]} />;
}
