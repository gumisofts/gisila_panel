/// Render a Nginx reverse-proxy vhost for an app.
///
/// HTTP-only by default; certbot rewrites the file to add 443 / managed
/// SSL when [issueCert] is invoked.
class NginxVhost {
  NginxVhost({
    required this.appId,
    required this.port,
    required this.hostnames,
  });

  final int appId;
  final int port;
  final List<String> hostnames;

  String render() {
    if (hostnames.isEmpty) {
      return '# app=$appId has no hostnames yet — vhost intentionally empty.\n';
    }
    final names = hostnames.join(' ');
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

    client_max_body_size 50M;
    access_log /var/log/nginx/gisila-app-$appId.access.log;
    error_log  /var/log/nginx/gisila-app-$appId.error.log;
}
''';
  }
}
