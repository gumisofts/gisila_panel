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
        'Installed as a systemd-managed apt package.',
    category: 'cache',
    docsUrl: 'https://redis.io/docs/',
    configSchema: [
      ConfigField('port',
          label: 'Port',
          type: FieldType.number,
          defaultValue: '6379',
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

  // ── Mail servers ───────────────────────────────────────────────────────────
  //
  // Postfix + Dovecot is the industry-standard self-hosted email stack.
  // Install them independently or together:
  //   Postfix alone  → outbound MTA / smart relay for your apps.
  //   Dovecot alone  → IMAP/POP3 access to an existing Maildir.
  //   Both together  → full inbound + outbound email for your domains.

  ServiceDef(
    type: 'postfix',
    name: 'Postfix',
    description:
        'Battle-tested MTA (Mail Transfer Agent) for outbound and inbound '
        'email. Can act as a smart relay (apps send to localhost:25, '
        'Postfix relays through your upstream SMTP) or as a standalone '
        'mail server for your domains.',
    category: 'email',
    docsUrl: 'https://www.postfix.org/documentation.html',
    configSchema: [
      ConfigField('mode',
          label: 'Mode',
          type: FieldType.select,
          defaultValue: 'relay',
          options: ['relay', 'standalone'],
          hint: 'relay — forward all mail through an upstream SMTP host. '
              'standalone — receive and deliver mail for your own domains.'),

      // Relay-mode settings.
      ConfigField('relay_host',
          label: 'Relay host',
          type: FieldType.string,
          placeholder: '[smtp.mailgun.org]:587',
          hint: 'Used when mode = relay. Format: [host]:port'),
      ConfigField('relay_username',
          label: 'Relay username', type: FieldType.string),
      ConfigField('relay_password',
          label: 'Relay password', type: FieldType.password, secret: true),

      // Standalone-mode settings.
      ConfigField('myhostname',
          label: 'Mail hostname',
          type: FieldType.string,
          placeholder: 'mail.example.com',
          hint: 'Used when mode = standalone. Must have an A record and '
              'reverse DNS (PTR) pointing here.'),
      ConfigField('mydomain',
          label: 'Mail domain',
          type: FieldType.string,
          placeholder: 'example.com'),
      ConfigField('mynetworks',
          label: 'Trusted networks',
          type: FieldType.string,
          defaultValue: '127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128',
          hint: 'CIDR ranges that may relay without authentication.'),

      // Common settings.
      ConfigField('smtp_port',
          label: 'SMTP port',
          type: FieldType.number,
          defaultValue: '25',
          min: 1,
          max: 65535),
      ConfigField('submission_port',
          label: 'Submission port (STARTTLS)',
          type: FieldType.number,
          defaultValue: '587',
          min: 1,
          max: 65535),
      ConfigField('smtps_port',
          label: 'SMTPS port (implicit TLS)',
          type: FieldType.number,
          defaultValue: '465',
          min: 1,
          max: 65535),
      ConfigField('tls_cert',
          label: 'TLS certificate path',
          type: FieldType.string,
          placeholder: '/etc/letsencrypt/live/mail.example.com/fullchain.pem'),
      ConfigField('tls_key',
          label: 'TLS private key path',
          type: FieldType.string,
          placeholder: '/etc/letsencrypt/live/mail.example.com/privkey.pem'),
      ConfigField('max_message_size_mb',
          label: 'Max message size (MB)',
          type: FieldType.number,
          defaultValue: '25',
          min: 1),
    ],
  ),

  ServiceDef(
    type: 'dovecot',
    name: 'Dovecot',
    description:
        'IMAP and POP3 server that gives email clients access to mailboxes '
        'on the host. Typically paired with Postfix (standalone mode) — '
        'Postfix delivers to Maildir, Dovecot serves it over IMAP.',
    category: 'email',
    docsUrl: 'https://doc.dovecot.org/',
    configSchema: [
      ConfigField('protocols',
          label: 'Protocols',
          type: FieldType.select,
          defaultValue: 'imap',
          options: ['imap', 'pop3', 'imap pop3'],
          hint: 'Which protocols to enable.'),
      ConfigField('imap_port',
          label: 'IMAP port (STARTTLS)',
          type: FieldType.number,
          defaultValue: '143',
          min: 1,
          max: 65535),
      ConfigField('imaps_port',
          label: 'IMAPS port (implicit TLS)',
          type: FieldType.number,
          defaultValue: '993',
          min: 1,
          max: 65535),
      ConfigField('pop3_port',
          label: 'POP3 port',
          type: FieldType.number,
          defaultValue: '110',
          min: 1,
          max: 65535),
      ConfigField('pop3s_port',
          label: 'POP3S port',
          type: FieldType.number,
          defaultValue: '995',
          min: 1,
          max: 65535),
      ConfigField('mail_location',
          label: 'Maildir location',
          type: FieldType.string,
          defaultValue: 'maildir:~/Maildir',
          hint: 'Where to store mailboxes on disk.'),
      ConfigField('tls_cert',
          label: 'TLS certificate path',
          type: FieldType.string,
          placeholder: '/etc/letsencrypt/live/mail.example.com/fullchain.pem'),
      ConfigField('tls_key',
          label: 'TLS private key path',
          type: FieldType.string,
          placeholder: '/etc/letsencrypt/live/mail.example.com/privkey.pem'),
      ConfigField('auth_mechanisms',
          label: 'Auth mechanisms',
          type: FieldType.string,
          defaultValue: 'plain login',
          hint: 'Space-separated list, e.g. plain login cram-md5.'),
      ConfigField('disable_plaintext_auth',
          label: 'Require TLS for plaintext auth',
          type: FieldType.boolean,
          defaultValue: 'true'),
    ],
  ),
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
