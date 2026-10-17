"use client";

import {
  InlineNotification,
  StructuredListBody,
  StructuredListCell,
  StructuredListHead,
  StructuredListRow,
  StructuredListWrapper,
} from "@carbon/react";
import { WarningAlt } from "@carbon/icons-react";
import Link from "@/compat/link";
import { formatRelative } from "@/lib/utils";
import { type BuildStamp, useServerInfo } from "@/components/server-ip";

/// The UI bundle's own stamp (vite.config.ts `define`).
const UI: BuildStamp = {
  version: __GISILA_UI_VERSION__,
  commit: __GISILA_UI_COMMIT__,
  builtAt: __GISILA_UI_BUILT_AT__,
};

interface Component {
  name: string;
  stamp: BuildStamp | null;
}

/// Panel, agent and UI — the three things deployed separately — and which of
/// them were built from a different commit than the panel API.
function useComponents() {
  const { data } = useServerInfo();
  const panel = data?.version?.panel ?? null;
  const components: Component[] = [
    { name: "Panel (API + worker)", stamp: panel },
    { name: "Agent", stamp: data?.version?.agent ?? null },
    { name: "Web UI", stamp: UI },
  ];
  // Only commits both sides know are compared — a dev build has none.
  const outOfStep = panel?.commit
    ? components.filter(
        (c) => c.stamp?.commit && c.stamp.commit !== panel.commit,
      )
    : [];
  return { loaded: !!data, panel, components, outOfStep };
}

/// One line at the foot of the side nav; links to the About section.
export function VersionFooter() {
  const { panel, outOfStep } = useComponents();
  const version = panel?.version ?? UI.version;
  return (
    <Link href="/settings#about" className="gisila-version-footer">
      {outOfStep.length > 0 && (
        <WarningAlt size={16} aria-label="Components out of step" />
      )}
      <span>Gisila Panel {version}</span>
    </Link>
  );
}

/// Full build details for the Settings page.
export function AboutVersions() {
  const { loaded, components, outOfStep } = useComponents();
  return (
    <>
      {outOfStep.length > 0 && (
        <InlineNotification
          kind="warning"
          lowContrast
          hideCloseButton
          title="Components are out of step"
          subtitle={`${outOfStep.map((c) => c.name).join(" and ")} ${
            outOfStep.length === 1 ? "was" : "were"
          } built from a different commit than the panel. Redeploy so they match — a newer panel can call agent options an older agent doesn't have.`}
        />
      )}
      <StructuredListWrapper isCondensed>
        <StructuredListHead>
          <StructuredListRow head>
            <StructuredListCell head>Component</StructuredListCell>
            <StructuredListCell head>Version</StructuredListCell>
            <StructuredListCell head>Commit</StructuredListCell>
            <StructuredListCell head>Built</StructuredListCell>
          </StructuredListRow>
        </StructuredListHead>
        <StructuredListBody>
          {components.map(({ name, stamp }) => (
            <StructuredListRow key={name}>
              <StructuredListCell>{name}</StructuredListCell>
              <StructuredListCell>
                <code>{stamp?.version ?? (loaded ? "unknown" : "…")}</code>
              </StructuredListCell>
              <StructuredListCell>
                <code>{stamp?.commit || "—"}</code>
              </StructuredListCell>
              <StructuredListCell>
                {stamp?.builtAt ? formatRelative(stamp.builtAt) : "—"}
              </StructuredListCell>
            </StructuredListRow>
          ))}
        </StructuredListBody>
      </StructuredListWrapper>
    </>
  );
}
