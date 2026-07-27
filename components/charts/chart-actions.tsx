"use client";

/**
 * ChartCard action row (CargoGrid Chart System) -- refresh/export/fullscreen/period
 * selector/more, each caller-gated: an action button only renders when the caller
 * supplies a real handler, never an always-present button that does nothing (this
 * repository's own "no unresolved placeholder" rule, `AGENTS.md`).
 */

import type { ReactNode } from "react";
import { IconButton } from "../ui/icon-button.tsx";
import { DropdownMenu, type DropdownMenuItem } from "../ui/dropdown-menu.tsx";
import { Select } from "../forms/select.tsx";

export interface ChartActionsProps {
  readonly periods?: readonly { readonly value: string; readonly label: string }[];
  readonly period?: string;
  readonly onPeriodChange?: (period: string) => void;
  readonly onRefresh?: () => void;
  readonly onExportPng?: () => void;
  readonly onExportCsv?: () => void;
  readonly onFullscreen?: () => void;
  readonly moreActions?: readonly DropdownMenuItem[];
}

export function ChartActions({ periods, period, onPeriodChange, onRefresh, onExportPng, onExportCsv, onFullscreen, moreActions }: ChartActionsProps) {
  const exportItems: DropdownMenuItem[] = [
    ...(onExportPng ? [{ label: "Export as PNG", onSelect: onExportPng }] : []),
    ...(onExportCsv ? [{ label: "Export data as CSV", onSelect: onExportCsv }] : []),
  ];

  const hasActions = onRefresh || exportItems.length > 0 || onFullscreen || (moreActions && moreActions.length > 0);
  if (!periods && !hasActions) {
    return null;
  }

  return (
    <div className="flex items-center gap-1">
      {periods && periods.length > 0 ? (
        <Select value={period} onChange={(event) => onPeriodChange?.(event.target.value)} aria-label="Period">
          {periods.map((entry) => (
            <option key={entry.value} value={entry.value}>
              {entry.label}
            </option>
          ))}
        </Select>
      ) : null}
      {onRefresh ? <IconButton label="Refresh" icon={<RefreshGlyph />} onClick={onRefresh} /> : null}
      {exportItems.length > 0 ? <DropdownMenu align="end" items={exportItems} trigger={<IconButton label="Export" icon={<ExportGlyph />} />} /> : null}
      {onFullscreen ? <IconButton label="Fullscreen" icon={<FullscreenGlyph />} onClick={onFullscreen} /> : null}
      {moreActions && moreActions.length > 0 ? <DropdownMenu align="end" items={moreActions} trigger={<IconButton label="More actions" icon={<MoreGlyph />} />} /> : null}
    </div>
  );
}

function RefreshGlyph(): ReactNode {
  return <span aria-hidden="true">⟳</span>;
}
function ExportGlyph(): ReactNode {
  return <span aria-hidden="true">⇩</span>;
}
function FullscreenGlyph(): ReactNode {
  return <span aria-hidden="true">⛶</span>;
}
function MoreGlyph(): ReactNode {
  return <span aria-hidden="true">⋯</span>;
}
