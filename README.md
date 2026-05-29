# icloud-docker-plus

> **[`mandarons/icloud-docker`](https://github.com/mandarons/icloud-docker) with my pending upstream PRs already applied.** Use it while those PRs are in review; switch back to upstream the moment they merge.

```bash
docker pull ghcr.io/epheterson/icloud-docker-plus:latest
```

Same Dockerfile, same entrypoint, same config schema as upstream — just six [pending PRs](#how-the-image-is-composed-provenance) layered in (2 to `icloudpy` + 4 to `icloud-docker`). When upstream merges, this repo + image archive and you point `:image:` at `mandarons/icloud-drive:latest`. Config and on-disk files keep working unchanged.

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
| **`--dry-run` pre-flight check** | ❌ No way to verify auth + mounts before downloading | ✅ `python src/main.py --dry-run` authenticates, summarises, exits without writing |
| **Mount-failsafe marker file** (boredazfcuk-style `.mounted` check) | ❌ Silent bind-mount failure → terabytes into wrong dir | ✅ Optional `{drive,photos}.require_mount_marker` refuses to sync unless `.mounted` exists |
| **Embedded web UI** (re-auth from your phone, dashboard, log tail) | ❌ Port 80 EXPOSEd but never used | ✅ Opt-in via `app.web_ui.enabled`, runs on `:8080`, Apple-leaning UI |
| **Keyring persists across container recreations** | ❌ `$HOME/.local/share/python_keyring/` is wiped on every `compose up`; user re-auths on every image bump | ✅ Entrypoint pins `XDG_DATA_HOME=/config`, keyring lives at `/config/python_keyring/keyring_pass.cfg` |
| Everything else | ✅ | ✅ identical (same source, same Dockerfile, same entrypoint) |

All new config keys are **opt-in with safe defaults** — vanilla mandarons users see no behavior change.

---

## Quick start (fresh install)

`/path/to/icloud/docker-compose.yml`:

```yaml
services:
  icloud:
    image: ghcr.io/epheterson/icloud-docker-plus:latest
    container_name: icloud
    restart: unless-stopped
    environment:
      - TZ=America/Los_Angeles
      - ENV_CONFIG_FILE_PATH=/config/config.yaml
    volumes:
      - ./config:/config
      - /path/to/your/photos:/icloud/photos
      - /path/to/your/drive:/icloud/drive
    # See "Resource sizing" below — tune to your photo library size.
    # 8GB suits a typical 100K-photo iCloud library. Smaller libraries
    # can use less; very large ones need more (mandarons peaks during
    # the initial library enumeration, before downloads start).
    mem_limit: 8g
    memswap_limit: 12g
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
    # No `libraries` filter? Means sync ALL libraries on your Apple ID —
    # your personal (PrimarySync) AND iCloud Shared Photo Library
    # (SharedLibrary) if you have it enabled at icloud.com/photos.
    # To restrict, list them explicitly:
    #   libraries:
    #     - PrimarySync       # your own library only
    #     - SharedLibrary     # shared library only
    # By default they all dump to photos.destination/ — see
    # library_destinations below to separate them into subdirs.

drive:
  destination: drive
  sync_interval: 43200
```

**iCloud Shared Photo Library is on by default** — if your Apple ID has it enabled, this container picks it up automatically. No config change needed. (Want to OPT OUT and keep it personal-only? Add `libraries: [PrimarySync]` under `filters`.)

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
- `/volume1/photo/iCloud/<YourName>/` and `.../Shared/` (custom share-name setups)

You'll point this container at the **parent** dir (e.g. `/volume1/photos/iCloud`) and use `library_destinations` to map each library to your existing subdir name.

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
    image: ghcr.io/epheterson/icloud-docker-plus:latest
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
    # 4GB suits a ~100K-photo library. Bump if your library is larger.
    # See "Resource sizing" section below.
    mem_limit: 4g
    memswap_limit: 6g
```

### 5. Run it
```bash
docker compose pull && docker compose up -d
docker exec -it icloud sh -c "icloud --username=you@apple.example --session-directory=/config/session_data"
```

### 6. **Run the per-file migration-match check BEFORE the real sync**

After 2FA but before letting the sync loop touch a single file, run:

```bash
docker exec -it icloud python /app/src/main.py --dry-run --check-files 200
```

This walks up to 200 photos per library AND up to 200 Drive files, computes the on-disk path mandarons WOULD use, and reports per-service counts:

- `would_skip` — file exists at target path AND size matches (good — migration matching working)
- `size_mismatch` — file exists but different size (would re-download — investigate)
- `not_found` — target path empty (would download as new — expected for new items, alarming if old)
- `error` — couldn't compute path or check disk

Reported separately for each photo library (`PrimarySync`, `SharedSync-<GUID>`, etc.) and for iCloud Drive. Photos validates `library_destinations` / `folder_format` / `filename_format`; Drive validates `drive.destination` and that your existing Drive tree mirrors what iCloud reports.

Healthy migration: **`would_skip` should dominate** for the sample. If `not_found` dominates on a service, your config doesn't line up with the existing on-disk layout — fix BEFORE running the real sync, or mandarons will re-download everything for that service.

Pass `--check-files 0` to walk the entire library + entire Drive (slow on 100K+ libraries; do a small sample first).

### 7. Let it sync
```bash
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
+ image: ghcr.io/epheterson/icloud-docker-plus:latest
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

### `--dry-run` pre-flight check

```bash
# Run once after editing config.yaml + docker-compose.yml, before letting
# the real sync loop touch any files:
docker exec -it icloud sh -c "su-exec abc python /app/src/main.py --dry-run"
```

Authenticates against iCloud, prints:
- Drive destination + root-level item count (or "would be skipped" if `drive:` is absent)
- Photos destination + available library names (or "would be skipped" if `photos:` is absent)
- A `DRY RUN complete — no files were written` line

Exits non-zero only on hard auth failure. If 2FA is pending, prints a hint to finish interactive auth first. No notifications sent, no files written, no infinite loop. Cheap safety net before a fresh install.

### `require_mount_marker` (default: `false`)

Ports boredazfcuk/docker-icloudpd's `.mounted` failsafe. Refuses to sync a service unless a marker file is present in its destination directory — the user's way of asserting "this path is correctly bind-mounted."

```yaml
app:
  mount_marker_filename: .mounted     # optional, default ".mounted"

drive:
  require_mount_marker: true

photos:
  require_mount_marker: true
```

After confirming the container's destination dirs really are your intended host paths, run once on each:
```bash
ssh nas 'touch "/volume1/your/drive/.mounted" "/volume1/your/photos/.mounted"'
```
From that point on, if the bind-mount silently fails (typo, missing share, NFS unreachable, permissions reset), the container refuses to sync — preventing terabytes of iCloud data from being dumped into a tmpfs the user can't see. The countdown is not advanced on a missed check, so re-mounting + touching the file is enough to recover (no container restart needed).

Default is OFF for backward compatibility; existing setups see no behaviour change.

### `web_ui` — built-in dashboard + re-auth from your phone

Opt-in via `app.web_ui.enabled: true`. When enabled, a Flask app starts on `:8080` inside the container alongside the sync loop.

```yaml
app:
  web_ui:
    enabled: true     # default false — don't surprise vanilla users
    host: 0.0.0.0     # default
    port: 8080        # default
```

`docker-compose.yml`:
```yaml
services:
  icloud:
    image: ghcr.io/epheterson/icloud-docker-plus:latest
    ports:
      - "8080:8080"   # add this — adds host port mapping
    # ... rest unchanged
```

What's there:
- **Dashboard at `/`** — current Apple ID, mount-marker status per service, sync intervals, last 200 log lines.
- **Re-authentication at `/auth`** — password → push notification to your trusted device → 6-digit code → trusted session written to the same `/config/session_data` the sync loop reads. The next sync loop iteration picks up the now-trusted session.
- **JSON API** for monitors / scripts: `/api/health`, `/api/status`, `/api/logs`.

**No built-in login.** Designed for Cloudflare Tunnel / Authelia / Tailscale front-ends. Do NOT expose `:8080` to the public internet without an auth proxy. Run locally first; protect before opening up.

What's NOT in v1 (deferred — open an issue if you want any of these):
- Apple's older 2-step (2SA) flow — pure 2FA only.
- "Force sync now" button.
- Inline content browser (Notes / Drive contents view).
- CSRF token (relies on the auth-proxy layer to gate access).

---

## Operational notes

### Resource sizing

Photo libraries are the dominant memory pressure. mandarons enumerates the entire library asset list in RAM before downloads start — for an 111K-photo library this peaks at **~4 GB RSS** (empirically measured: a 4 GB-capped container OOM-killed mid-enumeration; cgroup dmesg showed `total-vm:4270872kB anon-rss:4181524kB`).

| Library size | `mem_limit` | `memswap_limit` |
|---|---|---|
| <10K photos | 1 GB | 2 GB |
| 10–50K photos | 2 GB | 4 GB |
| 50–100K photos | 4 GB | 6 GB |
| 100–150K photos (**default recommendation for typical iCloud users**) | 8 GB | 12 GB |
| >150K photos | 12 GB | 2× mem |

How to know you're undersized: container restarts with `Killed` in the logs mid-`Syncing All Photos`, and the next start re-runs Drive sync from scratch. On Linux, `dmesg | grep -i oom` is authoritative (look for `Memory cgroup out of memory`). Docker's own `OOMKilled` flag resets on container restart and is often misleading — trust dmesg.

Drive sync is memory-light (linear walk per folder); Photos is the constraint. Once a sync has completed a full pass, steady-state memory is far lower — but you need the headroom for the initial backfill.

### iCloud Drive packages (iWork, etc.)

Apple's iWork formats (`.key`, `.pages`, `.numbers`) and similar bundle formats (`.band` GarageBand, third-party `.jmb`, etc.) are technically "directory bundles" — Finder shows one file, but the on-disk representation is a directory of XML + assets.

iCloud Drive serves these as a single archive per download. mandarons attempts to detect the archive type via libmagic and unpack it. If the archive type is `application/zip` or `application/gzip`, it works. **Anything else (most Apple iWork files report `application/octet-stream` for some reason) currently triggers a verbose `Unhandled file type` error and the file is counted as a failed download**, even though the bytes ARE saved to disk as a flat single-file bundle (which Keynote, Pages, etc. open fine).

Practical effect:
- **No data loss** — the file is present at the target path, you can open it directly.
- **Wasted bandwidth on every container restart** — mandarons re-downloads the file each time, because the "failed" flag prevents marking it as up-to-date.

Fix in progress as a separate upstream PR. Until it lands, expect noisy `drive_package_processing.py :: Unhandled file type` lines for iWork/`.jmb`/etc files. Safe to ignore unless your Drive sync is dominated by these (large iWork archives), in which case bumping `mem_limit` doesn't help; only the upstream fix or removing those files from iCloud Drive does.

---

## How the image is composed (provenance)

This image is built from a fork of `mandarons/icloud-docker` whose `requirements.txt` pins a fork of `mandarons/icloudpy`. Ten pending upstream PRs (2 to `icloudpy` + 8 to `icloud-docker`):

### To `mandarons/icloudpy` (the underlying iCloud Python library)
1. [`fix/ios-26.4-auth`](https://github.com/epheterson/icloudpy/tree/fix/ios-26.4-auth) — iOS 26.4 SRP auth fix
2. [`feat/live-photos`](https://github.com/epheterson/icloudpy/tree/feat/live-photos) — surfaces Live Photo `.mov` via new `live_video_*` version keys

### To `mandarons/icloud-docker` (the container project)
3. [`feat/photos-library-destinations`](https://github.com/epheterson/icloud-docker/tree/feat/photos-library-destinations) — per-library subdirs
4. [`feat/photos-live-photo-pair-download`](https://github.com/epheterson/icloud-docker/tree/feat/photos-live-photo-pair-download) — uses the new icloudpy API to download `.mov` pair
5. [`feat/photos-filename-format-simple`](https://github.com/epheterson/icloud-docker/tree/feat/photos-filename-format-simple) — simple naming + collision fallback
6. [`feat/photos-preserve-originals-as-bak`](https://github.com/epheterson/icloud-docker/tree/feat/photos-preserve-originals-as-bak) — `.original.bak` for hidden originals
7. [`feat/dry-run`](https://github.com/epheterson/icloud-docker/tree/feat/dry-run) — `--dry-run` CLI flag (authenticate + enumerate + exit)
8. [`feat/require-mount-marker`](https://github.com/epheterson/icloud-docker/tree/feat/require-mount-marker) — opt-in `.mounted` failsafe file requirement
9. [`feat/web-ui`](https://github.com/epheterson/icloud-docker/tree/feat/web-ui) — embedded Flask dashboard + on-device 2FA re-auth flow
10. [`feat/persist-keyring`](https://github.com/epheterson/icloud-docker/tree/feat/persist-keyring) — `XDG_DATA_HOME=/config` so the keyring survives container recreation

The combined branches for the actual build are [`epheterson/icloudpy@combined/all-fixes`](https://github.com/epheterson/icloudpy/tree/combined/all-fixes) and [`epheterson/icloud-docker@combined/all-features`](https://github.com/epheterson/icloud-docker/tree/combined/all-features).

---

## Lifecycle / when to stop using this

This repo + image are a **bridge**. When the eight mandarons/icloud-docker PRs (plus the two icloudpy PRs) merge upstream and mandarons publishes a release that pulls them in, switch back to vanilla `mandarons/icloud-drive:latest`. All your config + on-disk files keep working.

This README will be updated with "✅ Upstream has merged X" markers as each PR lands. When all ten are merged, the README will say "Archived — use upstream."

---

## Versioning

| Version | Date | Notes |
|---|---|---|
| `0.6.7` | 2026-05-28 | `--dry-run --check-files N` extension to PR 7: walks N photos per library, reports `would_skip` / `size_mismatch` / `not_found` counts. The recommended pre-flight for boredazfcuk→mandarons migration. Plus `SharedLibrary` alias matches Apple's GUID-named shared zones (e.g. `SharedSync-3C97...`), and entrypoint always chowns the new `/config/python_keyring` dir. README now documents memory sizing rules + the iWork-package re-download caveat. |
| `0.6.6` | 2026-05-28 | Web-UI hardening for behind-proxy deployments: ProxyFix middleware, `Cache-Control: no-store`, `threaded=True`. Test fixture restores `ENV_CONFIG_FILE_PATH` so the test suite doesn't bleed env state across cases. |
| `0.6.5` | 2026-05-28 | Persist python-keyring at `/config/python_keyring/` (PR 10) so the keyring survives container recreate. Plus iterative web-UI polish: truthful auth-state pill, library_destinations on dashboard, "already signed in" view on `/auth`, ProxyFix + no-cache headers for behind-proxy behaviour. |
| `0.6.0` | 2026-05-28 | Embedded web UI (PR 9): dashboard + on-device 2FA re-auth flow (Apple-leaning design, opt-in via `app.web_ui.enabled`) |
| `0.5.0` | 2026-05-27 | New `--dry-run` CLI flag (PR 7) + opt-in `require_mount_marker` failsafe (PR 8) — safety net for fresh installs |
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
