#!/bin/sh
# Set up icloud-docker-plus on a Synology NAS (or any Linux host with docker).
#
# Idempotent — safe to re-run. Two-phase:
#   1) First run: downloads docker-compose.yml + config.yaml TEMPLATES to
#      $CONFIG_DIR, then stops and tells you what to edit.
#   2) After you edit both files (set your Apple ID + your host paths),
#      re-run this script — it pulls the image, starts the container,
#      and prints the one-line interactive 2FA command.
#
# All scheduling lives in config.yaml; this script just bootstraps the
# files + container.
set -eu

REPO_BASE="https://raw.githubusercontent.com/epheterson/icloud-docker-plus/main/nas-deploy"
CONFIG_DIR="${ICLOUD_CONFIG_DIR:-/volume1/docker/icloud}"
DOCKER="${DOCKER:-/usr/local/bin/docker}"
# Fall back to plain `docker` if the Synology absolute path doesn't exist
if [ ! -x "$DOCKER" ]; then DOCKER="docker"; fi

CONFIG_FILE="$CONFIG_DIR/config/config.yaml"
COMPOSE_FILE="$CONFIG_DIR/docker-compose.yml"

echo "→ Creating $CONFIG_DIR ..."
mkdir -p "$CONFIG_DIR/config"

# Only download templates if missing — never clobber edited copies.
if [ ! -f "$COMPOSE_FILE" ]; then
  echo "→ Downloading docker-compose.yml template..."
  curl -fsSL "$REPO_BASE/docker-compose.yml" -o "$COMPOSE_FILE"
else
  echo "✓ $COMPOSE_FILE already exists (not overwriting)"
fi
if [ ! -f "$CONFIG_FILE" ]; then
  echo "→ Downloading config.yaml template..."
  curl -fsSL "$REPO_BASE/config.yaml" -o "$CONFIG_FILE"
else
  echo "✓ $CONFIG_FILE already exists (not overwriting)"
fi

# Detect unedited templates and bail out with clear instructions.
# Match REPLACE_ME followed by `@` or `_` to catch actual placeholder
# values (REPLACE_ME@icloud.example, REPLACE_ME_PHOTOS_HOST_PATH) while
# skipping the word "REPLACE_ME" used in instructional comments.
NEEDS_EDIT=""
if grep -qE "REPLACE_ME[@_]" "$CONFIG_FILE"; then
  NEEDS_EDIT="${NEEDS_EDIT}  • $CONFIG_FILE
"
fi
if grep -qE "REPLACE_ME[@_]" "$COMPOSE_FILE"; then
  NEEDS_EDIT="${NEEDS_EDIT}  • $COMPOSE_FILE
"
fi
if [ -n "$NEEDS_EDIT" ]; then
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  TEMPLATES PLACED — EDIT BEFORE CONTINUING"
  echo "════════════════════════════════════════════════════════════════"
  echo "  Files that still contain REPLACE_ME placeholders:"
  printf "%s" "$NEEDS_EDIT"
  echo ""
  echo "  Edit them to set:"
  echo "    • config.yaml        → your Apple ID (app.credentials.username)"
  echo "                         → photos.library_destinations (if migrating from boredazfcuk)"
  echo "    • docker-compose.yml → your host paths for photos + drive"
  echo ""
  echo "  Then re-run this script:"
  echo "    sh $0"
  echo "════════════════════════════════════════════════════════════════"
  exit 0
fi

echo "→ Pulling ghcr.io/epheterson/icloud-docker-plus:latest..."
cd "$CONFIG_DIR"
$DOCKER compose pull

echo "→ Starting container..."
$DOCKER compose up -d

echo ""
echo "✓ Container 'icloud' is up. Status:"
$DOCKER ps --filter name=icloud --format "  {{.Names}} | {{.Status}}"

# Pull the username out of config.yaml so the printed command works for
# anyone, not just the original author.
USERNAME=$(awk -F: '/^[[:space:]]*username:/ { gsub(/[[:space:]"'"'"']/, "", $2); print $2; exit }' "$CONFIG_FILE" 2>/dev/null || echo "YOUR_APPLE_ID")

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  NEXT (interactive — enter password + 2FA code on iPhone)"
echo "════════════════════════════════════════════════════════════════"
# Wrap in su-exec abc so session_data is written with the non-root user
# the container runs as. Without this, session files end up root-owned
# and the abc user can't read them on subsequent container restarts.
echo "  $DOCKER exec -it icloud sh -c \"su-exec abc icloud --username=$USERNAME --session-directory=/config/session_data\""
echo ""
echo "After that completes, watch the first sync with:"
echo "  $DOCKER logs -f icloud"
echo "════════════════════════════════════════════════════════════════"
