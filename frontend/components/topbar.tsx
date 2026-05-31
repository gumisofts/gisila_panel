"use client";

import Link from "next/link";
import useSWR from "swr";
import { Button } from "@/components/ui/button";
import { ThemeToggle } from "@/components/theme-toggle";
import { fetcher } from "@/lib/api";
import type { User } from "@/lib/types";

export function Topbar({ title }: { title?: string }) {
  const { data } = useSWR<User>("/auth/me", fetcher);

  return (
    <header className="flex h-12 items-center justify-between border-b border-border bg-background px-5">
      <div className="text-sm font-medium text-foreground/70">
        {title ?? "Dashboard"}
      </div>
      <div className="flex items-center gap-2">
        <ThemeToggle />
        <Button asChild variant="outline" size="sm">
          <Link href="/apps/new">New app</Link>
        </Button>
        <div className="flex items-center gap-2 rounded-md border border-border bg-card px-2.5 py-1 text-xs text-muted-foreground">
          <span className="h-1.5 w-1.5 rounded-full bg-emerald-500" />
          {data?.email ?? "—"}
        </div>
      </div>
    </header>
  );
}
