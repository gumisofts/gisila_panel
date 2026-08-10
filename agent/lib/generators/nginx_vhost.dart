import 'dart:io';

/// Render a Nginx vhost that reverse-proxies a hostname to the local MinIO
/// S3 API so the object store is reachable at a public URL.
///
/// MinIO binds 127.0.0.1 only, so without this the public hostname matches no
/// server block and nginx returns 404. The settings here are the ones MinIO/S3
/// require behind a proxy:
///   - `client_max_body_size 0` — never cap object uploads.
///   - `ignore_invalid_headers off` — S3 signatures use headers with underscores.
///   - `proxy_request_buffering off` + `chunked_transfer_encoding off` — stream
///     large PUTs straight through instead of buffering them to disk first.
///   - `Host $host` — preserve the host so S3 signature-v4 validation passes.
class MinioNginxVhost {
  MinioNginxVhost({
    required this.hostname,
    required this.apiPort,
    this.consoleHostname,
    this.consolePort,
  });

  final String hostname;
  final int apiPort;

  /// When set, a second `server` block proxies this hostname to the MinIO web
  /// console on [consolePort] (with websocket upgrade). The console needs its
  /// own hostname — it lives at the root path, which would collide with S3
  /// bucket paths on the API host.
  final String? consoleHostname;
  final int? consolePort;

  String _apiServer() => '''
server {
    listen 80;
    listen [::]:80;
    server_name $hostname;

    # ACME HTTP-01 challenges
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    # Allow arbitrarily large object uploads and pass S3 requests through
    # untouched (header names with underscores, streamed request bodies).
    ignore_invalid_headers off;
    client_max_body_size 0;
    proxy_buffering off;
    proxy_request_buffering off;

    location / {
        proxy_pass http://127.0.0.1:$apiPort;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Connection "";
        chunked_transfer_encoding off;
        proxy_connect_timeout 300;
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }

    access_log /var/log/nginx/gisila-minio.access.log;
    error_log  /var/log/nginx/gisila-minio.error.log;
}
''';

  String _consoleServer() => '''

server {
    listen 80;
    listen [::]:80;
    server_name $consoleHostname;

    # ACME HTTP-01 challenges
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    ignore_invalid_headers off;
    client_max_body_size 0;
    proxy_buffering off;

    location / {
        proxy_pass http://127.0.0.1:$consolePort;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # The console uses websockets for live stats / the object browser.
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_connect_timeout 300;
        proxy_read_timeout 300;
        proxy_send_timeout 300;
        chunked_transfer_encoding off;
    }

    access_log /var/log/nginx/gisila-minio-console.access.log;
    error_log  /var/log/nginx/gisila-minio-console.error.log;
}
''';

  String render() {
    final console = (consoleHostname != null &&
            consoleHostname!.isNotEmpty &&
            consolePort != null)
        ? _consoleServer()
        : '';
    return '# Managed by gisila-agent (minio) — do not edit by hand.\n'
        '${_apiServer()}$console';
  }
}

/// Whether Let's Encrypt material exists for [hostname] on this host.
bool letsEncryptReady(String hostname) {
  final live = '/etc/letsencrypt/live/$hostname';
  return File('$live/fullchain.pem').existsSync() &&
      File('$live/privkey.pem').existsSync();
}

String _sslListenPreamble(String hostname) {
  final live = '/etc/letsencrypt/live/$hostname';
  final options = File('/etc/letsencrypt/options-ssl-nginx.conf');
  final dhparam = File('/etc/letsencrypt/ssl-dhparams.pem');
  final extras = StringBuffer();
  if (options.existsSync()) {
    extras.writeln('    include /etc/letsencrypt/options-ssl-nginx.conf;');
  }
  if (dhparam.existsSync()) {
    extras.writeln('    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;');
  }
  return '''
    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate $live/fullchain.pem;
    ssl_certificate_key $live/privkey.pem;
${extras.toString()}''';
}

/// Render a Nginx vhost that serves static files directly from the filesystem.
///
/// One `server` block (or HTTP+HTTPS pair) is emitted **per hostname** so each
/// domain can keep its own Let's Encrypt lineage. A shared `server_name a b`
/// block cannot attach two different certificates, which broke multi-domain
/// apps as soon as a second hostname was added or the vhost was re-rendered.
///
/// When [isSpa] is true every request that does not match a real file falls
/// back to `index.html` (SPA / client-side routing).
class StaticNginxVhost {
  StaticNginxVhost({
    required this.appId,
    required this.staticDir,
    required this.hostnames,
    this.isSpa = false,
  });

  final int appId;

  /// Absolute path to the directory Nginx should serve. This is the stable
  /// symlink `/srv/apps/app_xxx/current/web`, which the agent atomically
  /// repoints at the latest published release (`releases/web/<id>`) on each
  /// deploy — so the path here never changes and never points at a build dir
  /// that is about to be wiped.
  final String staticDir;
  final List<String> hostnames;
  final bool isSpa;

  String render() {
    if (hostnames.isEmpty) {
      return '# app=$appId has no hostnames yet — static vhost intentionally empty.\n';
    }
    final fallback = isSpa
        ? 'try_files \$uri \$uri/ /index.html;'
        : 'try_files \$uri \$uri/ =404;';
    final body = StringBuffer()
      ..writeln('# Managed by gisila-agent (static) — do not edit by hand.');
    for (final host in hostnames) {
      body.write(_serverFor(host, fallback));
    }
    return body.toString();
  }

  String _locations(String fallback) => '''
    root $staticDir;
    index index.html;

    location / {
        $fallback
    }

    # Long-lived cache for hashed assets
    location ~* \\.(?:css|js|mjs|woff2?|ttf|eot|otf|svg|png|jpe?g|gif|ico|webp|avif)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
        $fallback
    }

    client_max_body_size 10M;
    access_log /var/log/nginx/gisila-app-$appId.access.log;
    error_log  /var/log/nginx/gisila-app-$appId.error.log;
''';

  String _serverFor(String hostname, String fallback) {
    final locations = _locations(fallback);
    if (!letsEncryptReady(hostname)) {
      return '''
server {
    listen 80;
    listen [::]:80;
    server_name $hostname;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
$locations}
''';
    }
    return '''
server {
    listen 80;
    listen [::]:80;
    server_name $hostname;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
${_sslListenPreamble(hostname)}    server_name $hostname;
$locations}
''';
  }
}

/// Render a Nginx reverse-proxy vhost for an app.
///
/// One HTTP (and optional HTTPS) `server` block per hostname — see
/// [StaticNginxVhost] for why a shared `server_name` list cannot carry
/// per-domain certificates. TLS is enabled automatically when
/// `/etc/letsencrypt/live/<hostname>/` exists (written by [Applier.issueCert]).
class NginxVhost {
  NginxVhost({
    required this.appId,
    required this.port,
    required this.hostnames,
    this.staticRoot,
    this.staticUrl = '/static/',
    this.mediaRoot,
    this.mediaUrl = '/media/',
    this.protectedMedia = false,
    this.maxUploadMb = 50,
  });

  final int appId;
  final int port;
  final List<String> hostnames;

  /// When set, nginx serves [staticUrl] (default `/static/`) directly from this
  /// directory via `alias`, bypassing the app process. Used for Django's
  /// collected static files. Null leaves all paths proxied to the app.
  final String? staticRoot;
  final String staticUrl;

  /// When set, nginx serves [mediaUrl] (default `/media/`) from this directory.
  final String? mediaRoot;
  final String mediaUrl;

  /// When true (and [mediaRoot] is set) also emit an `internal` location at
  /// `/_protected/` aliased to [mediaRoot]. The app validates the request, then
  /// returns `X-Accel-Redirect: /_protected/<path>` so nginx serves the file
  /// for auth-gated downloads without the bytes flowing through the app.
  final bool protectedMedia;

  /// Per-app `client_max_body_size` in MB (upload ceiling).
  final int maxUploadMb;

  /// One `location <url> { alias <root>/; }` block, or '' when [root] is null.
  /// [immutable] adds a long-lived cache header (right for hashed static assets,
  /// wrong for user-uploaded media which can change in place).
  String _fileLocation(String? root, String url, {required bool immutable}) {
    if (root == null) return '';
    final u = url.endsWith('/') ? url : '$url/';
    final cache = immutable
        ? '        expires 1y;\n'
            '        add_header Cache-Control "public, immutable";\n'
            '        access_log off;\n'
        : '';
    return '''

    location $u {
        alias $root/;
$cache        try_files \$uri =404;
    }
''';
  }

  String get _appLocations {
    final staticBlock = _fileLocation(staticRoot, staticUrl, immutable: true);
    final mediaBlock = _fileLocation(mediaRoot, mediaUrl, immutable: false);
    final protectedBlock = (mediaRoot != null && protectedMedia)
        ? '''

    location /_protected/ {
        internal;
        alias $mediaRoot/;
    }
'''
        : '';
    return '''
$staticBlock$mediaBlock$protectedBlock
    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    client_max_body_size ${maxUploadMb}M;
    access_log /var/log/nginx/gisila-app-$appId.access.log;
    error_log  /var/log/nginx/gisila-app-$appId.error.log;
''';
  }

  String render() {
    if (hostnames.isEmpty) {
      return '# app=$appId has no hostnames yet — vhost intentionally empty.\n';
    }
    final body = StringBuffer()
      ..writeln('# Managed by gisila-agent — do not edit by hand.');
    for (final host in hostnames) {
      body.write(_serverFor(host));
    }
    return body.toString();
  }

  String _serverFor(String hostname) {
    final locations = _appLocations;
    if (!letsEncryptReady(hostname)) {
      return '''
server {
    listen 80;
    listen [::]:80;
    server_name $hostname;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
$locations}
''';
    }
    return '''
server {
    listen 80;
    listen [::]:80;
    server_name $hostname;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
${_sslListenPreamble(hostname)}    server_name $hostname;
$locations}
''';
  }
}
