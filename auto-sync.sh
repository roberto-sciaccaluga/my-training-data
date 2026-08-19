#!/usr/bin/env bash
set -Eeuo pipefail

# Local Intervals.icu sync and Nginx publishing script.
# Run this script from any directory; files are written to the script directory.

# Example configuration. Uncomment and replace the placeholder values before use.
export ATHLETE_ID="i47608"
export INTERVALS_KEY="-----------"
# export NGINX_DEST_DIR="/var/www/html/training-data"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

: "${ATHLETE_ID:?Set ATHLETE_ID before running}"
: "${INTERVALS_KEY:?Set INTERVALS_KEY before running}"

DAYS="${SYNC_DAYS:-7}"

on_error() {
  local exit_code=$?
  echo "ERROR: sync failed with exit code ${exit_code}." >&2
  echo "Check ATHLETE_ID, INTERVALS_KEY and Intervals.icu API access." >&2
  exit "$exit_code"
}
trap on_error ERR

if [[ ! -f sync.py ]]; then
  echo "ERROR: sync.py not found in ${SCRIPT_DIR}." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required." >&2
  exit 1
fi

if ! python3 -c 'import requests' >/dev/null 2>&1; then
  echo "Installing Python dependency: requests"
  python3 -m pip install requests
fi

echo "Python version: $(python3 --version)"
echo "Working directory: $(pwd)"
echo "Athlete ID: ${ATHLETE_ID:0:5}..."
echo "Days: ${DAYS}"
echo "Running sync.py..."

python3 sync.py \
  --athlete-id "$ATHLETE_ID" \
  --intervals-key "$INTERVALS_KEY" \
  --days "$DAYS" \
  --output latest.json

if [[ ! -f latest.json ]]; then
  echo "ERROR: latest.json was not created." >&2
  exit 1
fi

echo "latest.json created: $(wc -c < latest.json) bytes"

YEAR_MONTH="$(date -u +%Y-%m)"
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
ARCHIVE_FILE="archive/${YEAR_MONTH}/${TIMESTAMP}.json"
mkdir -p "archive/${YEAR_MONTH}"
cp -- latest.json "$ARCHIVE_FILE"
echo "Archived to ${ARCHIVE_FILE}"

# Optional local deployment to a directory served by Nginx.
if [[ -n "${NGINX_DEST_DIR:-}" ]]; then
  if [[ ! -d "$NGINX_DEST_DIR" ]]; then
    echo "Creating Nginx destination directory: $NGINX_DEST_DIR"
    mkdir -p -- "$NGINX_DEST_DIR"
  fi

  DEPLOY_TMP_DIR="$(mktemp -d "${NGINX_DEST_DIR%/}/.deploy.XXXXXX")"
  trap 'rm -rf -- "$DEPLOY_TMP_DIR"' EXIT

  for file in latest.json history.json intervals.json routes.json ftp_history.json; do
    if [[ -f "$file" ]]; then
      cp -- "$file" "$DEPLOY_TMP_DIR/$file"
      mv -f -- "$DEPLOY_TMP_DIR/$file" "${NGINX_DEST_DIR%/}/$file"
      echo "Published $file to Nginx"
    fi
  done

  rmdir -- "$DEPLOY_TMP_DIR" 2>/dev/null || true
fi

echo "Sync completed successfully."
