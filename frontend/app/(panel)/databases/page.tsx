"use client";

import useSWR from "swr";
import { Tab, TabList, TabPanel, TabPanels, Tabs } from "@carbon/react";
import { Page, PageHeader } from "@/components/page";
import { fetcher } from "@/lib/api";
import type { DatabaseEngineDescriptor, ListResponse } from "@/lib/types";
import { PostgresInstances } from "./_components/postgres-instances";
import { MongoInstances } from "./_components/mongo-instances";
import "./_databases.scss";

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
    <Page>
      <PageHeader
        title="Databases"
        description="Manage your database engines. Pick an engine below to install and administer instances."
      />

      <Tabs>
        <TabList aria-label="Database engines">
          {tabs.map((e) => (
            <Tab key={e.key}>{e.label}</Tab>
          ))}
        </TabList>
        <TabPanels>
          {tabs.map((e) => (
            <TabPanel key={e.key}>{ENGINE_VIEWS[e.key]?.()}</TabPanel>
          ))}
        </TabPanels>
      </Tabs>
    </Page>
  );
}
