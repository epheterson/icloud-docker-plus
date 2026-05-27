# icloud-docker-overlay

Docker image of [`mandarons/icloud-docker`](https://github.com/mandarons/icloud-docker) with three pending upstream PRs already applied — restores iCloud auth on iOS 26.4+, downloads Live Photo `.mov` pairs properly, and supports per-library destination directories.

## What's in this image vs. upstream mandarons

| Capability | Upstream `mandarons/icloud-docker` | This image |
|---|---|---|
| **iCloud auth on iOS 26.4+** | ❌ Broken — 2FA code never arrives ([#426](https://github.com/mandarons/icloud-docker/issues/426)) | ✅ Push notification triggered correctly |
| **Live Photo `.mov` download** | ❌ HEIC only ([#199](https://github.com/mandarons/icloud-docker/issues/199), open since 2024) | ✅ Both HEIC + paired `.mov` |
| **Per-library destinations** | ❌ All photos land in one tree | ✅ Optional `library_destinations` config block |
| **Migrate from boredazfcuk/docker-icloudpd** | ❌ Re-downloads everything (different filename convention) | ✅ Optional `filename_format: simple` reuses existing files (no re-download) |
| Everything else | ✅ | ✅ identical |

## Quick start

```bash
docker pull ghcr.io/epheterson/icloud-docker-overlay:latest
```

`docker-compose.yml`:

```yaml
services:
  icloud:
    image: ghcr.io/epheterson/icloud-docker-overlay:latest
    container_name: icloud
    restart: unless-stopped
    environment:
      - TZ=America/Los_Angeles
      - ENV_CONFIG_FILE_PATH=/config/config.yaml
    volumes:
      - ./config:/config
      - /path/to/photos:/icloud/photos
      - /path/to/drive:/icloud/drive
```

`config.yaml` — uses the standard mandarons schema, plus the new optional `library_destinations`:

```yaml
app:
  credentials:
    username: you@me.com
  root: /icloud
  region: global
photos:
  destination: photos
  sync_interval: 43200      # 12h
  library_destinations:     # NEW (optional) — preserves per-library separation
    PrimarySync: personal
    SharedLibrary: shared
  filters:
    file_sizes: [original]
    libraries: [PrimarySync, SharedLibrary]
drive:
  destination: drive
  sync_interval: 43200
```

First-time 2FA:
```bash
docker exec -it icloud sh -c "icloud --username=you@me.com --session-directory=/config/session_data"
```

## How the patches compose

This image is built from a fork of `mandarons/icloud-docker` ([`epheterson/icloud-docker@feat/per-library-destinations-and-live-photos`](https://github.com/epheterson/icloud-docker/tree/feat/per-library-destinations-and-live-photos)) whose `requirements.txt` pins a fork of `mandarons/icloudpy` ([`epheterson/icloudpy@combined/all-fixes`](https://github.com/epheterson/icloudpy/tree/combined/all-fixes)) containing the iOS 26.4 auth fix + Live Photo `.mov` surfacing.

Three upstream PRs are in flight:

1. **icloudpy** — [iOS 26.4 SRP auth fix](https://github.com/epheterson/icloudpy/tree/fix/ios-26.4-auth) → `mandarons/icloudpy`
2. **icloudpy** — [Live Photo `.mov` surfacing](https://github.com/epheterson/icloudpy/tree/feat/live-photos) → `mandarons/icloudpy`
3. **icloud-docker** — [per-library destinations + Live Photo download](https://github.com/epheterson/icloud-docker/tree/feat/per-library-destinations-and-live-photos) → `mandarons/icloud-docker`

**This repo is a bridge.** When all three merge upstream and mandarons publishes a new container release, switch back to `mandarons/icloud-drive:latest`.

MIT.
