import { cn } from "@/lib/utils";

const STATUS_COLORS: Record<string, string> = {
  running: "bg-emerald-500 ring-emerald-500/30",
  succeeded: "bg-emerald-500 ring-emerald-500/30",
  building: "bg-blue-500 ring-blue-500/30 animate-pulse",
  deploying: "bg-blue-500 ring-blue-500/30 animate-pulse",
  queued: "bg-amber-500 ring-amber-500/30 animate-pulse",
  stopped: "bg-zinc-400 ring-zinc-400/30",
  failed: "bg-red-500 ring-red-500/30",
  crashed: "bg-red-500 ring-red-500/30",
  created: "bg-zinc-400 ring-zinc-400/30",
  deleting: "bg-red-500 ring-red-500/30 animate-pulse",
};

export function StatusDot({
  status,
  size = "md",
  className,
}: {
  status: string;
  size?: "sm" | "md";
  className?: string;
}) {
  const cls = STATUS_COLORS[status] ?? "bg-zinc-400 ring-zinc-400/30";
  const dim = size === "sm" ? "h-1.5 w-1.5" : "h-2 w-2";
  return (
    <span
      className={cn("inline-block rounded-full ring-4 ring-offset-0", dim, cls, className)}
    />
  );
}
