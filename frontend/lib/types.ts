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
  runtime: string;
  sourceType: "binary" | "git" | "zip";
  gitUrl?: string | null;
  gitBranch?: string | null;
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
  deployKeyId?: number | null;
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
}

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
  /** The always-available cluster that backs the panel itself. Its port is
   *  fixed and it cannot be stopped or uninstalled. */
  isSystem?: boolean;
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
}

export interface PostgresDatabase {
  id: ID;
  instanceId: ID;
  dbName: string;
  roleName: string;
  extensions: string[];
  status: PgDatabaseStatus;
  errorMessage?: string | null;
  createdAt: string;
  updatedAt?: string | null;
  connection?: PgConnectionInfo; // present on create + retrieve
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
