/// Render a Nginx vhost that serves static files directly from the filesystem.
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
    final names = hostnames.join(' ');
    final fallback = isSpa
        ? 'try_files \$uri \$uri/ /index.html;'
        : 'try_files \$uri \$uri/ =404;';
    return '''
# Managed by gisila-agent (static) — do not edit by hand.
server {
    listen 80;
    listen [::]:80;
    server_name $names;

    root $staticDir;
    index index.html;

    # ACME HTTP-01 challenges
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

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
}
''';
  }
}

/// Render a Nginx reverse-proxy vhost for an app.
///
/// HTTP-only by default; certbot rewrites the file to add 443 / managed
/// SSL when [issueCert] is invoked.
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

  String render() {
    if (hostnames.isEmpty) {
      return '# app=$appId has no hostnames yet — vhost intentionally empty.\n';
    }
    final names = hostnames.join(' ');
    final staticBlock = _fileLocation(staticRoot, staticUrl, immutable: true);
    final mediaBlock = _fileLocation(mediaRoot, mediaUrl, immutable: false);
    // Internal location for X-Accel-Redirect handoff of auth-gated media.
    final protectedBlock = (mediaRoot != null && protectedMedia)
        ? '''

    location /_protected/ {
        internal;
        alias $mediaRoot/;
    }
'''
        : '';
    return '''
# Managed by gisila-agent — do not edit by hand.
server {
    listen 80;
    listen [::]:80;
    server_name $names;

    # ACME HTTP-01 challenges
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
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
}
''';
  }
}
