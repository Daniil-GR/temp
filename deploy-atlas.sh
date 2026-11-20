#!/bin/sh
# Atlas — Earth & Place. Safe, explicit deployment to an existing nginx-selfsteal HTML mount.
# This script never changes nginx conf, TLS, Docker, DNS, or the Reality listener.
set -eu

DOMAIN_DEFAULT=atlas.dateihafen.xyz
CONTAINER=${CONTAINER:-nginx-selfsteal}
WEBROOT=${WEBROOT:-}
CONFIRM=no
DOMAIN=$DOMAIN_DEFAULT
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
SOURCE="$SCRIPT_DIR/atlas/site"
STAGE_NAME=atlas-earth
TMP_DIR=

usage() {
  cat <<'HELP'
Usage:
  sh deploy-atlas.sh inspect [--domain atlas.dateihafen.xyz] [--container nginx-selfsteal]
  sudo sh deploy-atlas.sh stage [--webroot /opt/nginx-selfsteal/html]
  sudo sh deploy-atlas.sh publish --confirm-root-replacement [--webroot HOST_PATH]
  sudo sh deploy-atlas.sh rollback --confirm-root-replacement [--webroot HOST_PATH]

  inspect  Read-only inspection of mounts, listeners, nginx roots and DNS.
  stage    Install Atlas under <existing HTML volume>/atlas-earth. No live changes.
  publish  Explicitly replace ONLY matching Atlas file paths in the HTML root;
           back up overwritten files outside the publicly served directory.
           Use only if your target hostname really serves this HTML root.
  rollback Restore the files modified by the latest publish.

Nothing here configures or reloads nginx, TLS, certificates, Docker, or Reality.
To use Atlas at a dedicated vhost, stage it and point that vhost's root
at /var/www/html/atlas-earth in your existing nginx configuration.
HELP
}
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
cleanup() { [ -z "$TMP_DIR" ] || rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

[ "$#" -gt 0 ] || { usage; exit 1; }
ACTION=$1; shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    --webroot) [ "$#" -gt 1 ] || err '--webroot requires a value'; WEBROOT=$2; shift 2 ;;
    --container) [ "$#" -gt 1 ] || err '--container requires a value'; CONTAINER=$2; shift 2 ;;
    --domain) [ "$#" -gt 1 ] || err '--domain requires a value'; DOMAIN=$2; shift 2 ;;
    --confirm-root-replacement) CONFIRM=yes; shift ;;
    --help|-h) usage; exit 0 ;;
    *) err "Unknown option: $1" ;;
  esac
done

is_running() {
  have docker && docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -qx true
}
mount_root() {
  if have docker; then
    docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/www/html"}}{{println .Source}}{{end}}{{end}}' "$CONTAINER" 2>/dev/null | sed -n '1p' || :
  fi
}
resolve_root() {
  ROOT=${WEBROOT:-$(mount_root)}
  [ -n "$ROOT" ] || ROOT=/opt/nginx-selfsteal/html
  [ -d "$ROOT" ] || err "HTML root is missing: $ROOT (pass --webroot if different)"
  [ ! -L "$ROOT" ] || err "Symlinked HTML root is not accepted: $ROOT"
  ROOT=$(CDPATH= cd -- "$ROOT" && pwd -P)
  case "$ROOT" in /|/etc|/opt|/var|/var/www|/opt/nginx-selfsteal) err "Unsafe HTML root: $ROOT" ;; esac
  case "$ROOT" in *[!A-Za-z0-9_./-]*) err "Unexpected characters in HTML path: $ROOT" ;; esac
  if is_running; then
    MOUNT=$(mount_root)
    [ -n "$MOUNT" ] || err "Container $CONTAINER does not have /var/www/html mounted"
    MOUNT=$(CDPATH= cd -- "$MOUNT" && pwd -P)
    [ "$ROOT" = "$MOUNT" ] || err "Requested root $ROOT is not the mounted /var/www/html path $MOUNT"
  elif [ -z "$WEBROOT" ]; then
    err "Cannot verify the nginx-selfsteal mount (container absent/stopped). Pass --webroot explicitly only after checking its configuration."
  else
    warn 'Container not running or unavailable; using explicit --webroot without container verification.'
  fi
}
require_root() { [ "$(id -u)" -eq 0 ] || err 'Run this action with sudo/root'; }
verify_site() {
  [ -s "$SOURCE/index.html" ] || err "Missing Atlas source: $SOURCE/index.html"
  [ -s "$SOURCE/assets/css/styles.css" ] || err 'Site stylesheet missing'
  [ -s "$SOURCE/assets/js/app.js" ] || err 'Site JavaScript missing'
  [ -s "$SOURCE/articles/great-lakes.html" ] || err 'Atlas articles missing'
  have mktemp || err 'mktemp command missing'
  [ -z "$(find "$SOURCE" -type l -print -quit)" ] || err 'Refusing symlinks in the site source'
  TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/atlas-deploy.XXXXXX")
  mkdir "$TMP_DIR/site"
  cp -R "$SOURCE/." "$TMP_DIR/site/" || err 'Unable to prepare the Atlas source'
  (cd "$TMP_DIR/site" && find . -type f -print | LC_ALL=C sort) > "$TMP_DIR/paths"
}

backup_dir() {
  BACKUPS=$(dirname "$ROOT")/atlas-deployment-backups
  [ ! -L "$BACKUPS" ] || err "Unsafe backup directory: $BACKUPS"
  mkdir -p "$BACKUPS"
  chmod 700 "$BACKUPS"
}
check_target_path() {
  relative=$1
  case "$relative" in ./index.html|./404.html|./robots.txt|./sitemap.xml|./about.html|./cartography.html|./earth-science.html|./explore.html|./geography.html|./sources.html|./articles/*|./assets/*|./README.md|./DEPLOY-RU.md) : ;; *) err "Unexpected file in the payload: $relative" ;; esac
  case "$relative" in *../*|*'/../'*|*'//'*) err "Unsafe relative path: $relative" ;; esac
  [ ! -L "$ROOT/$relative" ] || err "Existing target is a symlink: $ROOT/$relative"
  parent=$(dirname "$relative")
  until [ "$parent" = '.' ]; do
    [ ! -L "$ROOT/$parent" ] || err "Existing directory is a symlink: $ROOT/$parent"
    parent=$(dirname "$parent")
  done
  [ ! -d "$ROOT/$relative" ] || err "Existing directory conflicts with site file: $relative"
}
inspect() {
  printf 'Domain: %s\nContainer: %s\n' "$DOMAIN" "$CONTAINER"
  printf '\n-- Docker mounts --\n'
  if have docker; then docker inspect -f '{{range .Mounts}}{{println .Source " -> " .Destination}}{{end}}' "$CONTAINER" 2>/dev/null || :; fi
  printf '\n-- Nginx roots and hostnames --\n'
  if is_running; then
    docker exec "$CONTAINER" nginx -T 2>&1 | grep -E '^[[:space:]]*(root|listen|server_name)[[:space:]]' | head -65 || :
  else
    warn 'nginx container not running or unavailable'
  fi
  printf '\n-- TCP listeners --\n'
  if have ss; then ss -lntp | grep -E '(:80|:443)[[:space:]]' || :; fi
  printf '\n-- DNS A records --\n'
  if have getent; then getent ahostsv4 "$DOMAIN" | head -3 || :; fi
  printf '\n-- HTML mount --\n'
  if is_running; then mount_root; else printf 'Unavailable; use --webroot for stage only after verifying it.\n'; fi
  printf '\nNo changes made.\n'
}
stage() {
  require_root; resolve_root; verify_site; backup_dir
  TARGET="$ROOT/$STAGE_NAME"
  [ ! -L "$TARGET" ] || err "Staging target is a symlink: $TARGET"
  [ ! -e "$TARGET" ] || [ -d "$TARGET" ] || err "Staging target is not a directory: $TARGET"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  if [ -d "$TARGET" ]; then
    archive="$BACKUPS/atlas-stage-$stamp-$$.tar.gz"
    tar -czf "$archive" -C "$ROOT" "$STAGE_NAME" || err 'Stage backup failed'
    printf 'Previous stage archived at %s\n' "$archive"
  fi
  NEW="$ROOT/.atlas-stage-$$"
  [ ! -e "$NEW" ] || err "Temporary staging path already exists: $NEW"
  mkdir "$NEW"
  cp -R "$TMP_DIR/site/." "$NEW/" || { rm -rf "$NEW"; err 'Failed to copy stage files'; }
  find "$NEW" -type d -exec chmod 755 {} \;
  find "$NEW" -type f -exec chmod 644 {} \;
  [ -s "$NEW/index.html" ] || { rm -rf "$NEW"; err 'Staged index is empty'; }
  if [ -d "$TARGET" ]; then
    PREVIOUS="$BACKUPS/old-atlas-stage-$stamp-$$"
    mv "$TARGET" "$PREVIOUS" || err 'Failed to move previous staging directory'
  fi
  mv "$NEW" "$TARGET" || err 'Failed to activate staging directory'
  printf '\nAtlas staged: %s\n' "$TARGET"
  if is_running; then
    docker exec "$CONTAINER" test -s "/var/www/html/$STAGE_NAME/index.html" &&
      printf 'Verified within container: /var/www/html/%s/index.html\n' "$STAGE_NAME" ||
      warn 'Container cannot read the staged index file'
  fi
  printf 'Old webroot content, nginx, TLS and Reality were NOT changed.\n'
  printf 'For an isolated hostname, configure its existing vhost root as /var/www/html/%s.\n' "$STAGE_NAME"
}
publish() {
  require_root
  [ "$CONFIRM" = yes ] || err 'Use --confirm-root-replacement after checking nginx -T and the actual vhost root'
  [ "$DOMAIN" = "$DOMAIN_DEFAULT" ] || err "Publish confirmation is restricted to $DOMAIN_DEFAULT"
  resolve_root; backup_dir
  STAGE="$ROOT/$STAGE_NAME"
  [ -d "$STAGE" ] && [ ! -L "$STAGE" ] && [ -s "$STAGE/index.html" ] || err 'Stage not found: run stage first'
  [ ! -L "$BACKUPS/latest" ] || err 'Unsafe latest backup pointer'
  paths="$BACKUPS/.atlas-paths-$$"
  (cd "$STAGE" && find . -type f ! -name README.md ! -name DEPLOY-RU.md -print | LC_ALL=C sort) > "$paths"
  [ -s "$paths" ] || err 'Empty publish manifest'
  OLD="$BACKUPS/.atlas-existing-$$"
  NEW="$BACKUPS/.atlas-added-$$"
  : > "$OLD"; : > "$NEW"
  while IFS= read -r path; do
    check_target_path "$path"
    if [ -e "$ROOT/$path" ]; then
      [ -f "$ROOT/$path" ] || err "Not a regular file: $ROOT/$path"
      printf '%s\n' "$path" >> "$OLD"
    else
      printf '%s\n' "$path" >> "$NEW"
    fi
  done < "$paths"
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  SNAPSHOT="$BACKUPS/publish-$stamp-$$"
  mkdir "$SNAPSHOT"; chmod 700 "$SNAPSHOT"
  cp "$OLD" "$SNAPSHOT/existing.list"
  cp "$NEW" "$SNAPSHOT/added.list"
  cp "$paths" "$SNAPSHOT/all.list"
  printf '%s\n' "$ROOT" > "$SNAPSHOT/webroot"
  if [ -s "$OLD" ]; then
    tar -czf "$SNAPSHOT/original-files.tar.gz" -C "$ROOT" -T "$OLD" || err 'Could not back up previous webroot files; nothing published'
  fi
  # Copy index LAST so browsers see the completed site on activation.
  while IFS= read -r path; do
    [ "$path" != './index.html' ] || continue
    parent=$(dirname "$ROOT/$path")
    mkdir -p "$parent"
    cp "$STAGE/$path" "$ROOT/$path"
    chmod 644 "$ROOT/$path"
  done < "$paths"
  cp "$STAGE/index.html" "$ROOT/.atlas-new-index-$$"
  chmod 644 "$ROOT/.atlas-new-index-$$"
  mv -f "$ROOT/.atlas-new-index-$$" "$ROOT/index.html"
  printf '%s\n' "$SNAPSHOT" > "$BACKUPS/latest"
  rm -f "$paths" "$OLD" "$NEW"
  printf '\nPublished Atlas in: %s\nBackup: %s\n' "$ROOT" "$SNAPSHOT"
  printf 'No nginx, Docker, Reality, TLS, DNS or listeners were changed.\n'
  printf 'WARNING: Every hostname using this same webroot may now show Atlas.\n'
}
rollback() {
  require_root
  [ "$CONFIRM" = yes ] || err 'Use --confirm-root-replacement to explicitly restore previous webroot files'
  resolve_root; backup_dir
  [ -f "$BACKUPS/latest" ] || err 'No publish backup pointer found'
  SNAPSHOT=$(cat "$BACKUPS/latest")
  case "$SNAPSHOT" in "$BACKUPS"/publish-*) : ;; *) err 'Unsafe snapshot pointer' ;; esac
  [ -d "$SNAPSHOT" ] && [ ! -L "$SNAPSHOT" ] || err 'Snapshot directory missing or unsafe'
  [ "$(cat "$SNAPSHOT/webroot")" = "$ROOT" ] || err 'Backup belongs to a different HTML root'
  [ -f "$SNAPSHOT/added.list" ] && [ -f "$SNAPSHOT/existing.list" ] || err 'Backup manifest is incomplete'
  while IFS= read -r path; do
    check_target_path "$path"
    [ ! -e "$ROOT/$path" ] || { [ -f "$ROOT/$path" ] || err "Unsafe changed target: $path"; }
  done < "$SNAPSHOT/all.list"
  # Restore old files last for index.html, and remove files that did not exist.
  while IFS= read -r path; do
    [ "$path" != './index.html' ] || continue
    rm -f -- "$ROOT/$path"
  done < "$SNAPSHOT/added.list"
  if [ -f "$SNAPSHOT/original-files.tar.gz" ]; then
    tar -xzf "$SNAPSHOT/original-files.tar.gz" -C "$ROOT" || err 'Restore failed; backup remains intact'
  fi
  if grep -Fxq './index.html' "$SNAPSHOT/added.list"; then rm -f "$ROOT/index.html"; fi
  rm -f "$BACKUPS/latest"
  printf '\nRestored prior files from %s\n' "$SNAPSHOT"
  printf 'No nginx, TLS, Docker or Reality settings were changed.\n'
}

case "$ACTION" in
  inspect) inspect ;;
  stage) stage ;;
  publish) publish ;;
  rollback) rollback ;;
  help) usage ;;
  *) usage; err "Unknown action: $ACTION" ;;
esac