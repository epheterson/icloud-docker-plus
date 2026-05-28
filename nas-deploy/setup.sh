#!/bin/sh
# Set up the unified iCloud backup container on Synology NAS.
#
# Idempotent — safe to re-run. Creates directories, pulls the latest image,
# starts the container. Leaves you with a one-line follow-up to do the
# interactive 2FA (can't be scripted — Apple's flow requires manual code entry).
set -eu

REPO_BASE="https://raw.githubusercontent.com/epheterson/icloud-docker-overlay/main/nas-deploy"
CONFIG_DIR="/volume1/docker/icloud"
# Photos reuse existing boredazfcuk-format dirs at /volume1/ELP NAS/Pictures/iCloud/{Eric,Shared}
# via filename_format: simple in config.yaml — no re-download.
DRIVE_DEST="/volume1/ELP NAS/iCloud-Drive"
DOCKER=/usr/local/bin/docker

echo "→ Creating directories..."
mkdir -p "$CONFIG_DIR/config"
mkdir -p "$DRIVE_DEST"

echo "→ Fetching compose + config from $REPO_BASE..."
curl -fsSL "$REPO_BASE/docker-compose.yml" -o "$CONFIG_DIR/docker-compose.yml"
curl -fsSL "$REPO_BASE/config.yaml" -o "$CONFIG_DIR/config/config.yaml"

echo "→ Pulling ghcr.io/epheterson/icloud-docker-overlay:latest..."
cd "$CONFIG_DIR"
$DOCKER compose pull

echo "→ Starting container..."
$DOCKER compose up -d

echo ""
echo "✓ Container 'icloud' is up. Status:"
$DOCKER ps --filter name=icloud --format "  {{.Names}} | {{.Status}}"

# Pull the username out of config.yaml so the printed command line below works
# for anyone who runs this script with their own Apple ID in config.yaml.
USERNAME=$(awk -F: '/^[[:space:]]*username:/ { gsub(/[[:space:]"'"'"']/, "", $2); print $2; exit }' "$CONFIG_DIR/config/config.yaml" 2>/dev/null || echo "YOUR_APPLE_ID")

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  NEXT (interactive — enter password + 2FA code on iPhone)"
echo "════════════════════════════════════════════════════════════════"
# Wrap in su-exec abc so session_data is written with the non-root user
# the container runs as. Without this, session files end up root-owned
# and the abc user can't read them on subsequent container restarts.
echo "  ssh nas '$DOCKER exec -it icloud sh -c \"su-exec abc icloud --username=$USERNAME --session-directory=/config/session_data\"'"
echo ""
echo "After that completes, watch first sync with:"
echo "  ssh nas '$DOCKER logs -f icloud'"
echo "════════════════════════════════════════════════════════════════"
