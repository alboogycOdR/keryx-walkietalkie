#!/usr/bin/env bash
# Nightly Postgres dump for the Keryx directory (Technical §9).
# Keep 7 copies on the VPS disk. The database is small by design (V2-NFR-007).
#
# Install as root crontab on the VPS (example):
#   15 3 * * * /opt/keryx/token-svc/scripts/pg_dump_nightly.sh
#
# Required env (or /etc/keryx/directory.env):
#   DATABASE_URL=postgresql://keryx:...@127.0.0.1:5432/keryx
#   KERYX_BACKUP_DIR=/var/backups/keryx   (default)
set -euo pipefail

ENV_FILE="${KERYX_DIRECTORY_ENV:-/etc/keryx/directory.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
fi

: "${DATABASE_URL:?DATABASE_URL is required}"
BACKUP_DIR="${KERYX_BACKUP_DIR:-/var/backups/keryx}"
KEEP="${KERYX_BACKUP_KEEP:-7}"
mkdir -p "$BACKUP_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
out="$BACKUP_DIR/keryx-$stamp.sql.gz"
pg_dump --dbname="$DATABASE_URL" --no-owner --no-privileges | gzip -c > "$out"
chmod 600 "$out"

# Rotate: keep the newest $KEEP files.
mapfile -t files < <(ls -1t "$BACKUP_DIR"/keryx-*.sql.gz 2>/dev/null || true)
if (( ${#files[@]} > KEEP )); then
  for stale in "${files[@]:KEEP}"; do
    rm -f "$stale"
  done
fi
