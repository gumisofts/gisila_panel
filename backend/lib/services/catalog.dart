/// Static catalog of managed services the panel can install and configure.
///
/// Each [ServiceDef] describes a service type: its display metadata, whether
/// it requires host-side installation (apt + systemd), and the config schema
/// (fields shown in the UI and stored as JSON in [ManagedService.config]).
library gisila_panel.services.catalog;

// ─────────────────────────────────────────────────────────────────────────────

enum FieldType { string, password, number, boolean, select }

class ConfigField {
  const ConfigField(
    this.key, {
    required this.label,
    required this.type,
    this.defaultValue,
    this.placeholder,
    this.hint,
    this.required = false,
    this.secret = false,
    this.options, // for FieldType.select
    this.min,
    this.max,
  });

  final String key;
  final String label;
  final FieldType type;
  final String? defaultValue;
  final String? placeholder;
  final String? hint;
  final bool required;
  final bool secret;
  final List<String>? options;
  final int? min;
  final int? max;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'label': label,
        'type': type.name,
        if (defaultValue != null) 'default': defaultValue,
        if (placeholder != null) 'placeholder': placeholder,
        if (hint != null) 'hint': hint,
        'required': required,
        'secret': secret,
        if (options != null) 'options': options,
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };
}

class ServiceDef {
  const ServiceDef({
    required this.type,
    required this.name,
    required this.description,
    required this.category,
    required this.configSchema,
    this.requiresInstall = true,
    this.icon,
    this.docsUrl,
  });

  /// Stable machine identifier — stored in [ManagedService.serviceType].
  final String type;
  final String name;
  final String description;

  /// 'cache' | 'email' | 'queue'
  final String category;

  final List<ConfigField> configSchema;

  /// false for config-only services (e.g. SMTP relay — nothing to apt-install).
  final bool requiresInstall;

  final String? icon;
  final String? docsUrl;

  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        'name': name,
        'description': description,
        'category': category,
        'requiresInstall': requiresInstall,
        if (icon != null) 'icon': icon,
        if (docsUrl != null) 'docsUrl': docsUrl,
        'configSchema': configSchema.map((f) => f.toJson()).toList(),
      };
}

// ─────────────────────────── Catalog entries ─────────────────────────────────

const List<ServiceDef> kServiceCatalog = [
  // ── Cache ─────────────────────────────────────────────────────────────────

  ServiceDef(
    type: 'redis',
    name: 'Redis',
    description: 'In-memory data store for caching, pub/sub, and job queues. '
        'Runs as a dedicated gisila-redis systemd instance, separate from the '
        "panel's own Redis (so it defaults to port 6380, not 6379).",
    category: 'cache',
    docsUrl: 'https://redis.io/docs/',
    configSchema: [
      ConfigField('port',
          label: 'Port',
          type: FieldType.number,
          defaultValue: '6380',
          hint: "Use a port other than 6379 — that's the panel's own Redis.",
          min: 1024,
          max: 65535),
      ConfigField('bind',
          label: 'Bind address',
          type: FieldType.string,
          defaultValue: '127.0.0.1',
          hint: 'Keep 127.0.0.1 unless you need external access.'),
      ConfigField('maxmemory',
          label: 'Max memory',
          type: FieldType.string,
          defaultValue: '256mb',
          hint: 'e.g. 256mb, 1gb — 0 means no limit.'),
      ConfigField('maxmemory_policy',
          label: 'Eviction policy',
          type: FieldType.select,
          defaultValue: 'allkeys-lru',
          options: [
            'noeviction',
            'allkeys-lru',
            'volatile-lru',
            'allkeys-random',
            'volatile-random',
            'volatile-ttl',
          ]),
      ConfigField('password',
          label: 'Password',
          type: FieldType.password,
          secret: true,
          hint: 'Leave empty to disable authentication.'),
      ConfigField('appendonly',
          label: 'Persistence (AOF)',
          type: FieldType.boolean,
          defaultValue: 'true'),
    ],
  ),

  ServiceDef(
    type: 'memcached',
    name: 'Memcached',
    description: 'High-performance distributed memory object caching. '
        'Simple key-value store, ideal for session data.',
    category: 'cache',
    docsUrl: 'https://memcached.org/',
    configSchema: [
      ConfigField('port',
          label: 'Port',
          type: FieldType.number,
          defaultValue: '11211',
          min: 1024,
          max: 65535),
      ConfigField('memory_mb',
          label: 'Memory (MB)',
          type: FieldType.number,
          defaultValue: '64',
          min: 16,
          max: 8192),
      ConfigField('connections',
          label: 'Max connections',
          type: FieldType.number,
          defaultValue: '1024',
          min: 64),
    ],
  ),

  // ── Email ─────────────────────────────────────────────────────────────────

  ServiceDef(
    type: 'smtp',
    name: 'SMTP Relay',
    description: 'Configure outbound email via any SMTP relay (Gmail, SES, '
        'Mailgun, Resend, Postmark …). Nothing is installed — the settings '
        'are surfaced as env vars your apps can consume.',
    category: 'email',
    requiresInstall: false,
    configSchema: [
      ConfigField('host',
          label: 'SMTP host',
          type: FieldType.string,
          required: true,
          placeholder: 'smtp.mailgun.org'),
      ConfigField('port',
          label: 'Port',
          type: FieldType.number,
          defaultValue: '587',
          min: 1,
          max: 65535),
      ConfigField('username',
          label: 'Username', type: FieldType.string, required: true),
      ConfigField('password',
          label: 'Password',
          type: FieldType.password,
          required: true,
          secret: true),
      ConfigField('from_name',
          label: 'From name', type: FieldType.string, placeholder: 'My App'),
      ConfigField('from_email',
          label: 'From address',
          type: FieldType.string,
          placeholder: 'noreply@example.com'),
      ConfigField('tls',
          label: 'Use TLS / STARTTLS',
          type: FieldType.boolean,
          defaultValue: 'true'),
    ],
  ),

  ServiceDef(
    type: 'mailpit',
    name: 'Mailpit',
    description: 'Local email capture for development. Provides an SMTP server '
        'and a web inbox — emails never leave the host.',
    category: 'email',
    docsUrl: 'https://mailpit.axllent.org/',
    configSchema: [
      ConfigField('smtp_port',
          label: 'SMTP port',
          type: FieldType.number,
          defaultValue: '1025',
          min: 1024,
          max: 65535),
      ConfigField('ui_port',
          label: 'Web UI port',
          type: FieldType.number,
          defaultValue: '8025',
          min: 1024,
          max: 65535),
      ConfigField('max_messages',
          label: 'Max stored messages',
          type: FieldType.number,
          defaultValue: '500',
          min: 50),
    ],
  ),

  // ── Database ────────────────────────────────────────────────────────────────

  ServiceDef(
    type: 'pgbouncer',
    name: 'PgBouncer',
    description: 'Lightweight connection pooler for PostgreSQL. Pool many client '
        'connections onto a few server connections across one or more upstream '
        'databases. Configure pools, sizing and client users below after install.',
    category: 'database',
    docsUrl: 'https://www.pgbouncer.org/',
    // Only scalar settings live here (rendered by the generic form). The
    // repeating "databases" and "users" structures are edited by a dedicated
    // PgBouncer panel and stored as JSON strings under those config keys.
    configSchema: [
      ConfigField('listen_addr',
          label: 'Listen address',
          type: FieldType.string,
          defaultValue: '127.0.0.1',
          hint: 'Use 0.0.0.0 to accept connections from other hosts.'),
      ConfigField('listen_port',
          label: 'Listen port',
          type: FieldType.number,
          defaultValue: '6432',
          min: 1024,
          max: 65535),
      ConfigField('auth_type',
          label: 'Auth type',
          type: FieldType.select,
          defaultValue: 'scram-sha-256',
          options: ['scram-sha-256', 'md5', 'trust'],
          hint: 'trust requires no password (bind to 127.0.0.1 only).'),
      ConfigField('pool_mode',
          label: 'Pool mode',
          type: FieldType.select,
          defaultValue: 'transaction',
          options: ['transaction', 'session', 'statement']),
      ConfigField('max_client_conn',
          label: 'Max client connections',
          type: FieldType.number,
          defaultValue: '1000',
          min: 1),
      ConfigField('default_pool_size',
          label: 'Default pool size',
          type: FieldType.number,
          defaultValue: '25',
          min: 1,
          hint: 'Server connections kept per database/user pair.'),
      ConfigField('min_pool_size',
          label: 'Min pool size',
          type: FieldType.number,
          defaultValue: '0',
          min: 0),
      ConfigField('reserve_pool_size',
          label: 'Reserve pool size',
          type: FieldType.number,
          defaultValue: '5',
          min: 0),
      ConfigField('max_db_connections',
          label: 'Max DB connections',
          type: FieldType.number,
          defaultValue: '50',
          min: 0,
          hint: '0 = unlimited.'),
      ConfigField('max_user_connections',
          label: 'Max user connections',
          type: FieldType.number,
          defaultValue: '0',
          min: 0,
          hint: '0 = unlimited.'),
    ],
  ),

  ServiceDef(
    type: 'pgadmin',
    name: 'pgAdmin 4',
    description: 'Web-based PostgreSQL administration UI. Installed in a Python '
        'venv and run via gunicorn on a local port; optionally exposed at a '
        'domain with a Let\'s Encrypt certificate. Add your instances inside '
        'pgAdmin using the connection details from the Databases page.',
    category: 'database',
    docsUrl: 'https://www.pgadmin.org/docs/',
    configSchema: [
      ConfigField('email',
          label: 'Admin email',
          type: FieldType.string,
          required: true,
          placeholder: 'admin@example.com',
          hint: 'Login for the pgAdmin web UI (created on install).'),
      ConfigField('password',
          label: 'Admin password',
          type: FieldType.password,
          required: true,
          secret: true,
          hint: 'At least 6 characters. No quotes or backslashes.'),
      ConfigField('port',
          label: 'Local port',
          type: FieldType.number,
          defaultValue: '5050',
          hint: 'Bound to 127.0.0.1. Reached via the domain below or an SSH tunnel.',
          min: 1024,
          max: 65535),
      ConfigField('domain',
          label: 'Public domain',
          type: FieldType.string,
          placeholder: 'pgadmin.example.com',
          hint: 'Optional — nginx reverse-proxies this hostname to pgAdmin. '
              'Point a DNS A record here first.'),
      ConfigField('tls',
          label: 'HTTPS certificate (Let\'s Encrypt)',
          type: FieldType.boolean,
          defaultValue: 'true',
          hint: 'Obtain a certificate for the domain. Uncheck if TLS is '
              'terminated upstream (e.g. Cloudflare).'),
    ],
  ),

  // Note: the self-hosted Postfix + Dovecot mail stack is no longer an
  // installable catalog entry. It is provisioned and managed automatically by
  // the Mail feature (see MailService / the `mail` agent command).
];

/// Look up a service definition by type, or null if unknown.
ServiceDef? findService(String type) {
  for (final def in kServiceCatalog) {
    if (def.type == type) return def;
  }
  return null;
}

/// Build a defaults map from a [ServiceDef]'s config schema.
Map<String, String> defaultConfig(ServiceDef def) {
  return {
    for (final f in def.configSchema)
      if (f.defaultValue != null) f.key: f.defaultValue!,
  };
}
