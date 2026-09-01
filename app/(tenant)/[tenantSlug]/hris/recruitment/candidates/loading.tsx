export default function CandidatesLoading() {
  return (
    <div className="flex flex-col gap-4" role="status" aria-label="Loading candidate directory">
      <div className="h-6 w-48 animate-pulse rounded bg-neutral-200" />
      <div className="h-40 animate-pulse rounded-md border border-neutral-200 bg-neutral-100" />
      <div className="h-64 animate-pulse rounded-md border border-neutral-200 bg-neutral-100" />
    </div>
  );
}
