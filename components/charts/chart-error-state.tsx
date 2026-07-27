/**
 * Chart error state (CargoGrid Chart System) -- a thin, chart-flavored wrapper over the
 * real `ErrorState` primitive. Never exposes a stack trace: only `error.message` is
 * shown, and only when the caller opts in via `showMessage` (defaults to a generic
 * message, since a raw thrown error's `.message` can leak internal detail).
 */

import { ErrorState } from "../ui/error-state.tsx";

export interface ChartErrorStateProps {
  readonly error: Error;
  readonly onRetry?: () => void;
  readonly height?: number | string;
}

export function ChartErrorState({ error, onRetry, height = 280 }: ChartErrorStateProps) {
  return (
    <div style={{ height }} className="flex items-center justify-center">
      <ErrorState description="Something went wrong rendering this chart." requestId={error.name} onRetry={onRetry} />
    </div>
  );
}
