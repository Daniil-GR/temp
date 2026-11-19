#!/bin/sh
# Cloudenza Notes: non-disruptive installer for an existing nginx-selfsteal Docker volume.
# Does not modify DNS, nginx configs, Docker Compose, certificates, Reality, ports or running services.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SITE_SOURCE="$SCRIPT_DIR/site"
CONTAINER="${CONTAINER:-nginx-selfsteal}"
WEBROOT="${WEBROOT:-}"
DOMAIN=""
NEW_IP=""
ACTION=""

usage() {
  cat <<'USAGE'
Usage:
  sh deploy.sh inspect [--domain HOST] [--ip IPv4] [--container NAME]
  sudo sh deploy.sh install [--webroot HOST_PATH] [--container NAME]
  sh deploy.sh help

This only installs site files into <existing nginx html mount>/cloudenza-notes.
It does NOT configure a new public hostname or SNI.

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

case "$ACTION" in
  inspect) inspect ;;
  install) install_site ;;
  help) usage ;;
  *) usage; die "Unknown action: $ACTION" ;;
esac
