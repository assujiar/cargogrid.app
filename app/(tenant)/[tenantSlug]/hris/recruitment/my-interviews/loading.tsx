export default function MyInterviewsLoading() {
  return (
    <div className="flex flex-col gap-4" role="status" aria-label="Loading your assigned interviews">
      <div className="h-6 w-48 animate-pulse rounded bg-neutral-200" />
      <div className="h-48 animate-pulse rounded-md border border-neutral-200 bg-neutral-100" />
    </div>
  );
}
