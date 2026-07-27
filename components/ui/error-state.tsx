/**
 * Error state primitive (`docs/design-system/02_COMPONENTS.md` "Error state") --
 * human-readable message + request ID + gated retry, replacing the ad hoc
 * `role="alert"` block every real list/detail page currently hand-rolls
 * (`docs/design-system/08_COMPONENT_INVENTORY.md` §4). `requestId` and `onRetry` are
 * both optional -- most current call sites have neither yet; this component does not
 * fabricate a request id when the caller has none to show.
 */

export interface ErrorStateProps {
  readonly title?: string;
  readonly description: string;
  readonly requestId?: string;
  readonly onRetry?: () => void;
  readonly retryLabel?: string;
}

export function ErrorState({ title = "Something went wrong", description, requestId, onRetry, retryLabel = "Retry" }: ErrorStateProps) {
  return (
    <div role="alert" className="flex flex-col gap-2 rounded-md border border-danger/30 bg-danger/10 p-4">
      <p className="text-sm font-semibold text-danger">{title}</p>
      <p className="text-sm text-text-primary">{description}</p>
      {requestId ? <p className="text-xs text-text-secondary">Request ID: {requestId}</p> : null}
      {onRetry ? (
        <button type="button" onClick={onRetry} className="w-fit text-sm font-medium text-primary underline">
          {retryLabel}
        </button>
      ) : null}
    </div>
  );
}
