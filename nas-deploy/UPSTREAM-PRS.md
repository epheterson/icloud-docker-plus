# Three upstream PR drafts (push tonight)

Each goes to its respective repo. Submit in this order — they're independent
but maintainer can land them in any sequence.

---

## PR 1: `mandarons/icloudpy` ← `epheterson/icloudpy:fix/ios-26.4-auth`

**Title:** `fix: trigger 2FA push notification on iOS 26.4+ (resolves the auth stall in mandarons/icloud-docker#426)`

**Body:**

```markdown
## Summary
Restores 2FA on iOS 26.4+ trusted devices.

Since iOS 26.4 (Feb 2026), `validate_2fa_code()` is unreachable in practice
because the 6-digit code never arrives on any trusted device — Apple changed
the flow to require an explicit `PUT /verify/trusteddevice/securitycode`
(no body) to initiate code delivery. Without it, callers see
"Please enter validation code" and wait forever.

This PR adds `ICloudPyService.trigger_2fa_push_notification()` — the explicit
PUT — and wires it into the bundled `icloudpy` CLI so it works out of the
box. The bundled `cmdline.py` calls it right after `requires_2fa` returns
True and before prompting the user for the code.

Other library consumers (mandarons/icloud-docker, etc.) need only add a
single `api.trigger_2fa_push_notification()` call before their own
prompt-for-code logic to inherit the fix.

Refs: mandarons/icloud-docker#426

## Validation
- 4 new unit tests in `tests/test_auth.py`:
  - `test_trigger_2fa_push_notification_success` (happy path via mock)
  - `test_trigger_2fa_push_notification_includes_session_headers` (scnt + session_id forwarding)
  - `test_trigger_2fa_push_notification_api_failure_is_non_fatal` (ICloudPyAPIResponseException → False)
  - `test_trigger_2fa_push_notification_network_failure_is_non_fatal` (ConnectionError / Timeout / SSLError → False)
- Existing 213 tests still pass (only the pre-existing `test_storage` ordering
  issue remains, unrelated to this change).
- **Live-validated** against a real Apple ID with an iOS 26.x trusted device:
  push notification arrived, code accepted, Photos + Drive services reachable.

## Approach
Ported from icloud-photos-downloader/icloud_photos_downloader#1335. That fix
has been validated in the `boredazfcuk/docker-icloudpd` community since
2026-05-04 and is the known-working solution. This PR adapts the same
approach to icloudpy's smaller, simpler API surface.

## Notes
- Failure to trigger push is non-fatal (returns False). A code may still
  arrive via SMS or another path, and callers can fall through to the
  `validate_2fa_code` call regardless.
- The SMS-fallback piece of upstream PR #1335 (`pyicloud_ipd/sms.py` changes)
  is not ported here — icloudpy doesn't have an equivalent SMS parser. Its
  2SA flow uses `validate_verification_code` via `/listDevices`, which is a
  separate code path that hasn't been affected by the iOS 26.4 change.
```

**Submit command:**

```bash
gh pr create \
  --repo mandarons/icloudpy \
  --base main \
  --head epheterson:fix/ios-26.4-auth \
  --title "fix: trigger 2FA push notification on iOS 26.4+ (resolves the auth stall in mandarons/icloud-docker#426)" \
  --body-file <(curl -s https://raw.githubusercontent.com/epheterson/icloud-docker-overlay/main/nas-deploy/UPSTREAM-PRS.md | sed -n '/^## PR 1:/,/^## PR 2:/p' | sed -n '/^```markdown$/,/^```$/p' | sed '1d;$d')
```

(Or just open https://github.com/epheterson/icloudpy/pull/new/fix/ios-26.4-auth in a browser and paste the body manually — easier.)

---

## PR 2: `mandarons/icloudpy` ← `epheterson/icloudpy:feat/live-photos`

**Title:** `feat: surface Live Photo .mov pair via versions (enables fixing mandarons/icloud-docker#199)`

**Body:**

```markdown
## Summary
Live Photos are stored in CloudKit with both still-image fields
(`resOriginalRes`, `resJPEGMedRes`, …) AND live-video fields
(`resOriginalVidComplRes`, `resVidMedRes`, `resVidSmallRes`) on the same
master_record. Previous icloudpy versions detected "is this a video?" by
checking presence of `resVidSmallRes`, which is true for Live Photos too —
they were misclassified as videos and the still half was dropped.

This change:

1. Adds `ITEM_TYPES` dict mapping Apple UTIs (`public.heic`, `public.jpeg`,
   `com.apple.quicktime-movie`, RAW formats, …) to `"image"` / `"movie"`.
2. Adds `PhotoAsset.item_type` property reading `fields["itemType"]` with a
   filename-extension fallback for assets without the UTI.
3. Changes `versions` detection from the `resVidSmallRes` heuristic to
   `item_type` — correctly classifying Live Photos as images.
4. Extends `PHOTO_VERSION_LOOKUP` with three new keys —
   `live_video_original` / `live_video_medium` / `live_video_thumb` —
   mapping to `resOriginalVidCompl` / `resVidMed` / `resVidSmall`.
   These are silently absent for non-Live-Photo stills (the existing loop
   already filters on field presence), so plain photos are unaffected.

Backward compatibility: existing version keys (`original`, `medium`,
`thumb`, etc.) still work for all stills and videos. Callers that previously
could only access the still half of Live Photos now ALSO see the
`live_video_*` keys.

Closes #199 in `mandarons/icloud-docker` once that project wires up the new
versions key (companion PR submitted there).

## Approach
Ported from `icloud_photos_downloader`'s `pyicloud_ipd.services.photos`,
which has solved this for years.

## Tests
13 new tests in `tests/test_photos.py`:

- `TestItemTypeDetection` (8 tests): UTI lookup (HEIC, JPEG, MOV, RAW),
  extension fallback (HEIC ext / MOV ext), no-UTI-no-filename → None,
  unknown UTI with image extension → image.
- `TestLivePhotoVersions` (5 tests): Live Photo classified as image,
  exposes still version with correct URL, exposes all three `live_video_*`
  versions with correct URLs/types, plain still has no `live_video_*` keys,
  regular video uses `VIDEO_VERSION_LOOKUP`.

Full suite: 222 passed + 1 pre-existing unrelated `test_storage` failure.
```

---

## PR 3: `mandarons/icloud-docker` ← `epheterson/icloud-docker:feat/per-library-destinations-and-live-photos`

**Title:** `feat: per-library destinations + Live Photo .mov download (closes #199)`

**Body:**

```markdown
## Summary
Two related improvements that unlock running this container as a single
unified backup tool (Personal Photo Library + Shared Photo Library +
iCloud Drive, one Apple ID, one 2FA event) without losing data fidelity.

### 1. Per-library destinations (new optional config)

New optional config block `photos.library_destinations` maps each iCloud
library to a subdirectory of `photos.destination`:

```yaml
photos:
  destination: photos
  library_destinations:
    PrimarySync: personal
    SharedLibrary: shared
```

Personal photos then land in `<photos.destination>/personal/`, Shared
Library photos in `<photos.destination>/shared/`. When `library_destinations`
is unset (the default), all libraries share the single `photos.destination`
tree — preserving the historical mandarons/icloud-docker behaviour. Threaded
through `sync_photos.sync_photos`, `_sync_all_photos_first_for_hardlinks`,
and `_sync_albums_by_configuration`.

Obsolete-file cleanup is updated to walk each per-library subdir
independently when `library_destinations` is set, falling back to the legacy
single-destination walk otherwise.

### 2. Live Photo .mov pair auto-download (closes #199)

When a photo is a Live Photo and the user has requested the `original`
file_size, the orchestrator collects a second download task for the paired
`.mov`. Live Photos now round-trip intact (HEIC + paired MOV land
together in the destination) instead of dropping the video half.

Has no effect on plain stills (the `live_video_original` key is absent in
`photo.versions` for them) or when the user did not request "original".
Failure to read `photo.versions` is non-fatal — original-still tasks are
still emitted.

## Dependency

Requires `icloudpy` with the `live_video_*` keys in `PHOTO_VERSION_LOOKUP`
and the `item_type` property — submitted as a companion PR at
`mandarons/icloudpy` (link inline once filed). `requirements.txt` in this
PR pins the fork branch temporarily; will swap to the upstream tag once
that PR merges and a new icloudpy is released.

## Tests
15 new:

- `tests/test_library_destinations.py` (10 tests): config helper returns
  `{}` for missing config / non-dict values / coerces stringly,
  `_library_destination` helper returns base when no mapping / when library
  absent from mapping, joins + creates subdir, handles nested subdirs,
  `None` mapping is safe.
- `tests/test_live_photo_pair_download.py` (5 tests): Live Photo with
  original yields two tasks (still + .mov), still photo yields one,
  Live Photo without "original" request does not append .mov,
  `photo.versions` exception is non-fatal,
  `None` collect result for .mov is skipped.

Full suite: 430 passed (was 415), 20 pre-existing failures unchanged.

Closes #199.
```

---

## Cross-references to include in each PR

- PR 1 references: `mandarons/icloud-docker#426` (the user-facing issue) + `icloud-photos-downloader/icloud_photos_downloader#1335` (the source of the port)
- PR 2 references: `mandarons/icloud-docker#199`
- PR 3 references: PR 1 + PR 2 (the icloudpy dependencies) + `#199`

When PR 1 lands and a new icloudpy release ships, mandarons can bump
`requirements.txt` in this repo to that release and PR 3 is the only change
that needs maintainer attention.
