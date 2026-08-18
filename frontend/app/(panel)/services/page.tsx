"use client";

import { useEffect, useState } from "react";
import RouterLink from "@/compat/link";
import useSWR, { mutate } from "swr";
import {
  Add,
  ArrowRight,
  DataBase,
  Email,
  Grid as GridIcon,
  Launch,
  Network_1,
  ServerProxy,
} from "@carbon/icons-react";
import {
  Button,
  ClickableTile,
  Column,
  Grid,
  InlineLoading,
  InlineNotification,
  Link as CarbonLink,
  Modal,
  NumberInput,
  PasswordInput,
  Select,
  SelectItem,
  SkeletonText,
  Stack,
  Tag,
  TextInput,
  Tile,
  Toggle,
} from "@carbon/react";
import { Page, PageHeader, PageSection } from "@/components/page";
import { HealthBadge } from "@/components/health-badge";
import { api, fetcher } from "@/lib/api";
import { usePermissions } from "@/lib/permissions";
import type {
  ConfigField,
  HealthStatus,
  ListResponse,
  ManagedService,
  ServiceDef,
} from "@/lib/types";
import "./_services.scss";

// ── Helpers ───────────────────────────────────────────────────────────────────

/// ClickableTile renders Carbon's polymorphic Link and forwards unknown props to
/// it, but its own props are typed against an anchor, so `as` — how the tile is
/// handed to react-router instead of doing a document navigation — is declared
/// here.
const RouterTile = ClickableTile as React.ComponentType<
  React.ComponentProps<typeof ClickableTile> & { as?: React.ElementType }
>;

const STATUS_LABEL: Record<string, string> = {
  running:      "Running",
  config_only:  "Active",
  stopped:      "Stopped",
  failed:       "Failed",
  installing:   "Installing…",
  uninstalling: "Removing…",
  pending:      "Pending…",
};

/// Statuses the backend is still working through — these show a spinner rather
/// than a settled tag.
const IN_PROGRESS = ["installing", "uninstalling", "pending"];

const STATUS_TAG: Record<string, "green" | "red" | "magenta"> = {
  running:     "green",
  config_only: "green",
  stopped:     "magenta",
  failed:      "red",
};

function StatusIndicator({ status }: { status: string }) {
  const label = STATUS_LABEL[status] ?? status;
  if (IN_PROGRESS.includes(status)) {
    return <InlineLoading status="active" description={label} />;
  }
  return (
    <Tag type={STATUS_TAG[status] ?? "cool-gray"} size="sm">
      {label}
    </Tag>
  );
}

const CATEGORY_ICON: Record<string, typeof ServerProxy> = {
  cache: DataBase,
  email: Email,
  queue: GridIcon,
  database: Network_1,
};

const SERVICE_CATEGORY: Record<string, string> = {
  redis: "cache", memcached: "cache",
  smtp: "email", mailpit: "email",
  pgbouncer: "database",
};

function CategoryIcon({ category }: { category: string }) {
  const Icon = CATEGORY_ICON[category] ?? ServerProxy;
  return (
    <span className="gisila-catalog__icon">
      <Icon size={20} />
    </span>
  );
}

/** Pull the most useful config key-values to surface on the card, driven by the
 *  catalog [def] (its summaryKeys + field labels). Falls back to the first few
 *  config values when the def is unavailable. */
function summaryFields(
  config: Record<string, string>,
  def?: ServiceDef,
): { label: string; value: string }[] {
  const pairs: { label: string; value: string }[] = [];

  if (def && def.summaryKeys && def.summaryKeys.length > 0) {
    for (const key of def.summaryKeys) {
      const v = config[key];
      if (!v) continue;
      const field = def.configSchema.find((f) => f.key === key);
      pairs.push({
        label: field?.label ?? key,
        value: field?.secret ? "••••••••" : v,
      });
    }
  } else {
    // No summaryKeys declared — show the first few non-empty values generically.
    for (const [k, v] of Object.entries(config).slice(0, 3)) {
      if (v) pairs.push({ label: k, value: v });
    }
  }

  return pairs.slice(0, 4);
}

// ── Page ─────────────────────────────────────────────────────────────────────

export default function ServicesPage() {
  const { data: catalogData } = useSWR<ListResponse<ServiceDef>>(
    "/services/catalog",
    fetcher,
  );
  const { data: installedData, isLoading } = useSWR<
    ListResponse<ManagedService>
  >("/services/", fetcher, { refreshInterval: 4000 });

  const catalog  = catalogData?.results  ?? [];
  const installed = installedData?.results ?? [];

  // Map service type → installed service (one per type enforced by backend).
  const installedByType = new Map(installed.map((s) => [s.serviceType, s]));
  // Map service type → catalog def, so installed cards render generically.
  const defsByType = new Map(catalog.map((d) => [d.type, d]));

  return (
    <Page>
      <PageHeader
        title="Services"
        description="Host-level services managed by your panel."
      />

      <PageSection>
        {isLoading ? (
          <SkeletonTiles />
        ) : installed.length === 0 ? (
          <Tile className="gisila-empty">
            No services installed yet — pick one from the catalog below.
          </Tile>
        ) : (
          <Grid fullWidth withRowGap className="gisila-catalog__grid">
            {installed.map((svc) => (
              <Column key={svc.id} sm={4} md={4} lg={8}>
                <InstalledTile
                  svc={svc}
                  def={defsByType.get(svc.serviceType)}
                />
              </Column>
            ))}
          </Grid>
        )}
      </PageSection>

      <PageSection title="Available services">
        <Grid fullWidth withRowGap className="gisila-catalog__grid">
          {catalog.map((def) => (
            <Column key={def.type} sm={4} md={4} lg={8}>
              <CatalogTile def={def} installed={installedByType.get(def.type)} />
            </Column>
          ))}
        </Grid>
      </PageSection>
    </Page>
  );
}

// ── Installed tile ────────────────────────────────────────────────────────────

function InstalledTile({ svc, def }: { svc: ManagedService; def?: ServiceDef }) {
  const config: Record<string, string> = (() => {
    try { return JSON.parse(svc.config) as Record<string, string>; }
    catch { return {}; }
  })();

  const details = summaryFields(config, def);
  const category = def?.category ?? SERVICE_CATEGORY[svc.serviceType] ?? "";

  // Only services with something on the host to probe (apt + systemd) get a
  // live health check — config-only services (e.g. pgAdmin behind the panel
  // itself) have no daemon for HealthMonitorWorker to check.
  const { data: health } = useSWR<HealthStatus>(
    def?.requiresInstall ? `/services/${svc.id}/health` : null,
    fetcher,
    { refreshInterval: 30_000 },
  );

  return (
    <RouterTile as={RouterLink} href={`/services/${svc.id}`}>
      <Stack gap={4}>
        <div className="gisila-catalog__row">
          <div className="gisila-catalog__ident">
            <CategoryIcon category={category} />
            <div>
              <p className="gisila-catalog__name">{svc.displayName}</p>
              <p className="gisila-catalog__key">{svc.serviceType}</p>
            </div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "0.5rem" }}>
            <HealthBadge health={health} />
            <StatusIndicator status={svc.status} />
          </div>
        </div>

        {details.length > 0 && (
          <div className="gisila-catalog__summary">
            {details.map(({ label, value }) => (
              <div key={label} className="gisila-catalog__summary-item">
                <span className="gisila-catalog__summary-label">{label}</span>
                <span className="gisila-catalog__summary-value">{value}</span>
              </div>
            ))}
          </div>
        )}

        {svc.errorMessage && (
          <p className="gisila-catalog__error">{svc.errorMessage}</p>
        )}

        <div className="gisila-catalog__row">
          <span className="gisila-catalog__meta">
            {svc.installedAt
              ? `Installed ${new Date(svc.installedAt).toLocaleDateString()}`
              : ""}
          </span>
          <span className="gisila-catalog__cta">
            Configure
            <ArrowRight size={16} />
          </span>
        </div>
      </Stack>
    </RouterTile>
  );
}

// ── Catalog tile ──────────────────────────────────────────────────────────────

function requiredInstallFields(def: ServiceDef): ConfigField[] {
  return def.configSchema.filter((f) => f.required && !f.default);
}

function CatalogTile({
  def,
  installed,
}: {
  def: ServiceDef;
  installed?: ManagedService;
}) {
  const [installing, setInstalling] = useState(false);
  const [error, setError] = useState("");
  const [showForm, setShowForm] = useState(false);
  const { isSuperuser } = usePermissions();

  const isInstalled = !!installed;
  const needsConfig = requiredInstallFields(def).length > 0;

  async function submitInstall(config: Record<string, string>) {
    if (isInstalled || installing) return;
    setError("");
    setInstalling(true);
    try {
      await api("/services/", {
        method: "POST",
        body: JSON.stringify({
          serviceType: def.type,
          displayName: def.name,
          config,
        }),
      });
      mutate("/services/");
      setShowForm(false);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Install failed.");
    } finally {
      setInstalling(false);
    }
  }

  function onInstallClick() {
    if (needsConfig) {
      setError("");
      setShowForm(true);
      return;
    }
    void submitInstall({});
  }

  return (
    <Tile
      className={isInstalled ? "gisila-catalog__tile--installed" : undefined}
    >
      <Stack gap={4}>
        <div className="gisila-catalog__row">
          <div className="gisila-catalog__ident">
            <CategoryIcon category={def.category} />
            <div>
              <p className="gisila-catalog__name">{def.name}</p>
              <Tag type="cool-gray" size="sm">
                {def.category}
              </Tag>
            </div>
          </div>

          {def.docsUrl && (
            <CarbonLink
              href={def.docsUrl}
              target="_blank"
              rel="noopener noreferrer"
              renderIcon={Launch}
              size="sm"
              onClick={(e) => e.stopPropagation()}
            >
              Docs
            </CarbonLink>
          )}
        </div>

        <p className="gisila-catalog__desc">{def.description}</p>

        {error && !showForm && (
          <InlineNotification
            kind="error"
            lowContrast
            hideCloseButton
            title={error}
          />
        )}

        <div className="gisila-catalog__row">
          <span className="gisila-catalog__summary-label">
            {def.requiresInstall ? "apt + systemd" : "config only"}
          </span>

          {isInstalled ? (
            <CarbonLink
              as={RouterLink}
              href={`/services/${installed.id}`}
              renderIcon={ArrowRight}
              size="sm"
            >
              Installed · View
            </CarbonLink>
          ) : isSuperuser ? (
            installing && !showForm ? (
              <InlineLoading status="active" />
            ) : (
              <Button
                size="sm"
                kind="tertiary"
                renderIcon={Add}
                onClick={onInstallClick}
              >
                {def.requiresInstall ? "Install" : "Configure"}
              </Button>
            )
          ) : null}
        </div>
      </Stack>

      {needsConfig && (
        <InstallConfigModal
          open={showForm}
          def={def}
          installing={installing}
          error={error}
          onClose={() => {
            if (!installing) setShowForm(false);
          }}
          onSubmit={submitInstall}
        />
      )}
    </Tile>
  );
}

function InstallConfigModal({
  open,
  def,
  installing,
  error,
  onClose,
  onSubmit,
}: {
  open: boolean;
  def: ServiceDef;
  installing: boolean;
  error: string;
  onClose: () => void;
  onSubmit: (config: Record<string, string>) => Promise<void>;
}) {
  const [values, setValues] = useState<Record<string, string>>({});

  useEffect(() => {
    if (!open) return;
    setValues(
      Object.fromEntries(
        def.configSchema.map((f) => [f.key, f.default ?? ""]),
      ),
    );
  }, [open, def]);

  function set(key: string, value: string) {
    setValues((p) => ({ ...p, [key]: value }));
  }

  const missing = requiredInstallFields(def).filter(
    (f) => !(values[f.key] ?? "").trim(),
  );

  return (
    <Modal
      open={open}
      modalHeading={`Install ${def.name}`}
      primaryButtonText={installing ? "Installing…" : "Install"}
      secondaryButtonText="Cancel"
      primaryButtonDisabled={installing || missing.length > 0}
      onRequestClose={onClose}
      onRequestSubmit={() => {
        void onSubmit(values);
      }}
      size="md"
    >
      <Stack gap={5}>
        <p className="gisila-catalog__desc">
          This service needs a few settings before install.
        </p>
        {def.configSchema.map((field) => (
          <InstallField
            key={field.key}
            field={field}
            value={values[field.key] ?? ""}
            onChange={(v) => set(field.key, v)}
          />
        ))}
        {error && (
          <InlineNotification
            kind="error"
            lowContrast
            hideCloseButton
            title={error}
          />
        )}
      </Stack>
    </Modal>
  );
}

function InstallField({
  field,
  value,
  onChange,
}: {
  field: ConfigField;
  value: string;
  onChange: (v: string) => void;
}) {
  const label = (
    <span className="gisila-label">
      {field.label}
      {field.required && <span className="gisila-required">*</span>}
    </span>
  );

  if (field.type === "boolean") {
    return (
      <Toggle
        id={`install-${field.key}`}
        labelText={field.label}
        labelA="Off"
        labelB="On"
        toggled={value === "true"}
        onToggle={(checked) => onChange(checked ? "true" : "false")}
      />
    );
  }

  if (field.type === "select") {
    return (
      <Select
        id={`install-${field.key}`}
        labelText={label}
        helperText={field.hint}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      >
        {field.options?.map((opt) => (
          <SelectItem key={opt} value={opt} text={opt} />
        ))}
      </Select>
    );
  }

  if (field.type === "password") {
    return (
      <PasswordInput
        id={`install-${field.key}`}
        labelText={label}
        helperText={field.hint}
        value={value}
        placeholder={field.placeholder ?? field.default}
        onChange={(e) => onChange(e.target.value)}
      />
    );
  }

  if (field.type === "number") {
    return (
      <NumberInput
        id={`install-${field.key}`}
        label={label}
        helperText={field.hint}
        value={value}
        min={field.min}
        max={field.max}
        allowEmpty
        onChange={(_event, { value: next }) => onChange(String(next))}
      />
    );
  }

  return (
    <TextInput
      id={`install-${field.key}`}
      labelText={label}
      helperText={field.hint}
      value={value}
      placeholder={field.placeholder ?? field.default}
      onChange={(e) => onChange(e.target.value)}
    />
  );
}

function SkeletonTiles() {
  return (
    <Grid fullWidth withRowGap className="gisila-catalog__grid">
      {[0, 1, 2].map((i) => (
        <Column key={i} sm={4} md={4} lg={8}>
          <Tile>
            <SkeletonText paragraph lineCount={3} />
          </Tile>
        </Column>
      ))}
    </Grid>
  );
}
