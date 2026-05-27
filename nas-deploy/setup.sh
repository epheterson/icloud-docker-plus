#!/bin/sh
# Set up the unified iCloud backup container on Synology NAS.
#
# Idempotent — safe to re-run. Creates directories, pulls the latest image,
# starts the container. Leaves you with a one-line follow-up to do the
# interactive 2FA (can't be scripted — Apple's flow requires manual code entry).
set -eu

REPO_BASE="https://raw.githubusercontent.com/epheterson/icloud-docker-overlay/main/nas-deploy"
CONFIG_DIR="/volume1/docker/icloud"
PHOTOS_DEST="/volume1/ELP NAS/iCloud-Unified/photos"
DRIVE_DEST="/volume1/ELP NAS/iCloud-Unified/drive"
DOCKER=/usr/local/bin/docker

echo "→ Creating directories..."
mkdir -p "$CONFIG_DIR/config"
mkdir -p "$PHOTOS_DEST"
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

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  NEXT (interactive — enter password + 2FA code on iPhone)"
echo "════════════════════════════════════════════════════════════════"
echo "  ssh nas '$DOCKER exec -it icloud sh -c \"icloud --username=epheterson@me.com --session-directory=/config/session_data\"'"
echo ""
echo "After that completes, watch first sync with:"
echo "  ssh nas '$DOCKER logs -f icloud'"
echo "════════════════════════════════════════════════════════════════"
