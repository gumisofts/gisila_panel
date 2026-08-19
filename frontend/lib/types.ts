export type ID = number;

export interface User {
  id: ID;
  email: string;
  firstName?: string | null;
  lastName?: string | null;
  isActive: boolean;
  isStaff: boolean;
  isSuperuser: boolean;
  avatarUrl?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export type Role = "viewer" | "developer" | "admin" | "owner";

export interface Team {
  id: ID;
  name: string;
  slug: string;
  ownerId: ID;
  plan: string;
  createdAt: string;
  /** The current user's role in this team (added by the API on list). */
  myRole?: Role;
}

export interface AuditLog {
  id: ID;
  actorId?: ID | null;
  teamId?: ID | null;
  action: string;
  targetType?: string | null;
  targetId?: string | null;
  ipAddress?: string | null;
  userAgent?: string | null;
  data?: string | null;
  createdAt: string;
}

export interface Project {
  id: ID;
  teamId: ID;
  name: string;
  slug: string;
  description?: string | null;
  createdAt: string;
}

export type AppStatus =
  | "created"
  | "building"
  | "running"
  | "stopped"
  | "failed"
  | "crashed"
  | "deleting";

export interface App {
  id: ID;
  projectId: ID;
  name: string;
  slug: string;
  linuxUser: string;
  workDir: string;
  internalPort: number;
  // The installed Application this app deploys against. `runtime` is kept
  // in sync with `application.key` for backward compatibility.
  applicationId?: ID | null;
  deploymentMode?: DeployMode | null;
  runtime: string;
  sourceType: "binary" | "git" | "zip";
  gitUrl?: string | null;
  gitBranch?: string | null;
  // Optional subdirectory within the repo to build/run from, so a single
  // monorepo can be deployed by pointing at just one of its projects.
  sourceSubdir?: string | null;
  buildCommand?: string | null;
  startCommand?: string | null;
  healthCheckPath?: string | null;
  pythonVersion?: string | null;
  pythonMode?: "wsgi" | "asgi" | null;
  wsgiApp?: string | null;
  gunicornWorkers?: number | null;
  gunicornThreads?: number | null;
  gunicornTimeout?: number | null;
  gunicornBind?: string | null;
  gunicornExtraArgs?: string | null;
  // Runtime version pins
  nodeVersion?: string | null;
  dartVersion?: string | null;
  goVersion?: string | null;
  rustVersion?: string | null;
  bunVersion?: string | null;
  // Celery-specific
  celeryApp?: string | null;
  celeryWorkerCount?: number | null;
  celeryConcurrency?: number | null;
  celeryQueues?: string | null;
  celeryBeatEnabled?: boolean | null;
  celeryExtraArgs?: string | null;
  // Static site
  staticRoot?: string | null;
  staticSpa?: boolean | null;
  // Local disk media (Model A)
  mediaEnabled?: boolean | null;
  mediaMaxUploadMb?: number | null;
  deployKeyId?: number | null;
  // Network exposure. Set at creation, immutable afterward.
  //   web      — Nginx reverse proxy + optional Domain/TLS (default).
  //   tcp      — direct port, no Nginx/domain; publiclyReachable controls
  //              whether the host firewall has the port open.
  //   internal — no public exposure at all.
  exposeMode: ExposeMode;
  // Only meaningful when exposeMode === "tcp". Editable post-creation via
  // POST /apps/{id}/network.
  publiclyReachable?: boolean | null;
  memoryMbLimit: number;
  cpuQuotaPercent: number;
  tasksLimit: number;
  status: AppStatus;
  lastDeployedAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export interface EnvVar {
  id: ID;
  appId: ID;
  name: string;
  value?: string | null;
  isSecret: boolean;
  updatedAt: string;
}

export type DeploymentStatus =
  | "queued"
  | "building"
  | "deploying"
  | "succeeded"
  | "failed"
  | "rolled_back";

export interface Deployment {
  id: ID;
  appId: ID;
  triggeredById?: ID | null;
  sourceType: string;
  gitCommitSha?: string | null;
  artifactPath?: string | null;
  status: DeploymentStatus;
  failureReason?: string | null;
  isActive: boolean;
  startedAt?: string | null;
  finishedAt?: string | null;
  createdAt: string;
}

export interface Domain {
  id: ID;
  appId: ID;
  hostname: string;
  isPrimary: boolean;
  isVerified: boolean;
  sslStatus: "none" | "pending" | "issued" | "expired" | "failed";
  sslExpiresAt?: string | null;
  sslIssuer?: string | null;
  createdAt: string;
}

export interface MetricSample {
  id: ID;
  appId: ID;
  cpuPercent: number;
  memBytes: number;
  rssBytes: number;
  sampledAt: string;
}

// `GET /apps/metrics-summary` — the latest fresh (<5 min old) sample per
// running app, joined with the quota it's measured against. `cpuPercent` is
// basis points relative to one core, same unit as `MetricSample.cpuPercent`.
export interface AppUsage {
  appId: ID;
  name: string;
  status: AppStatus;
  cpuPercent: number;
  memBytes: number;
  memoryMbLimit: number;
  cpuQuotaPercent: number;
  sampledAt: string;
}

export interface ApiToken {
  id: ID;
  name: string;
  prefix: string;
  lastUsedAt?: string | null;
  expiresAt?: string | null;
  createdAt: string;
}

export interface SshKey {
  id: ID;
  name: string;
  algorithm?: string | null;
  fingerprint: string;
  publicKey: string;
  isDeployKey?: boolean;
  createdAt: string;
}

export type SshKeyAlgorithm = 'ed25519' | 'rsa-4096' | 'rsa-2048' | 'ecdsa-p256' | 'ecdsa-p384';

export interface BuildLog {
  id: ID;
  deploymentId: ID;
  line: string;
  stream: "stdout" | "stderr" | "system";
  createdAt: string | null;
}

export interface ListResponse<T> {
  results: T[];
  // Total matching rows, independent of how many `results` came back on this
  // page. Only endpoints that support `limit`/`offset` (e.g. `/audit/`)
  // populate this; unpaginated list endpoints omit it.
  count?: number;
}

// ── Runtimes (language stacks) ────────────────────────────────────────────────
//
// An Application is an installable runtime/language stack (Python, Dart,
// Node, …) managed independently of the panel itself — see the Runtimes
// section. Apps pick one of the *installed* runtimes as their deployment target.

export type DeployMode = "build_execute" | "direct_run" | "static_publish";

export type ApplicationStatus =
  | "pending"
  | "installing"
  | "installed"
  | "updating"
  | "removing"
  | "disabled"
  | "failed";

export interface ApplicationDef {
  key: string;
  displayName: string;
  description: string;
  deployModes: DeployMode[];
  defaultDeployMode: DeployMode;
  /** Whether several versions can be installed side by side (Python via
   *  pyenv, Node via fnm, …). False for static/binary/zig/celery. */
  versioned: boolean;
  /** Curated installable versions, newest first. Empty when not versioned. */
  availableVersions: string[];
  defaultVersion?: string | null;
  defaultBuildCommand?: string | null;
  defaultStartCommand?: string | null;
  versionHint?: string | null;
  docsUrl?: string | null;
}

export type ApplicationVersionStatus =
  | "pending"
  | "installing"
  | "installed"
  | "removing"
  | "failed";

/** One installed toolchain version of an Application. Versioned Applications
 *  can have several of these at once. */
export interface ApplicationVersion {
  id: ID;
  applicationId: ID;
  version: string;
  status: ApplicationVersionStatus;
  /** The version new apps get when they don't pin one themselves. */
  isDefault: boolean;
  errorMessage?: string | null;
  installedAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export interface Application {
  id: ID;
  key: string;
  displayName: string;
  deployModes: string; // csv, e.g. "build_execute,direct_run"
  defaultDeployMode: DeployMode;
  /** Kept in sync with whichever version is marked default. */
  defaultVersion?: string | null;
  defaultBuildCommand?: string | null;
  defaultStartCommand?: string | null;
  status: ApplicationStatus;
  isBuiltin?: boolean;
  errorMessage?: string | null;
  installedAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
  /** Installed versions, always present on list and retrieve. Empty for
   *  unversioned Applications. */
  versions: ApplicationVersion[];
  _def?: ApplicationDef; // injected by the retrieve endpoint
}

export const DEPLOY_MODE_LABEL: Record<DeployMode, string> = {
  build_execute: "Build → Execute",
  direct_run: "Direct Run",
  static_publish: "Static Publish",
};

export type ExposeMode = "web" | "tcp" | "internal";

export const EXPOSE_MODE_LABEL: Record<ExposeMode, string> = {
  web: "Web",
  tcp: "TCP service",
  internal: "Internal only",
};

// ── Managed services ─────────────────────────────────────────────────────────

export type ServiceStatus =
  | "pending"
  | "installing"
  | "running"
  | "stopped"
  | "failed"
  | "uninstalling"
  | "config_only";

export type FieldType = "string" | "password" | "number" | "boolean" | "select";

export interface ConfigField {
  key: string;
  label: string;
  type: FieldType;
  default?: string;
  placeholder?: string;
  hint?: string;
  required: boolean;
  secret: boolean;
  options?: string[];
  min?: number;
  max?: number;
}

export interface ServiceDef {
  type: string;
  name: string;
  description: string;
  category: "cache" | "email" | "queue" | "database";
  requiresInstall: boolean;
  docsUrl?: string;
  /** Config keys to surface on the installed-service card. */
  summaryKeys?: string[];
  configSchema: ConfigField[];
}

// PgBouncer repeating config structures (stored as JSON strings in the service
// config blob under the `databases` and `users` keys).
export interface PgbDatabase {
  name: string;
  host: string;
  port: string;
  dbname: string;
  user?: string;
  password?: string;
  pool_size?: string;
}

export interface PgbUser {
  username: string;
  password: string;
}

// ── PostgreSQL ────────────────────────────────────────────────────────────────

export type PgInstanceStatus =
  | "pending"
  | "installing"
  | "running"
  | "stopped"
  | "failed"
  | "uninstalling";

export type PgDatabaseStatus = "pending" | "active" | "failed" | "dropped";

export interface PostgresInstance {
  id: ID;
  version: number;
  displayName: string;
  port: number;
  status: PgInstanceStatus;
  isDefault: boolean;
  /** Publicly reachable over TLS at publicDomain:port (sslmode=verify-full). */
  isPublic?: boolean;
  publicDomain?: string | null;
  /** The always-available cluster that backs the panel itself. Its port is
   *  fixed and it cannot be stopped or uninstalled. */
  isSystem?: boolean;
  /** Host the instance is reachable at. Always 127.0.0.1 except for a system
   *  database that database.yaml points at another machine. */
  host?: string;
  /** Whether the instance runs on the panel's host and can therefore be
   *  operated from here — databases, roles, settings, backups, exposure. False
   *  only for a remote system database, which the panel can read but not
   *  manage. */
  isManaged?: boolean;
  dataDirectory?: string | null;
  errorMessage?: string | null;
  installedAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export interface PgConnectionInfo {
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  url: string;
  /** Present when the instance is publicly exposed over TLS. */
  publicHost?: string | null;
  publicUrl?: string | null;
}

export interface PostgresDatabase {
  id: ID;
  instanceId: ID;
  dbName: string;
  roleName: string;
  extensions: string[];
  roleAttributes: string[]; // granted Postgres role attributes (CREATEDB, …)
  status: PgDatabaseStatus;
  errorMessage?: string | null;
  createdAt: string;
  updatedAt?: string | null;
  connection?: PgConnectionInfo; // present on create + retrieve
}

// ── MongoDB ───────────────────────────────────────────────────────────────────

export type MongoInstanceStatus = PgInstanceStatus;
export type MongoDatabaseStatus = PgDatabaseStatus;

export interface MongoInstance {
  id: ID;
  engine?: "mongodb";
  version: string; // "6.0" | "7.0" | "8.0"
  displayName: string;
  port: number;
  status: MongoInstanceStatus;
  isDefault: boolean;
  isPublic?: boolean;
  publicDomain?: string | null;
  dataDirectory?: string | null;
  errorMessage?: string | null;
  installedAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export interface MongoConnectionInfo {
  host: string;
  port: number;
  database: string;
  username: string;
  password: string;
  authSource: string;
  url: string;
  publicHost?: string | null;
  publicUrl?: string | null;
}

export interface MongoDatabase {
  id: ID;
  instanceId: ID;
  dbName: string;
  userName: string;
  roles: string[]; // granted built-in roles (readWrite, dbAdmin, …)
  status: MongoDatabaseStatus;
  errorMessage?: string | null;
  createdAt: string;
  updatedAt?: string | null;
  connection?: MongoConnectionInfo; // present on create + retrieve
}

// Mongo backups/schedules are structurally identical to the Postgres ones.
export type MongoBackup = PgBackup;
export type MongoBackupSchedule = PgBackupSchedule;

/** Descriptor served by GET /db-engines, used to render the Databases UI
 *  generically across engines. */
export interface DatabaseEngineDescriptor {
  key: string; // 'postgres' | 'mongodb'
  label: string;
  kind: "sql" | "nosql";
  apiBase: string; // '/databases' | '/mongo'
  versions: string[];
  defaultVersion: string;
  capabilities: Record<string, boolean>;
  userRoleOptions: string[];
  backupScopes: string[];
  terms: Record<string, string>;
  docsUrl?: string;
}

export interface ManagedService {
  id: ID;
  serviceType: string;
  displayName: string;
  status: ServiceStatus;
  config: string; // JSON string
  errorMessage?: string | null;
  installedAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
  _def?: ServiceDef; // injected by the retrieve endpoint
}

export interface MailStatus {
  installed: boolean;
}

// ── Database backups ──────────────────────────────────────────────────────────

export type PgBackupScope = "full" | "schema" | "data";
export type PgBackupStatus = "pending" | "running" | "completed" | "failed";
export type PgBackupTrigger = "manual" | "scheduled";
export type PgBackupFrequency = "hourly" | "daily" | "weekly";

export interface PgBackup {
  id: ID;
  databaseId: ID;
  fileName?: string | null;
  sizeBytes?: number | null;
  scope: PgBackupScope;
  status: PgBackupStatus;
  trigger: PgBackupTrigger;
  errorMessage?: string | null;
  startedAt?: string | null;
  completedAt?: string | null;
  createdAt: string;
}

export interface PgBackupSchedule {
  id: ID;
  databaseId: ID;
  enabled: boolean;
  frequency: PgBackupFrequency;
  hour: number;
  minute: number;
  weekday?: number | null;
  scope: PgBackupScope;
  keepCount: number;
  nextRunAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export interface MailDomain {
  id: ID;
  domain: string;
  mailHostname: string;
  dkimSelector?: string | null;
  dkimConfigured: boolean;
  dmarcPolicy: "none" | "quarantine" | "reject";
  publicIp?: string | null;
  isActive: boolean;
  createdAt: string;
}

export interface MailConnectionEndpoint {
  port: number;
  security: string;
}

export interface MailConnectionSettings {
  host: string;
  username: string;
  smtp: { host: string; starttls: MailConnectionEndpoint; ssl: MailConnectionEndpoint };
  imap: { host: string; ssl: MailConnectionEndpoint; starttls: MailConnectionEndpoint };
  pop3: { host: string; ssl: MailConnectionEndpoint; starttls: MailConnectionEndpoint };
}

export interface MailAccount {
  id: ID;
  mailDomainId: ID;
  address: string;
  quotaMb?: number | null;
  isActive: boolean;
  createdAt: string;
  updatedAt?: string | null;
  connection: MailConnectionSettings;
}

export interface MailDnsRecord {
  type: "A" | "MX" | "TXT";
  host: string;
  value: string;
  priority?: number;
  label?: string;
  note?: string;
}

export interface MailDnsResponse {
  domain: string;
  mailHostname: string;
  publicIp?: string | null;
  dkimConfigured: boolean;
  records: MailDnsRecord[];
}

// ── Object storage (Model B) ──────────────────────────────────────────────────

export type StorageProviderKind = "minio" | "external";

export type StorageProviderStatus =
  | "pending"
  | "installing"
  | "running"
  | "stopped"
  | "failed"
  | "uninstalling"
  | "config_only";

export interface StorageProvider {
  id: ID;
  kind: StorageProviderKind;
  displayName: string;
  endpoint: string;
  region?: string | null;
  publicUrl?: string | null;
  consoleUrl?: string | null;
  forcePathStyle: boolean;
  consolePort?: number | null;
  status: StorageProviderStatus;
  errorMessage?: string | null;
  installedAt?: string | null;
  createdAt: string;
  updatedAt?: string | null;
}

export type StorageBucketStatus = "pending" | "active" | "failed" | "deleted";

export interface BucketConnectionInfo {
  endpoint: string;
  region: string;
  bucket: string;
  accessKey: string;
  secretKey: string;
  publicUrl?: string | null;
  forcePathStyle: boolean;
}

export interface StorageBucket {
  id: ID;
  providerId: ID;
  bucketName: string;
  isPublic: boolean;
  status: StorageBucketStatus;
  errorMessage?: string | null;
  connection?: BucketConnectionInfo;
  createdAt: string;
  updatedAt?: string | null;
}

export interface AppStorageLink {
  id: ID;
  appId: ID;
  bucketId: ID;
  envPrefix: string;
  bucketName: string;
  providerName: string;
  providerKind: StorageProviderKind;
  envVars: string[];
  createdAt: string;
}

// ── Notifications & alerting ─────────────────────────────────────────────────
//
// Threshold-based alerting on whole-host resources, per-app quota usage, and
// managed database health, delivered via the in-panel notification inbox and
// (optionally) email through a panel-wide SMTP config.

export type AlertScope =
  | "system"
  | "app"
  | "postgres"
  | "mongo"
  | "mail"
  | "service"
  | "runtime";

export type AlertMetric =
  | "cpu_percent"
  | "memory_percent"
  | "disk_percent"
  | "connections_percent"
  | "status_down";

export type AlertComparison = "gte" | "lte";
export type AlertSeverity = "warning" | "critical";
export type AlertEventStatus = "firing" | "resolved";
export type NotificationLevel = "info" | "warning" | "critical";
export type SmtpSecurity = "none" | "starttls" | "ssl";

export interface SmtpConfig {
  id: ID;
  smtpHost?: string | null;
  smtpPort: number;
  smtpUsername?: string | null;
  // Never populated by the API (write-only) — an empty value on save means
  // "leave the stored password alone".
  smtpPassword?: string | null;
  smtpSecurity: SmtpSecurity;
  fromEmail?: string | null;
  fromName: string;
  emailEnabled: boolean;
  createdAt: string;
  updatedAt?: string | null;
}

export interface AlertRule {
  id: ID;
  scope: AlertScope;
  appId?: ID | null;
  postgresInstanceId?: ID | null;
  mongoInstanceId?: ID | null;
  managedServiceId?: ID | null;
  applicationId?: ID | null;
  metric: AlertMetric;
  comparison: AlertComparison;
  thresholdPercent?: number | null;
  severity: AlertSeverity;
  cooldownMinutes: number;
  enabled: boolean;
  notifyEmail: boolean;
  lastTriggeredAt?: string | null;
  createdById?: ID | null;
  createdAt: string;
  updatedAt?: string | null;
}

export interface AlertEvent {
  id: ID;
  ruleId: ID;
  scope: AlertScope;
  appId?: ID | null;
  postgresInstanceId?: ID | null;
  mongoInstanceId?: ID | null;
  managedServiceId?: ID | null;
  applicationId?: ID | null;
  metric: AlertMetric;
  observedPercent?: number | null;
  thresholdPercent?: number | null;
  severity: AlertSeverity;
  message: string;
  status: AlertEventStatus;
  resolvedAt?: string | null;
  emailSentAt?: string | null;
  emailError?: string | null;
  createdAt: string;
}

// Named `AppNotification` rather than `Notification` to avoid shadowing the
// browser's global `Notification` (desktop notification) type.
export interface AppNotification {
  id: ID;
  userId: ID;
  eventId?: ID | null;
  title: string;
  body?: string | null;
  level: NotificationLevel;
  readAt?: string | null;
  createdAt: string;
}

export interface HostStatsSnapshot {
  cpuPercent?: number | null;
  memTotalBytes: number;
  memUsedBytes: number;
  memPercent?: number | null;
  diskTotalBytes: number;
  diskUsedBytes: number;
  diskPercent?: number | null;
  sampledAt: string;
}

// From `GET /apps/limits` — the host's real capacity, so per-app resource
// fields (like CPU quota) can be capped at what the host can actually give
// rather than an arbitrary hardcoded number.
export interface AppLimits {
  cpuCores: number;
  maxCpuQuotaPercent: number;
}

export const ALERT_METRIC_LABEL: Record<AlertMetric, string> = {
  cpu_percent: "CPU usage",
  memory_percent: "Memory usage",
  disk_percent: "Disk usage",
  connections_percent: "Connection usage",
  status_down: "Is down",
};

export const ALERT_SCOPE_LABEL: Record<AlertScope, string> = {
  system: "Server",
  app: "App",
  postgres: "Postgres instance",
  mongo: "Mongo instance",
  mail: "Mail stack",
  service: "Service",
  runtime: "Runtime",
};

// ── Health monitoring (mail stack / managed services / runtime toolchains) ──
//
// Shared cached-health shape published by `HealthMonitorWorker` to Redis and
// read straight back by `GET /mail/health`, `GET /services/{id}/health`, and
// `GET /applications/{id}/versions/{versionId}/health`.
export interface HealthStatus {
  healthy: boolean | null;
  checkedAt?: string | null;
  detail?: string | null;
  unhealthySince?: string | null;
  lastRepairAt?: string | null;
  // Outcome of that last repair, written by the worker as soon as the job
  // finishes so the UI can report what happened instead of just "queued".
  // `running` means a repair is in flight.
  lastRepairStatus?: "running" | "succeeded" | "failed" | null;
  lastRepairDetail?: string | null;
  // What the repair actually tried, in order, including the steps that
  // failed — the answer to "so what went wrong?".
  lastRepairSteps?: string[] | null;
  // Present for `/mail/health` (per-daemon) and `/services/{id}/health`
  // (per-port) — kept loose since the shape differs by resource type.
  [key: string]: unknown;
}
