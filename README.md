# icloud-docker-plus

A drop-in `mandarons/icloud-docker` image with iOS 26.4+ auth working, **2FA re-authentication from Telegram** (reply from your phone, no shell, no exposed web server), Live Photo `.mov` pairs, per-library destinations, fully templatable filenames, and a dozen other fixes I needed for my own ~70 000-photo iCloud library on a Synology NAS.

```bash
docker pull ghcr.io/epheterson/icloud-docker-plus:latest
```

Same Dockerfile, same entrypoint, same config schema as upstream. Every new feature is opt-in with a safe default. When the PRs land upstream, switch back — your config and on-disk files keep working.

## Why this exists

I wanted iCloud Shared Photo Library + iCloud Drive backed up to my NAS without standing up yet another auth flow per library. Two `boredazfcuk/docker-icloudpd` containers (one per library, each with its own 2FA setup, no Drive at all) wasn't it. `mandarons/icloud-docker` was the right shape — one auth, all libraries, Drive included — so I migrated, hit a string of papercuts (iOS 26.4 broke auth entirely, Live Photos dropped the `.mov`, Personal and Shared dumped into the same tree, no way to re-auth a headless box without a shell…), and fixed them. Putting the result here in case someone else is looking for the same thing.

## What's new vs upstream

| | upstream | here |
|---|---|---|
| iOS 26.4+ trusted-device 2FA | stalls, no code ([#426](https://github.com/mandarons/icloud-docker/issues/426)) | pushes a code & completes — fixed in icloudpy 0.9.0 |
| Re-auth a headless box | shell in and run the CLI by hand | **reply `auth` + the 6-digit code in Telegram** — or the CLI, or the web UI |
| Live Photo `.mov` pair | dropped ([#199](https://github.com/mandarons/icloud-docker/issues/199)) | add `live_video_original` to `file_sizes` |
| Filenames | fixed `name__filesize__id.ext` | `simple` mode **or** a full `file_format` template (`${photo.*}` tokens) |
| Per-library subdirs (Personal vs Shared) | one shared tree | `photos.library_destinations` |
| Migrate from boredazfcuk without re-download | not possible | `filename_format: simple` / matching `file_format` + size-based dedup |
| `--dry-run` pre-flight | none | authenticate + summarize, no writes |
| Bind-mount failsafe | none | opt-in `.mounted` marker (every library subdir, not just root) |
| Keyring across `compose recreate` | wiped, full re-auth every time | persists in `/config` *(merged upstream — [#460](https://github.com/mandarons/icloud-docker/pull/460))* |

Plus smaller fixes: iWork/JMG package downloads no longer count as failures; zip bundles with bare-rooted entries don't clobber siblings; the test suite runs on macOS dev hosts *(merged upstream — [#455](https://github.com/mandarons/icloud-docker/pull/455))*.

> **Memory note:** a large (100k+) photo library can still spike RAM during album enumeration — set `mem_limit` accordingly (≈4 GB for ~100k photos, more for bigger libraries). icloudpy 0.9.0 ships the bounded-memory *primitive* (`iter_chunks`, [icloudpy#140](https://github.com/mandarons/icloudpy/pull/140) — merged), but the icloud-docker *consumer* rework that would use it to stream album enumeration isn't built yet ([#462](https://github.com/mandarons/icloud-docker/pull/462) was closed/superseded), so this image still loads the full album list into memory.

## Quick start

`docker-compose.yml`:

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
      - /path/to/photos:/icloud/photos
      - /path/to/drive:/icloud/drive
    mem_limit: 4g     # large libraries spike during enumeration (no streaming fix yet — see #462)
```

Minimal `config/config.yaml`:

```yaml
app:
  credentials:
    username: you@apple.example
  root: /icloud
  region: global
  logger: { level: info, filename: /config/icloud.log }

photos: { destination: photos, sync_interval: 43200 }
drive:  { destination: drive,  sync_interval: 43200 }
```

Then authenticate (first run, and whenever the ~90-day trust lapses):

```bash
docker compose up -d
docker exec -it icloud sh -c "icloud --username=you@apple.example --session-directory=/config/session_data"
# On icloudpy 0.9.0 this pushes a 6-digit code to your trusted devices; enter it + your password.
docker logs -f icloud
```

Prefer not to shell in every 90 days? See **Re-authentication** below.

## Re-authentication

iCloud trust lapses about every 90 days. Three ways to complete the 2FA, pick whichever fits:

### Telegram (headless — reply from your phone)

No exposed web server, no shell. Set a bot token + chat id and turn on `listen`:

```yaml
app:
  telegram:
    bot_token: <your bot token>
    chat_id: <your chat id>
    listen: true          # poll for replies during a 2FA wait
    auth_keyword: auth     # the word that triggers the push (default "auth")
```

When re-auth is needed the container messages your chat. Reply **`auth`** → Apple pushes a 6-digit code to your devices → reply the **code** → sync resumes. Codes tolerate spaces (`123 456`). Use a 1:1 chat with the bot; for multiple containers give each its own bot token + a distinct `auth_keyword`.

### CLI

`docker exec -it icloud sh -c "icloud --username=… --session-directory=/config/session_data"` — on icloudpy 0.9.0 this pushes a code and prompts for it. (China: add `--region=china`.)

### Web UI

Opt-in `app.web_ui.enabled: true` — Flask app on `:8080` with a dashboard + `/auth` re-auth flow. **No built-in login** — put it behind Cloudflare Access, Tailscale, or your own auth proxy; don't expose it bare.

## Migration

**From upstream `mandarons/icloud-docker`** — swap the image, that's it:

```diff
- image: mandarons/icloud-drive:latest
+ image: ghcr.io/epheterson/icloud-docker-plus:latest
```

**From `boredazfcuk/docker-icloudpd`** without re-downloading anything:

1. Stop your existing boredazfcuk container(s) — leave them stopped, don't `rm` (easy rollback).
2. Mount the parent of your existing per-library dirs at `/icloud/photos`.
3. Set a filename scheme that **reproduces your existing names** so dedup-by-size recognizes them — either `filename_format: simple` (plain `IMG_1234.HEIC`) or an equivalent `file_format` (see below) — plus `library_destinations` mapping each iCloud library to your existing subdir:

   ```yaml
   photos:
     filename_format: simple
     library_destinations:
       PrimarySync: Personal      # ← your existing Personal dir name
       SharedLibrary: Shared      # ← your existing Shared dir name
   ```

4. Pre-flight before the sync loop touches anything:

   ```bash
   docker exec -it icloud python /app/src/main.py --dry-run --check-files 200
   ```

   It walks 200 **photos** per library and reports per-library `would_skip` / `size_mismatch` / `not_found`. If `would_skip` dominates, dedup-by-size will recognize your existing files and nothing re-downloads. If `not_found` dominates, your paths don't line up — fix before the real run. *(Drive-side `--check-files` is photos-only today — [#459](https://github.com/mandarons/icloud-docker/pull/459).)*

5. `docker compose up -d` and watch the logs. Existing files log `No changes detected. Skipping`; only genuine new items download.

## New config knobs

All under `photos:` unless noted. All optional, all default-OFF.

- **`library_destinations: {PrimarySync: personal, SharedLibrary: shared}`** — each iCloud library gets its own subdir of `photos.destination`. `SharedLibrary` matches Apple's GUID-named shared zones (`SharedSync-…`) so you don't hardcode your GUID.
- **`filename_format: simple`** — plain `IMG_1234.HEIC` instead of `IMG_1234__original__<base64id>.HEIC`. Collision-safe (falls back to the suffix form when two photos share a name). Lets you migrate from boredazfcuk without re-downloading. **Pick at install time.**
- **`file_format`** — a single filename template applied to every version (the filename sibling of `folder_format`), overriding `filename_format` when set. Tokens: `${photo.filename}` `${photo.ext}` `${photo.id}` `${photo.file_size}` `${photo.year}` `${photo.month}` `${photo.day}`, plus variant tokens that are **empty for `original`/`full`** and the version name otherwise: `${photo.variant}` (bare) and `${photo.variant_suffix}` (a separator + variant, emitted *only* when there is a variant, so originals stay un-suffixed). Separator via `variant_separator` (default `_`). Example that keeps plain Apple names for originals (so an existing library isn't re-downloaded) but tags variants:
  ```yaml
  photos:
    file_format: "${photo.filename}${photo.variant_suffix}.${photo.ext}"   # IMG_1234.HEIC ; IMG_1234_medium.JPG
  ```
  A templated name that collides falls back to the unique metadata name.
- **Live Photo `.mov`** — add `live_video_original` (and/or `live_video_medium` / `live_video_thumb`) to `photos.filters.file_sizes`. Non-Live-Photos lack those versions and are skipped quietly.
- **`require_mount_marker: true`** — refuse to sync unless a `.mounted` file exists in every destination (each `library_destinations` subdir too — any one could be the failed mount).
- **`preserve_originals_as_bak`** *(being reshaped — [#458](https://github.com/mandarons/icloud-docker/pull/458))* — keeps the unmodified original of an edited photo on disk but hidden from Plex/Photos.app/Synology Photos. Per maintainer feedback this is moving to an `original:hidden` marker inside `file_sizes` rather than a standalone flag; check the PR for the current shape.

## PRs feeding this image — status

Building blocks in `mandarons/icloudpy` (RFC [icloudpy#137](https://github.com/mandarons/icloudpy/issues/137)):

| PR | what | status |
|---|---|---|
| [icloudpy#138](https://github.com/mandarons/icloudpy/pull/138) | iOS 26.4+ 2FA push trigger | ✅ merged (in 0.9.0) |
| [icloudpy#139](https://github.com/mandarons/icloudpy/pull/139) | Live Photo `.mov` via `live_video_*` keys | ✅ merged (in 0.9.0) |
| [icloudpy#140](https://github.com/mandarons/icloudpy/pull/140) | `iter_chunks` (bounded-memory enumeration primitive) | ✅ merged (in 0.9.0) |

In `mandarons/icloud-docker` (RFC [icloud-docker#454](https://github.com/mandarons/icloud-docker/issues/454)):

| PR | what | status |
|---|---|---|
| [#455](https://github.com/mandarons/icloud-docker/pull/455) | test suite green on macOS/sandbox dev hosts | ✅ merged |
| [#460](https://github.com/mandarons/icloud-docker/pull/460) | persist python-keyring across container recreate | ✅ merged |
| [#471](https://github.com/mandarons/icloud-docker/pull/471) | bump icloudpy → 0.9.0 (the universal 2FA-push fix; also fixes the CLI flow) | 🔄 open |
| [#470](https://github.com/mandarons/icloud-docker/pull/470) | complete 2FA from Telegram (optional, headless) | 🔄 open |
| [#456](https://github.com/mandarons/icloud-docker/pull/456) | `photos.library_destinations` | 🔄 open |
| [#457](https://github.com/mandarons/icloud-docker/pull/457) | `filename_format: simple` + `file_format` templates | 🔄 open |
| [#458](https://github.com/mandarons/icloud-docker/pull/458) | preserve originals of edited photos (reshaping to `original:hidden`) | 🔄 open |
| [#459](https://github.com/mandarons/icloud-docker/pull/459) | `--dry-run` pre-flight | 🔄 open |
| [#461](https://github.com/mandarons/icloud-docker/pull/461) | Drive package single-file bundles (iWork, JMG) | 🔄 open |
| [#463](https://github.com/mandarons/icloud-docker/pull/463) | `require_mount_marker` failsafe | 🔄 open |
| [#464](https://github.com/mandarons/icloud-docker/pull/464) | embedded web UI | 🔄 open |
| [#465](https://github.com/mandarons/icloud-docker/pull/465) | Live Photo `.mov` via `file_sizes` | 🔄 open |
| [#462](https://github.com/mandarons/icloud-docker/pull/462) | streaming photo enumeration (bounds peak RSS) | ❌ closed — superseded by icloudpy#140; consumer rework pending |

> **The 2FA work was split at the maintainer's request:** [#471](https://github.com/mandarons/icloud-docker/pull/471) is the universal fix (the icloudpy bump — also makes the documented `docker exec … icloud` re-auth push a code), and [#470](https://github.com/mandarons/icloud-docker/pull/470) is the *optional* Telegram convenience layer on top.

This image is built from [`epheterson/icloud-docker@combined/all-features`](https://github.com/epheterson/icloud-docker/tree/combined/all-features) — every open PR above merged — on top of the released `icloudpy==0.9.0`. (The [`epheterson/icloudpy@combined/all-fixes`](https://github.com/epheterson/icloudpy/tree/combined/all-fixes) fork is no longer needed now that icloudpy#138/#139/#140 shipped in 0.9.0.)

## Lifecycle

This is a bridge image. As each PR lands in an upstream release the table above flips to ✅; when they're all in (or superseded), swap back to `mandarons/icloud-drive:latest` — your config + on-disk files keep working — and this repo archives.

## Acknowledgments

Built on:
- **[`mandarons/icloud-docker`](https://github.com/mandarons/icloud-docker)** + **[`mandarons/icloudpy`](https://github.com/mandarons/icloudpy)** by Mandar Patil — the foundation.
- **[`boredazfcuk/docker-icloudpd`](https://github.com/boredazfcuk/docker-icloudpd)** — prior-art patterns ported into several PRs (simple filenames, mount marker, package handling, keyring persistence).
- **[`icloud-photos-downloader`](https://github.com/icloud-photos-downloader/icloud_photos_downloader)** — reference for the iOS 26.4 SRP auth fix.

Questions or issues? [Open an issue](https://github.com/epheterson/icloud-docker-plus/issues) or submit a PR. For things that should land upstream, file with Mandar directly — these are his repos, I'm just shipping a bridge.

## License

MIT · *Unofficial bridge image, not affiliated with Mandar Patil or Apple.*

Upstream licenses: [`mandarons/icloud-docker`](https://github.com/mandarons/icloud-docker) Apache 2.0 · [`mandarons/icloudpy`](https://github.com/mandarons/icloudpy) MIT.

---

Built with ❤️ in California by [@epheterson](https://github.com/epheterson) and [Claude Code](https://claude.ai/code).
