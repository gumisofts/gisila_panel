import type { ReactNode } from "react";
import { SelectItem, SelectItemGroup } from "@carbon/react";
import type { Application, ApplicationDef } from "@/lib/types";

/// Options for a runtime's version dropdown, sourced from the Application
/// catalog. Versions already on the host come first: picking one that is not
/// installed still works, it just makes the first deploy wait for the
/// toolchain to be installed lazily. `current` is always offered so the
/// select is never empty while the catalog is still loading.
export function versionItems(
  key: string,
  current: string,
  applications: Application[] | undefined,
  catalog: ApplicationDef[] | undefined,
): ReactNode[] {
  const onHost =
    applications
      ?.find((a) => a.key === key)
      ?.versions.filter((v) => v.status === "installed")
      .map((v) => v.version) ?? [];
  const rest = (
    catalog?.find((d) => d.key === key)?.availableVersions ?? []
  ).filter((v) => !onHost.includes(v));

  const items: ReactNode[] = [];
  if (current && !onHost.includes(current) && !rest.includes(current)) {
    items.push(<SelectItem key={current} value={current} text={current} />);
  }
  if (onHost.length > 0) {
    items.push(
      <SelectItemGroup key="installed" label="Installed on this server">
        {onHost.map((v) => (
          <SelectItem key={v} value={v} text={v} />
        ))}
      </SelectItemGroup>,
    );
  }
  if (rest.length > 0) {
    items.push(
      <SelectItemGroup key="available" label="Available — installed on first deploy">
        {rest.map((v) => (
          <SelectItem key={v} value={v} text={v} />
        ))}
      </SelectItemGroup>,
    );
  }
  return items;
}
