"use client";

import Link from "next/link";
import useSWR from "swr";
import { Globe } from "lucide-react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { fetcher } from "@/lib/api";
import type { App, Domain, ListResponse } from "@/lib/types";

interface AppWithDomains extends App {
  domains?: Domain[];
}

export default function DomainsPage() {
  const apps = useSWR<ListResponse<App>>("/apps/", fetcher);

  return (
    <div className="container space-y-6 py-8">
      <header>
        <h1 className="text-2xl font-semibold tracking-tight">Domains</h1>
        <p className="text-sm text-muted-foreground">
          Manage custom hostnames + automatic Let&rsquo;s Encrypt certificates.
        </p>
      </header>

      <div className="space-y-3">
        {apps.data?.results.map((app) => (
          <Card key={app.id}>
            <CardContent className="p-5">
              <Link
                href={`/apps/${app.id}#domains`}
                className="flex items-center justify-between"
              >
                <div className="flex items-center gap-3">
                  <Globe className="h-4 w-4 text-muted-foreground" />
                  <div>
                    <p className="font-medium">{app.name}</p>
                    <p className="text-xs text-muted-foreground">
                      {app.runtime} · port {app.internalPort}
                    </p>
                  </div>
                </div>
                <Badge variant="muted">manage</Badge>
              </Link>
            </CardContent>
          </Card>
        ))}
        {apps.data?.results.length === 0 && (
          <Card>
            <CardContent className="py-12 text-center text-sm text-muted-foreground">
              You don&rsquo;t have any apps yet.
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}
