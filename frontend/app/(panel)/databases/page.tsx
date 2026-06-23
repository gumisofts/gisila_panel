"use client";

import useSWR from "swr";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { fetcher } from "@/lib/api";
import type { DatabaseEngineDescriptor, ListResponse } from "@/lib/types";
import { PostgresInstances } from "./_components/postgres-instances";
import { MongoInstances } from "./_components/mongo-instances";

// Each engine key maps to the component that renders its instance list. Adding
// an engine in the backend registry + a component here is all the UI needs.
const ENGINE_VIEWS: Record<string, () => React.ReactNode> = {
  postgres: () => <PostgresInstances />,
  mongodb: () => <MongoInstances />,
};

export default function DatabasesPage() {
  const { data } = useSWR<ListResponse<DatabaseEngineDescriptor>>(
    "/db-engines/",
    fetcher
  );

  // Render only engines the UI knows how to display; fall back to the built-in
  // pair before the descriptor list has loaded.
  const engines = (data?.results ?? []).filter((e) => ENGINE_VIEWS[e.key]);
  const tabs =
    engines.length > 0
      ? engines
      : ([
          { key: "postgres", label: "PostgreSQL" },
          { key: "mongodb", label: "MongoDB" },
        ] as DatabaseEngineDescriptor[]);

  return (
    <div className="mx-auto max-w-4xl space-y-6 p-6">
      <div>
        <h1 className="text-xl font-semibold">Databases</h1>
        <p className="mt-0.5 text-sm text-muted-foreground">
          Manage your database engines. Pick an engine below to install and
          administer instances.
        </p>
      </div>

      <Tabs defaultValue={tabs[0]?.key ?? "postgres"}>
        <TabsList>
          {tabs.map((e) => (
            <TabsTrigger key={e.key} value={e.key}>
              {e.label}
            </TabsTrigger>
          ))}
        </TabsList>
        {tabs.map((e) => (
          <TabsContent key={e.key} value={e.key}>
            {ENGINE_VIEWS[e.key]?.()}
          </TabsContent>
        ))}
      </Tabs>
    </div>
  );
}
