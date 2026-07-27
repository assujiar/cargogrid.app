/**
 * Progress primitive (`docs/design-system/02_COMPONENTS.md` "Progress") -- determinate
 * long-running-operation indicator. Native `<progress>`, server-safe, correct
 * accessible semantics for free (no Radix needed for a determinate bar).
 */

export interface ProgressProps {
  readonly value: number;
  readonly max?: number;
  readonly label: string;
}

export function Progress({ value, max = 100, label }: ProgressProps) {
  const clamped = Math.min(Math.max(value, 0), max);

  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center justify-between text-xs text-text-secondary">
        <span>{label}</span>
        <span>{Math.round((clamped / max) * 100)}%</span>
      </div>
      <progress value={clamped} max={max} className="h-2 w-full overflow-hidden rounded-full [&::-webkit-progress-bar]:rounded-full [&::-webkit-progress-bar]:bg-neutral-200 [&::-webkit-progress-value]:bg-primary [&::-moz-progress-bar]:bg-primary">
        {Math.round((clamped / max) * 100)}%
      </progress>
    </div>
  );
}
