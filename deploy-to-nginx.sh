#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy the generated JSON files to a directory served by Nginx.
# Required environment variables:
#   NGINX_SSH_HOST   remote hostname or IP address
#   NGINX_SSH_USER   remote SSH user
#   NGINX_DEST_DIR   absolute directory served by Nginx
# Optional:
#   NGINX_SSH_PORT   SSH port, default 22
#   NGINX_SSH_KEY    path to the private SSH key

: "${NGINX_SSH_HOST:?Set NGINX_SSH_HOST}"
: "${NGINX_SSH_USER:?Set NGINX_SSH_USER}"
: "${NGINX_DEST_DIR:?Set NGINX_DEST_DIR}"

SSH_PORT="${NGINX_SSH_PORT:-22}"
SSH_KEY_ARGS=()
if [[ -n "${NGINX_SSH_KEY:-}" ]]; then
  SSH_KEY_ARGS=(-i "$NGINX_SSH_KEY")
fi

SSH_ARGS=(
  -p "$SSH_PORT"
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
)

SCP_ARGS=(
  -P "$SSH_PORT"
  -o BatchMode=yes
  -o StrictHostKeyChecking=yes
)

if [[ ${#SSH_KEY_ARGS[@]} -gt 0 ]]; then
  SSH_ARGS+=("${SSH_KEY_ARGS[@]}")
  SCP_ARGS+=("${SSH_KEY_ARGS[@]}")
fi

REMOTE="${NGINX_SSH_USER}@${NGINX_SSH_HOST}"
FILES=(latest.json history.json intervals.json routes.json ftp_history.json)
FILES_TO_DEPLOY=()

for file in "${FILES[@]}"; do
  if [[ -f "$file" ]]; then
    FILES_TO_DEPLOY+=("$file")
  fi
done

if [[ ${#FILES_TO_DEPLOY[@]} -eq 0 ]]; then
  echo "No JSON files found to deploy." >&2
  exit 1
fi

REMOTE_TMP_DIR="$NGINX_DEST_DIR/.deploy-$(date -u +%Y%m%d%H%M%S)-$$"
REMOTE_FILES=()
for file in "${FILES_TO_DEPLOY[@]}"; do
  REMOTE_FILES+=("$REMOTE_TMP_DIR/$file")
done

cleanup() {
  ssh "${SSH_ARGS[@]}" "$REMOTE" "rm -rf -- '$REMOTE_TMP_DIR'" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Creating temporary directory on $REMOTE..."
ssh "${SSH_ARGS[@]}" "$REMOTE" "mkdir -p -- '$NGINX_DEST_DIR' '$REMOTE_TMP_DIR'"

echo "Uploading: ${FILES_TO_DEPLOY[*]}"
scp "${SCP_ARGS[@]}" "${FILES_TO_DEPLOY[@]}" "$REMOTE:$REMOTE_TMP_DIR/"

# Move each file only after all uploads have completed successfully.
# Existing files are replaced atomically one by one, without exposing partial uploads.
REMOTE_COMMAND="set -e;"
for file in "${FILES_TO_DEPLOY[@]}"; do
  REMOTE_COMMAND+=" mv -f -- '$REMOTE_TMP_DIR/$file' '$NGINX_DEST_DIR/$file';"
done
REMOTE_COMMAND+=" rmdir -- '$REMOTE_TMP_DIR' 2>/dev/null || true"

ssh "${SSH_ARGS[@]}" "$REMOTE" "$REMOTE_COMMAND"

echo "JSON files deployed to $REMOTE:$NGINX_DEST_DIR"
