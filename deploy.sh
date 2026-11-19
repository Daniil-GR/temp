#!/bin/sh
# Cloudenza Notes: non-disruptive installer for an existing nginx-selfsteal Docker volume.
# install: files only. prepare-http/activate: explicit nginx virtual-host changes after validation.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SITE_SOURCE="$SCRIPT_DIR/site"
CONTAINER="${CONTAINER:-nginx-selfsteal}"
WEBROOT="${WEBROOT:-}"
DOMAIN=""
NEW_IP=""
CERT_FILE=""
KEY_FILE=""
ACTION=""

usage() {
  cat <<'USAGE'
Usage:
  sh deploy.sh inspect [--domain HOST] [--ip IPv4] [--container NAME]
  sudo sh deploy.sh install [--webroot HOST_PATH] [--container NAME]
  sudo sh deploy.sh prepare-http --domain HOST
  sudo sh deploy.sh activate --domain HOST --cert-file FULLCHAIN_FILENAME --key-file PRIVKEY_FILENAME
  sh deploy.sh help

The installer writes only into <existing nginx html mount>/cloudenza-notes.
prepare-http adds an isolated port-80 nginx vhost for HTTP-01 validation.
activate adds an isolated TLS vhost. Neither configures DNS, Reality or public listener routing.

Examples:
  sudo sh deploy.sh inspect --domain YOUR_SUBDOMAIN --ip YOUR_SECONDARY_IP
  sudo sh deploy.sh install
  sudo sh deploy.sh install --webroot /opt/nginx-selfsteal/html
USAGE
}

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'WARNING: %s\n' "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }

[ "$#" -gt 0 ] || { usage; exit 1; }
ACTION="$1"; shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --container) [ "$#" -ge 2 ] || die '--container needs a value'; CONTAINER="$2"; shift 2 ;;
    --webroot) [ "$#" -ge 2 ] || die '--webroot needs a value'; WEBROOT="$2"; shift 2 ;;
    --domain) [ "$#" -ge 2 ] || die '--domain needs a value'; DOMAIN="$2"; shift 2 ;;
    --ip) [ "$#" -ge 2 ] || die '--ip needs a value'; NEW_IP="$2"; shift 2 ;;
    --cert-file) [ "$#" -ge 2 ] || die '--cert-file needs a filename'; CERT_FILE="$2"; shift 2 ;;
    --key-file) [ "$#" -ge 2 ] || die '--key-file needs a filename'; KEY_FILE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

docker_running() {
  have docker && docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true
}
docker_webroot() {
  have docker || return 0
  docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{println .Source}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null | sed -n '1p' || true
}
resolve_webroot() {
  if [ -n "$WEBROOT" ]; then printf '%s\n' "$WEBROOT"; return; fi
  ROOT=$(docker_webroot)
  if [ -n "$ROOT" ]; then printf '%s\n' "$ROOT"; return; fi
  if [ -d /opt/nginx-selfsteal/html ]; then
    warn 'Docker volume could not be detected; using standard /opt/nginx-selfsteal/html'
    printf '%s\n' /opt/nginx-selfsteal/html
    return
  fi
  die 'Web root not found. Run inspect and pass --webroot HOST_PATH.'
}

inspect() {
  printf '\n== IPv4 addresses (verify the secondary IP is assigned) ==\n'
  if have ip; then ip -br -4 address || true; else warn "'ip' command unavailable"; fi
  if [ -n "$NEW_IP" ] && have ip; then
    if ip -o -4 addr show | grep -Fq "$NEW_IP"; then
      printf 'Requested IP appears in local address output.\n'
    else
      warn "Requested IP $NEW_IP was not found on local interfaces."
    fi
  fi

  printf '\n== TCP listeners on 80 and 443 ==\n'
  if have ss; then
    ss -lntp 2>/dev/null | grep -E '(:80|:443)[[:space:]]' || true
  else
    warn "'ss' command unavailable"
  fi

  printf '\n== Docker containers ==\n'
  if have docker; then
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null || true
    printf '\n== %s volume mounts ==\n' "$CONTAINER"
    docker inspect -f '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}' "$CONTAINER" 2>/dev/null ||
      warn "Container $CONTAINER not available"
  else
    warn 'Docker unavailable'
  fi

  printf '\n== Existing Selfsteal files ==\n'
  if [ -d /opt/nginx-selfsteal ]; then
    find /opt/nginx-selfsteal -maxdepth 3 -type f \
      \( -name '*.conf' -o -name 'docker-compose.yml' -o -name 'compose.yaml' -o -name 'index.html' \) \
      -print 2>/dev/null | head -60 || true
  else
    warn '/opt/nginx-selfsteal is absent'
  fi

  printf '\n== Nginx virtual hosts (no private keys printed) ==\n'
  if [ -d /opt/nginx-selfsteal/conf.d ]; then
    grep -RinE '^[[:space:]]*(server_name|root|listen|ssl_certificate|ssl_certificate_key)[[:space:]]' \
      /opt/nginx-selfsteal/conf.d 2>/dev/null | head -100 || true
  fi

  printf '\n== DNS ==\n'
  if [ -n "$DOMAIN" ]; then
    if have getent; then getent ahostsv4 "$DOMAIN" | head -5 || true; fi
    if have dig; then dig +short A "$DOMAIN" || true; fi
  else
    printf 'Supply --domain YOUR_SUBDOMAIN for a DNS lookup.\n'
  fi
  printf '\nDetected site webroot: '
  resolve_webroot
  printf '\nDo not change listeners or SNI until you inspect their existing configuration.\n'
}

install_site() {
  [ "$(id -u)" -eq 0 ] || die 'Install requires root: sudo sh deploy.sh install'
  [ -f "$SITE_SOURCE/index.html" ] || die "Missing site source: $SITE_SOURCE/index.html"
  [ -f "$SITE_SOURCE/assets/style.css" ] || die 'Missing site stylesheet'
  [ -f "$SITE_SOURCE/assets/app.js" ] || die 'Missing site JavaScript'

  ROOT=$(resolve_webroot)
  [ -d "$ROOT" ] || die "Web root does not exist: $ROOT"
  [ ! -L "$ROOT" ] || die 'Refusing a symlinked web root. Resolve it and pass a real --webroot path.'
  ROOT=$(cd "$ROOT" && pwd -P)
  [ "$ROOT" != "/" ] || die 'Refusing filesystem root'
  TARGET="$ROOT/cloudenza-notes"
  BACKUP_DIR="$(dirname "$ROOT")/backups-cloudenza"
  case "$TARGET" in
    */cloudenza-notes) ;;
    *) die "Unsafe target: $TARGET" ;;
  esac

  if [ -e "$TARGET" ]; then
    [ -d "$TARGET" ] && [ ! -L "$TARGET" ] || die "Existing target is not a normal directory: $TARGET"
    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"
    STAMP=$(date -u +%Y%m%dT%H%M%SZ)
    BACKUP="$BACKUP_DIR/cloudenza-notes-$STAMP.tar.gz"
    tar -czf "$BACKUP" -C "$ROOT" cloudenza-notes
    printf 'Backed up existing site to: %s\n' "$BACKUP"
  fi

  mkdir -p "$TARGET"
  cp -R "$SITE_SOURCE/." "$TARGET/"
  find "$TARGET" -type d -exec chmod 755 {} \;
  find "$TARGET" -type f -exec chmod 644 {} \;
  [ -s "$TARGET/index.html" ] || die 'Installation failed: index.html missing'

  printf '\nInstalled Cloudenza Notes into: %s\n' "$TARGET"
  if docker_running; then
    if docker exec "$CONTAINER" test -f /var/www/html/cloudenza-notes/index.html 2>/dev/null; then
      printf 'Verified: nginx container can see /var/www/html/cloudenza-notes/index.html\n'
    else
      warn 'Container cannot see the new directory. Inspect Docker volume mounts.'
    fi
  else
    warn 'Nginx container is not running or could not be checked.'
  fi
  printf '\nNo existing site files were removed; no services or configs were changed.\n'
  printf 'NEXT: configure a virtual host that uses root /var/www/html/cloudenza-notes;\n'
  printf 'and a valid certificate, DNS and your Selfsteal SNI route (see NGINX-EXAMPLE.md).\n'
}


validate_domain() {
  [ -n "$DOMAIN" ] || die 'Supply --domain YOUR_NEW_SUBDOMAIN'
  case "$DOMAIN" in
    *[!A-Za-z0-9.-]*|.*|*..*|*.) die "Invalid domain: $DOMAIN" ;;
  esac
  case "$DOMAIN" in
    *.*) : ;;
    *) die "The domain must contain a dot: $DOMAIN" ;;
  esac
}
config_host_dir() {
  if ! docker_running; then die "Container $CONTAINER must be running"; fi
  HOST_DIR=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/nginx/conf.d"}}{{println .Source}}{{end}}{{end}}' "$CONTAINER" | sed -n '1p')
  [ -d "$HOST_DIR" ] || die 'Could not find the existing nginx conf.d bind mount'
  printf '%s\n' "$HOST_DIR"
}
prepare_http() {
  [ "$(id -u)" -eq 0 ] || die 'Requires root: sudo sh deploy.sh prepare-http --domain HOST'
  validate_domain
  docker_running || die "Container $CONTAINER must be running"
  docker exec "$CONTAINER" test -s /var/www/html/cloudenza-notes/index.html 2>/dev/null ||
    die 'Site not installed; run sudo sh deploy.sh install first'
  CONF_HOST=$(config_host_dir)
  CONFIG="$CONF_HOST/cloudenza-notes-http-$DOMAIN.conf"
  [ ! -L "$CONFIG" ] || die "Refusing to overwrite symlink: $CONFIG"
  BACKUP=""
  if [ -e "$CONFIG" ]; then
    [ -f "$CONFIG" ] || die "Not a regular file: $CONFIG"
    BACKUP="$CONFIG.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    cp "$CONFIG" "$BACKUP"
  fi
  cat > "$CONFIG" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    root /var/www/html/cloudenza-notes;
    index index.html;

    location ^~ /.well-known/acme-challenge/ {
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
  chmod 644 "$CONFIG"
  if ! docker exec "$CONTAINER" nginx -t; then
    if [ -n "$BACKUP" ]; then cp "$BACKUP" "$CONFIG"; else rm -f "$CONFIG"; fi
    die 'nginx -t failed; original vhost restored; no reload'
  fi
  if ! docker exec "$CONTAINER" nginx -s reload; then
    if [ -n "$BACKUP" ]; then cp "$BACKUP" "$CONFIG"; else rm -f "$CONFIG"; fi
    die 'nginx reload failed; previous configuration file restored'
  fi
  printf 'HTTP vhost ready for %s and ACME HTTP-01 challenges.\n' "$DOMAIN"
  printf 'Config: %s\n' "$CONFIG"
  printf 'Next: validate HTTP on the secondary IPv4 and issue a TLS certificate.\n'
}

activate_vhost() {
  [ "$(id -u)" -eq 0 ] || die 'Activation requires root: sudo sh deploy.sh activate ...'
  validate_domain
  [ -n "$CERT_FILE" ] && [ -n "$KEY_FILE" ] || die 'Supply --cert-file and --key-file (file names within the already mounted nginx SSL directory)'
  case "$CERT_FILE" in *[!A-Za-z0-9._-]*|.|..) die 'Invalid certificate file name' ;; esac
  case "$KEY_FILE" in *[!A-Za-z0-9._-]*|.|..) die 'Invalid private key file name' ;; esac
  docker_running || die "Container $CONTAINER must be running"
  docker exec "$CONTAINER" test -s /var/www/html/cloudenza-notes/index.html 2>/dev/null ||
    die 'Site is not visible inside nginx: run install first'

  CONF_HOST=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/nginx/conf.d"}}{{println .Source}}{{end}}{{end}}' "$CONTAINER" | sed -n '1p')
  SSL_HOST=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/nginx/ssl"}}{{println .Source}}{{end}}{{end}}' "$CONTAINER" | sed -n '1p')
  [ -d "$CONF_HOST" ] && [ -d "$SSL_HOST" ] ||
    die 'Cannot discover existing conf.d / ssl bind mounts. Configure the vhost manually.'
  [ -f "$SSL_HOST/$CERT_FILE" ] && [ -f "$SSL_HOST/$KEY_FILE" ] ||
    die 'Certificate and key must already exist inside the currently mounted host SSL directory'

  if have openssl; then
    openssl x509 -in "$SSL_HOST/$CERT_FILE" -noout -checkhost "$DOMAIN" >/dev/null 2>&1 ||
      die 'Certificate is unreadable or does not cover the requested hostname'
  else
    warn 'openssl unavailable; confirm certificate SAN manually'
  fi

  grep -REq 'listen[[:space:]]+unix:/dev/shm/nginx[.]sock.*ssl.*proxy_protocol' "$CONF_HOST" ||
    die 'This installation does not clearly use the expected PROXY-protocol Unix listener. Do not apply this template.'

  CONFIG="$CONF_HOST/cloudenza-notes-$DOMAIN.conf"
  BACKUP=""
  if [ -e "$CONFIG" ]; then
    [ -f "$CONFIG" ] && [ ! -L "$CONFIG" ] || die "Unsafe config path: $CONFIG"
    BACKUP="$CONFIG.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    cp "$CONFIG" "$BACKUP"
  fi

  cat > "$CONFIG" <<EOF
server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol http2;
    server_name $DOMAIN;

    ssl_certificate /etc/nginx/ssl/$CERT_FILE;
    ssl_certificate_key /etc/nginx/ssl/$KEY_FILE;
    ssl_protocols TLSv1.2 TLSv1.3;

    root /var/www/html/cloudenza-notes;
    index index.html;

    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
  chmod 644 "$CONFIG"
  if ! docker exec "$CONTAINER" nginx -t; then
    if [ -n "$BACKUP" ]; then cp "$BACKUP" "$CONFIG"; else rm -f "$CONFIG"; fi
    die 'nginx -t failed; original vhost restored and nginx was not reloaded'
  fi
  if ! docker exec "$CONTAINER" nginx -s reload; then
    if [ -n "$BACKUP" ]; then cp "$BACKUP" "$CONFIG"; else rm -f "$CONFIG"; fi
    docker exec "$CONTAINER" nginx -t || true
    die 'nginx reload returned an error; file restored, investigate running configuration'
  fi
  printf 'Nginx vhost enabled: %s\n' "$DOMAIN"
  printf 'Config: %s\n' "$CONFIG"
  printf 'NOTE: DNS, external IPv4 listeners and Reality SNI routing are NOT changed.\n'
}

case "$ACTION" in
  inspect) inspect ;;
  install) install_site ;;
  prepare-http) prepare_http ;;
  activate) activate_vhost ;;
  help) usage ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac
