"use client";

/**
 * Live demos for a representative subset of checkpoint 4's ~40 new components
 * (CargoGrid UI Modernization). Not exhaustive by design: 14 of ~40 get a live demo
 * here; the rest still appear correctly in `/internal/design-system/components` via
 * `lib/design-system/component-registry.ts` (status, purpose, copyable import,
 * a11y/tokens metadata) but without a rendered variant matrix — disclosed here rather
 * than silently claimed complete. Each demo uses the real imported component.
 */

import { useState } from "react";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { Switch } from "../../../../../components/forms/switch.tsx";
import { Alert } from "../../../../../components/ui/alert.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { Dialog } from "../../../../../components/ui/dialog.tsx";
import { Tooltip, TooltipProvider } from "../../../../../components/ui/tooltip.tsx";
import { DropdownMenu } from "../../../../../components/ui/dropdown-menu.tsx";
import { Tabs } from "../../../../../components/ui/tabs.tsx";
import { Accordion } from "../../../../../components/ui/accordion.tsx";
import { Card } from "../../../../../components/ui/card.tsx";
import { KpiCard } from "../../../../../components/ui/kpi-card.tsx";
import { Button } from "../../../../../components/ui/button.tsx";

export function InputShowcase() {
  return (
    <div className="flex max-w-sm flex-col gap-2">
      <Input placeholder="Default" />
      <Input placeholder="Disabled" disabled />
      <Input placeholder="Read-only" readOnly value="Fixed value" />
      <Input placeholder="Invalid" invalid />
    </div>
  );
}

export function SelectShowcase() {
  return (
    <div className="max-w-sm">
      <Select defaultValue="ocean">
        <option value="ocean">Ocean freight</option>
        <option value="air">Air freight</option>
        <option value="road">Road freight</option>
      </Select>
    </div>
  );
}

export function CheckboxSwitchShowcase() {
  return (
    <div className="flex flex-col gap-2">
      <Checkbox label="Send confirmation email" defaultChecked />
      <Checkbox label="Disabled option" disabled />
      <Switch label="Auto-renew contract" defaultChecked />
      <Switch label="Disabled toggle" disabled />
    </div>
  );
}

export function AlertShowcase() {
  return (
    <div className="flex flex-col gap-2">
      <Alert tone="info">Informational alert, dismissible.</Alert>
      <Alert tone="warning" dismissible>
        Warning alert — click × to dismiss.
      </Alert>
      <Alert tone="danger">Danger alert, not dismissible.</Alert>
    </div>
  );
}

export function EmptyErrorStateShowcase() {
  return (
    <div className="flex flex-col gap-4">
      <EmptyState
        title="No quotations yet"
        description="Create your first quotation to get started."
        primaryAction={<Button variant="primary">Create quotation</Button>}
      />
      <ErrorState description="Something went wrong loading this page." requestId="req_demo_123" onRetry={() => alert("Demo only — would retry")} />
    </div>
  );
}

export function DialogShowcase() {
  const [open, setOpen] = useState(false);
  return (
    <Dialog
      open={open}
      onOpenChange={setOpen}
      title="Confirm action"
      description="This is a real, focus-trapped Radix Dialog — try Tab and Escape."
      trigger={<Button variant="secondary">Open dialog</Button>}
    >
      <Button variant="primary" onClick={() => setOpen(false)}>
        Close
      </Button>
    </Dialog>
  );
}

export function TooltipDropdownShowcase() {
  return (
    <TooltipProvider>
      <div className="flex items-center gap-3">
        <Tooltip content="Real Radix tooltip — hover or focus this button">
          <Button variant="secondary">Hover me</Button>
        </Tooltip>
        <DropdownMenu
          trigger={<Button variant="secondary">Actions ▾</Button>}
          items={[
            { label: "Edit", onSelect: () => alert("Edit") },
            { label: "Duplicate", onSelect: () => alert("Duplicate") },
            { label: "Delete", onSelect: () => alert("Delete"), destructive: true },
          ]}
        />
      </div>
    </TooltipProvider>
  );
}

export function TabsAccordionShowcase() {
  return (
    <div className="flex flex-col gap-4">
      <Tabs
        items={[
          { value: "details", label: "Details", content: <p className="text-sm">Quotation details panel.</p> },
          { value: "lines", label: "Lines", content: <p className="text-sm">Quotation lines panel.</p> },
          { value: "history", label: "History", content: <p className="text-sm">Version history panel.</p> },
        ]}
      />
      <Accordion
        items={[
          { title: "What happens on approval?", content: "The quotation status updates and the customer is notified." },
          { title: "Can I revise after submission?", content: "Yes, a new version is created." },
        ]}
      />
    </div>
  );
}

export function CardKpiShowcase() {
  return (
    <div className="flex flex-wrap gap-3">
      <Card title="Account summary" className="w-64">
        <p className="text-sm text-text-secondary">Redline Logistics — active, credit cleared.</p>
      </Card>
      <KpiCard label="Open quotations" value={12} trend="+3 this week" />
      <KpiCard label="Below margin threshold" value={2} tone="danger" />
    </div>
  );
}
