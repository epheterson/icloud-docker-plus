# icloud-docker-overlay

> Drop-in replacement for [`mandarons/icloud-drive`](https://hub.docker.com/r/mandarons/icloud-drive) that **works on iOS 26.4+**, **downloads Live Photos correctly**, **keeps Personal and Shared libraries in separate dirs**, and **lets boredazfcuk users migrate without re-downloading their entire library**.

```bash
docker pull ghcr.io/epheterson/icloud-docker-overlay:latest
```

Built from a fork of `mandarons/icloud-docker` with four pending upstream PRs already applied. When all four PRs merge upstream, this image gets archived — switch back to `mandarons/icloud-drive:latest`.

---

## What this fixes vs. upstream mandarons

| Capability | Upstream `mandarons/icloud-drive` | This image |
|---|---|---|
| **iCloud auth on iOS 26.4+ trusted devices** | ❌ Broken since Feb 2026 — 2FA code never arrives ([#426](https://github.com/mandarons/icloud-docker/issues/426)) | ✅ Push notification triggered correctly |
| **Live Photo `.mov` pair download** | ❌ HEIC only, paired `.mov` dropped ([#199](https://github.com/mandarons/icloud-docker/issues/199), open since 2024) | ✅ Both HEIC + paired `.mov` land on disk |
| **Per-library subdirectories** (Personal vs Shared) | ❌ All photos in one tree | ✅ Optional `photos.library_destinations` |
| **Migrate from boredazfcuk/docker-icloudpd without re-download** | ❌ Different filename convention → full re-download | ✅ Optional `photos.filename_format: simple` + size-based existence check |
| **Filename collision safety** | ❌ Two iCloud photos sharing a name silently overwrite | ✅ Collision-fallback to suffix path, both preserved |
| **Hide originals of edited photos from photo apps** | ❌ Original + edited both visible (duplicates in Plex etc.) | ✅ Optional `photos.preserve_originals_as_bak` writes original as `IMG_1234.HEIC.original.bak` |
| Everything else | ✅ | ✅ identical (same source, same Dockerfile, same entrypoint) |

All new config keys are **opt-in with safe defaults** — vanilla mandarons users see no behavior change.

---

## Quick start (fresh install)

`/path/to/icloud/docker-compose.yml`:

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
      - /path/to/your/photos:/icloud/photos
      - /path/to/your/drive:/icloud/drive
```

`/path/to/icloud/config/config.yaml` — minimal:

```yaml
app:
  credentials:
    username: you@apple.example
  root: /icloud
  region: global
  logger:
    level: info
    filename: /config/icloud.log

photos:
  destination: photos
  sync_interval: 43200      # 12 hours
  filters:
    file_sizes:
      - original

drive:
  destination: drive
  sync_interval: 43200
```

Then:

```bash
docker compose pull && docker compose up -d
docker exec -it icloud sh -c "icloud --username=you@apple.example --session-directory=/config/session_data"
# ← enter password + 6-digit 2FA code from your trusted device
docker logs -f icloud
```

---

## Migrate from `boredazfcuk/docker-icloudpd` (zero re-download)

If you're running one or more boredazfcuk-icloudpd containers (one for Personal, one for Shared library, etc.) and want to consolidate to a single one-2FA setup without re-downloading your photo library:

### 1. Stop your existing boredazfcuk containers
```bash
docker stop iCloudPD-Eric iCloudPD-Shared   # or whatever you named them
```
Leave them stopped (don't `rm`) for easy rollback. Files on disk are untouched.

### 2. Identify your existing photo paths
Note what host paths your boredazfcuk containers wrote to. Common patterns:
- `/volume1/photos/iCloud/Personal/` and `/volume1/photos/iCloud/Shared/`
- `/volume1/ELP NAS/Pictures/iCloud/Eric/` and `.../Shared/`

You'll point this container at the **parent** dir and use `library_destinations` to map each library to your existing subdir name.

### 3. Drop in a config that uses BOTH new knobs

```yaml
app:
  credentials:
    username: you@apple.example
  root: /icloud
  region: global
  logger:
    level: info
    filename: /config/icloud.log

photos:
  destination: photos
  remove_obsolete: true       # mirror iCloud deletes (boredazfcuk default behavior)
  sync_interval: 43200
  # KEY: produce plain IMG_1234.HEIC filenames matching what boredazfcuk wrote.
  # Existence check is by file size (not filename suffix), so existing files
  # are recognised and SKIPPED.
  filename_format: simple
  # KEY: keep Personal/Shared in your existing subdirs (these names MUST
  # match your on-disk directory names exactly).
  library_destinations:
    PrimarySync: Personal      # ← your existing Personal dir name
    SharedLibrary: Shared      # ← your existing Shared dir name
  filters:
    libraries:
      - PrimarySync
      - SharedLibrary
    file_sizes:
      - original

drive:
  destination: drive            # fresh dir (boredazfcuk doesn't do Drive)
  sync_interval: 43200
```

### 4. Compose with the right mounts

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
      - /volume1/docker/icloud/config:/config
      # Mount the PARENT of your existing per-library dirs:
      - /volume1/photos/iCloud:/icloud/photos          # ← your existing parent
      # Drive is brand-new:
      - /volume1/photos/iCloud-Drive:/icloud/drive
```

### 5. Run it
```bash
docker compose pull && docker compose up -d
docker exec -it icloud sh -c "icloud --username=you@apple.example --session-directory=/config/session_data"
docker logs -f icloud
```

### What to expect in the first sync
- Existing photos: `No changes detected. Skipping the file ...` for each (the existence check matched by size)
- New photos since boredazfcuk's last sync: actually downloaded
- Live Photos: from now on land as `IMG_1234.HEIC` AND `IMG_1234.MOV` (paired)
- Drive: fresh download of everything

### Once you trust it
```bash
docker rm iCloudPD-Eric iCloudPD-Shared   # remove the stopped boredazfcuk containers
```

### Roll back to boredazfcuk if needed
The container hasn't renamed your files; they're still `IMG_1234.HEIC` (because of `filename_format: simple`). To revert:
```bash
docker compose down
docker start iCloudPD-Eric iCloudPD-Shared
```

---

## Migrate from upstream `mandarons/icloud-drive`

If you're already running mandarons and it's stuck on iOS 26.4 (#426) or you want Live Photos / per-library dirs:

### Minimum migration: just swap the image

```yaml
# Change this in your existing docker-compose.yml:
- image: mandarons/icloud-drive:latest
+ image: ghcr.io/epheterson/icloud-docker-overlay:latest
```

Then `docker compose pull && docker compose up -d`. Your existing config.yaml works unchanged — all new features are opt-in.

### Optionally add the new knobs

Open your `config.yaml` and add any of:

```yaml
photos:
  # ... existing config ...

  # Separate Personal and Shared libraries into subdirs
  library_destinations:
    PrimarySync: personal
    SharedLibrary: shared

  # Switch to plain filenames (irreversible without re-download — only do this
  # if you're migrating from boredazfcuk OR doing a fresh install)
  filename_format: simple

  # Hide untouched originals of edited photos via .original.bak suffix
  # (requires `original` AND `original_alt` in file_sizes below)
  preserve_originals_as_bak: true

  filters:
    file_sizes:
      - original
      - original_alt   # ← add this to also download the edited version
```

For Live Photos: no config change needed — if `"original"` is in `file_sizes`, the paired `.mov` downloads automatically.

---

## New config options reference

All under the `photos:` section. All optional. All default-OFF for backward compatibility.

### `library_destinations` (default: empty)

Map each iCloud photo library to a subdirectory of `photos.destination`. When empty/unset, all libraries share one tree (legacy behavior).

```yaml
photos:
  destination: photos
  library_destinations:
    PrimarySync: personal      # → photos/personal/...
    SharedLibrary: shared      # → photos/shared/...
```

Library names mandarons recognises: `PrimarySync` (your own library), `SharedLibrary` (iCloud Shared Photo Library). Album-named iCloud libraries (e.g. Family) appear under their human name.

### `filename_format` (default: `metadata`)

```yaml
photos:
  filename_format: metadata    # legacy mandarons: IMG_1234__original__<base64id>.HEIC
  # OR
  filename_format: simple      # plain: IMG_1234.HEIC
```

- **`metadata`** — uniquely identifies each photo by encoding its CloudKit asset id into the filename. Robust against filename collisions but breaks portability (Plex / Photos.app / file managers see ugly names).
- **`simple`** — plain `IMG_1234.HEIC` style. Portable, matches what Apple's own iCloud.com web download produces and what boredazfcuk writes. **Collision-safe**: if two distinct iCloud photos share a human filename, the colliding photo automatically falls back to the suffix form so both files coexist on disk.

⚠ **Cannot be safely changed mid-flight** — switching between formats after files exist means mandarons won't recognise the previously-downloaded files and will re-download them. Pick once at install time.

### Live Photo `.mov` auto-download

No config option — automatic. When `"original"` is in `file_sizes` AND a photo is a Live Photo, the paired `.mov` is also downloaded. Naming:
- Simple mode: `IMG_1234.HEIC` + `IMG_1234.MOV`
- Metadata mode: `IMG_1234__original__<id>.HEIC` + `IMG_1234__live_video_original__<id>.MOV`

To opt out: don't put `"original"` in `file_sizes` (use only `medium` or `thumb`).

### `preserve_originals_as_bak` (default: `false`)

```yaml
photos:
  preserve_originals_as_bak: true
  filters:
    file_sizes:
      - original              # untouched original (will be hidden via .bak)
      - original_alt          # current "edited" view (visible)
```

**Requires both `original` AND `original_alt` in `file_sizes`** to be meaningful — without `original_alt`, the edited "current view" isn't downloaded and you just get hidden originals with no visible counterpart. The toggle is harmless without `original_alt` (it just has no effect), but the pairing is the intended use.

When `true` AND both `original` and `original_alt` are in `file_sizes`, edited photos land as TWO files:

```
IMG_1234.JPG                # the edited "current view" — visible in Plex/Photos/Synology Photos
IMG_1234.HEIC.original.bak  # the untouched original — no app recognises .bak as image, so hidden
```

Unedited photos (no `original_alt` available for them on iCloud) are unaffected.

To restore an original: rename `IMG_1234.HEIC.original.bak` → `IMG_1234.HEIC`. Easy `find . -name "*.original.bak"` to enumerate all hidden originals.

---

## How the image is composed (provenance)

This image is built from a fork of `mandarons/icloud-docker` whose `requirements.txt` pins a fork of `mandarons/icloudpy`. Six pending upstream PRs:

### To `mandarons/icloudpy` (the underlying iCloud Python library)
1. [`fix/ios-26.4-auth`](https://github.com/epheterson/icloudpy/tree/fix/ios-26.4-auth) — iOS 26.4 SRP auth fix
2. [`feat/live-photos`](https://github.com/epheterson/icloudpy/tree/feat/live-photos) — surfaces Live Photo `.mov` via new `live_video_*` version keys

### To `mandarons/icloud-docker` (the container project)
3. [`feat/photos-library-destinations`](https://github.com/epheterson/icloud-docker/tree/feat/photos-library-destinations) — per-library subdirs
4. [`feat/photos-live-photo-pair-download`](https://github.com/epheterson/icloud-docker/tree/feat/photos-live-photo-pair-download) — uses the new icloudpy API to download `.mov` pair
5. [`feat/photos-filename-format-simple`](https://github.com/epheterson/icloud-docker/tree/feat/photos-filename-format-simple) — simple naming + collision fallback
6. [`feat/photos-preserve-originals-as-bak`](https://github.com/epheterson/icloud-docker/tree/feat/photos-preserve-originals-as-bak) — `.original.bak` for hidden originals

The combined branches for the actual build are [`epheterson/icloudpy@combined/all-fixes`](https://github.com/epheterson/icloudpy/tree/combined/all-fixes) and [`epheterson/icloud-docker@combined/all-features`](https://github.com/epheterson/icloud-docker/tree/combined/all-features).

---

## Lifecycle / when to stop using this

This repo + image are a **bridge**. When the four mandarons/icloud-docker PRs merge upstream and mandarons publishes a release that pulls them in, switch back to vanilla `mandarons/icloud-drive:latest`. All your config + on-disk files keep working.

This README will be updated with "✅ Upstream has merged X" markers as each PR lands. When all four are merged, the README will say "Archived — use upstream."

---

## Versioning

| Version | Date | Notes |
|---|---|---|
| `0.4.1` | 2026-05-27 | Code-review pass: `validate_file_sizes` filters internal `live_video_*` keys; simple+bak interaction fixed; `setup.sh` uses `su-exec abc` for 2FA |
| `0.4.0` | 2026-05-27 | Added `preserve_originals_as_bak`; split combined branch into six PR-able feature branches |
| `0.3.x` | 2026-05-27 | filename_format simple + collision fallback + multiple critical fixes |
| `0.2.0` | 2026-05-27 | First image built from forked icloud-docker (vs overlay-FROM pattern in 0.1) |
| `0.1.0` | 2026-05-27 | Initial overlay (just icloudpy fix layered on mandarons/icloud-drive) |

Tags `:latest` always points at the newest tagged release. Pin to a specific tag if you want stability between deploys.

---

## License

MIT.

The upstream projects this builds on top of have their own licenses:
- [`mandarons/icloud-docker`](https://github.com/mandarons/icloud-docker) — Apache 2.0
- [`mandarons/icloudpy`](https://github.com/mandarons/icloudpy) — MIT
