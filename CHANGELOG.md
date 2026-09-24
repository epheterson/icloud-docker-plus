# Changelog

Versions track this image, not upstream `mandarons/icloud-docker`. Entries note when a change has been sent upstream and where.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is [semantic](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [0.14.0] — 2026-09-24

Rebuilt from current upstream `main`, which now carries six more of this image's fixes: [#528](https://github.com/mandarons/icloud-docker/pull/528) log rotation, [#530](https://github.com/mandarons/icloud-docker/pull/530) trust refresh and revocation naming, [#531](https://github.com/mandarons/icloud-docker/pull/531) dashboard auth state and the re-auth wake, [#534](https://github.com/mandarons/icloud-docker/pull/534) per-library isolation, [#535](https://github.com/mandarons/icloud-docker/pull/535) the mass-delete limit, and [#540](https://github.com/mandarons/icloud-docker/pull/540) the CloudKit error-record fix. The seven still-open PRs are layered on top, then the plus-only work.

### Fixed

- **A security-key sign-in now resumes the sync straight away.** Upstream's re-auth wake covers the sign-in paths upstream has; the two security-key paths exist only here, so a successful key ceremony left the loop sleeping out its retry interval with the dashboard still reading "sync is stopped".
- **The unavailable-libraries panel no longer claims to know why a library is unreadable.** It shows each library's actual error, so a genuinely revoked share isn't collapsed and blamed on Apple's migrations.
- **Drive's legacy download path honours `drive.flatten_packages`.** Only the parallel path passed it through; from review on [#473](https://github.com/mandarons/icloud-docker/pull/473).
- **A malformed `app.logger.max_bytes` or `backup_count` falls back to the default** instead of raising out of module import into a restart loop.

### Changed

- **icloudpy is pinned to the merged [icloudpy#174](https://github.com/mandarons/icloudpy/pull/174) commit on `mandarons/icloudpy`**, replacing the pin to our fork's branch. Same security-key code, now from the official repo. It moves to the released version once one ships.

## [0.13.0] — 2026-09-22

### Added

- **Security-key sign-in actually works.** Once keys are enrolled Apple stops issuing six-digit codes and answers every 2FA endpoint with an `fsaChallenge`. The dashboard ceremony for that already existed here, but the image shipped `icloudpy==0.9.0`, which has no `security_key_challenge` or `confirm_security_key` — so the flow had nothing to call and such an account could not complete two-factor by any route: not the dashboard, not Telegram, not `docker exec`. icloudpy is pinned to the branch from [icloudpy#174](https://github.com/mandarons/icloudpy/pull/174) until it lands.
- **The sync loop says so when Apple wants a key, not a code.** It detects the challenge before anything is sent, records the method so the *first* notification carries the right wording rather than waiting for someone to open the dashboard, and skips the two steps that cannot succeed — requesting a push that sends nothing, and listening six hours for a code that cannot arrive while Telegram says "reply the 6-digit code here". Detection keys on the payload shape, not truthiness: a false positive would suppress the real code flow for an ordinary account.
- **Revocation is named separately from expiry.** Both surface as `421` and read identically in the logs, but a refresh schedule prevents one and can do nothing about the other. When the trust token has not expired, the log now says how long it had left and that Apple revoked it server-side — which typically follows a new trusted device, a password change, or a change to security keys.

### Fixed

- **A completed re-auth ends the retry wait.** Every auth-retry path blocked in a plain sleep, so finishing the ceremony left the dashboard reading "sync is stopped" for the remainder of an interval that began before the problem was solved — six hours on a typical install — while the container held a session that had just been fixed underneath it. All five web-UI auth-success paths now signal, and the wait ends within seconds. The signal is deliberately **not** the one behind "Sync now": that button means "sync everything now", and borrowing it both queued a photo re-enumeration nobody asked for and let a dashboard tap collapse the anti-throttle backoff that exists because Apple answers a rate-limited account with 409 — turning a stalled page into a way to extend the lockout.
- **The dashboard no longer scrolls sideways on a phone.** The library grid used a bare `1fr`, which is `minmax(auto, 1fr)`; that `auto` floor resolves to min-content, and library names are `white-space: nowrap`, so min-content was the entire zone-name string. The track outgrew the viewport and the ellipsis never fired because its container widened instead of constraining.

### Changed

- **Libraries Apple created and never serves are set aside.** Apple attaches zones during its own backend migrations and then errors on every query about them; four sitting permanently red trains the eye to skip the state column, which is exactly when a real failure goes unnoticed. They collapse behind an "N unavailable (Apple)" disclosure, with each library's actual error shown. Only libraries that are failing now, have **never** completed a sync, and fail with an unreadable-zone error qualify — anything that ever synced, or fails for another reason, stays visible.

## [0.11.2] — 2026-09-11

### Fixed

- **An expired download URL no longer fails with an unexplained `'fields'`.** A failed CloudKit `records/lookup` is not an HTTP error: CloudKit returns it inside the `records` array as an entry carrying the *requested* `recordName` and a `serverErrorCode` in place of usable `fields`. The 410 URL refresh matched its record on `recordName` alone, so it assigned that error payload to the photo's master record and reported success — and the retrying download then raised `KeyError('fields')` deep inside icloudpy, surfacing as `Failed to download <path>: 'fields'`. Because the failure was charged to the download rather than the refresh, the refresh-failure counter never moved and the warning that exists precisely to report a broken refresh path never fired. Measured on this install: over 60 hours, 335 assets hit a 410 refresh and 289 then failed this way, with not one such failure occurring without a preceding refresh and not one refresh-failure warning logged. A record carrying a `serverErrorCode`, or whose `fields` are absent or empty, is now rejected and the existing master record left intact. This does not make an unavailable asset downloadable — it replaces a misleading `KeyError` with an accurate 410. Sent upstream as [#540](https://github.com/mandarons/icloud-docker/pull/540).

### Changed

- **The image is built from source by CI instead of by hand on the NAS.** Every version from 0.10.1 to 0.11.1 was an overlay build — `FROM` the last published image plus a `COPY` of individual source files — produced on the NAS and never pushed, so the running image existed on a single disk and could not be rebuilt from any git ref. GitHub Actions now tests the merged `plus/live` tree and builds its own root Dockerfile, publishing to GHCR. The overlay is retired.

## [0.10.2] — 2026-08-24

### Fixed

- **One unreadable photo library no longer stops the others.** An account can be shown libraries it never created — zones left behind by Apple's own backend migrations — and some answer every query with `ZONE_NOT_FOUND` or `BAD_REQUEST`. The library loop had no error handling, so one of those aborted the entire photos pass and every library after it in the list simply never synced — silently, for weeks, while the libraries processed earlier kept working. Each library is now isolated: the fault is logged, the library recorded, and the sync continues.
- **Obsolete-file cleanup can no longer delete a library it could not read.** Cleanup deletes any local file absent from the set of files seen during the run, and a library that failed contributes nothing to that set — so continuing past a failure would read as "the server has none of these" and delete every local copy. Failed libraries are now excluded from cleanup, and when a single shared destination is configured, one failure disables cleanup entirely, because the file set cannot attribute a path to a library.
- **Obsolete-file cleanup never runs against the shared photos root.** A library with no `library_destinations` entry falls through to the base destination by design, so per-library cleanup then walked the photos root — which holds every other library's tree, and anything else kept there. One unmapped library would have deleted all of them. Reached by doing nothing wrong, since Apple adds libraries to an account on its own and a mapping that was complete when written silently stops being complete.

## [0.10.1] — 2026-08-24

### Fixed

- **A service outage no longer masquerades as a sign-in failure.** The sync loop wraps authentication and the whole sync in one `try`, so any error raised during a download was reported as a sign-in failure and earned the rate-limit backoff — a shared library returning `ZONE_NOT_FOUND` told the user to re-authenticate an account that was signed in perfectly well. Failures are now routed on whether sign-in actually succeeded. Sent upstream as [#529](https://github.com/mandarons/icloud-docker/pull/529).
- **A failed sync no longer re-enumerates the whole library every few minutes.** Every retry handler ends in `continue`, which skips the scheduler, so the countdown timers never advanced and both services stayed enabled — the short login-retry interval therefore repeated a full library walk. A post-sign-in failure now waits at least as long as the shortest configured sync interval: never poll a broken service faster than a working one. Sent upstream as [#529](https://github.com/mandarons/icloud-docker/pull/529).
- **An unreadable `config.yaml` no longer becomes a restart loop.** `read_config` returns `None` when the file is missing, and a partial file may have no `app` section; both reached `config["app"]` unguarded — once from `get_logger()` at module scope, so the container died on import with a bare `TypeError` and never reported the real problem, and once from the sync loop's oneshot check. With `restart: unless-stopped` either one restarts forever. Reachable on any NAS boot where the volume holding the config lags behind the container. Logging now falls back to defaults and the loop waits for the file.

### Changed

- The security-key sign-in starts from the button on `/auth` instead of routing through an interstitial page. It remains a `POST`, so a bookmark or a link prefetch still cannot spend an Apple sign-in attempt.
- Removed a stale "Unvalidated" notice that claimed no assertion had ever been accepted by Apple and pointed at a trust-token option that no longer exists.

## [0.10.0] — 2026-08-21

### Added

- **Sign in with a hardware security key.** Apple stops offering a 6-digit code once security keys are enrolled and returns a WebAuthn challenge instead, so the headless paths waited for something that never arrived — such an account could not authenticate at all. The dashboard now issues a challenge, the operator signs it with the key on whichever machine holds it, and pastes the assertion back. One touch, no PIN. Sent upstream as [icloudpy#174](https://github.com/mandarons/icloudpy/pull/174) (the protocol) and held pending its release (the ceremony).
- **Proactive trust refresh** (`app.trust_refresh_days`, default 14). `trust_session` mints a fresh trust token whenever called on a live session, so refreshing on a schedule keeps the on-disk copy young and a container restart resumes without a second factor. Sent upstream as [#530](https://github.com/mandarons/icloud-docker/pull/530).
- **Log rotation** (`app.logger.max_bytes`, `app.logger.backup_count`). A line is written per file *considered* each cycle, so the log grew without bound — 5.8 GB on a ~294k-photo library. Sent upstream as [#528](https://github.com/mandarons/icloud-docker/pull/528).

### Fixed

- **Sign-in failures no longer exit the process.** Only the missing-password exception was caught, so any other failure escaped and, under `restart: unless-stopped`, became a loop re-authenticating every few seconds — against an account Apple was already rate-limiting. Now caught and backed off, with a 30-minute floor. Sent upstream as [#529](https://github.com/mandarons/icloud-docker/pull/529).
- **The dashboard no longer reports a healthy account while sync is stuck.** Auth state was derived from on-disk signals alone, which look correct whether or not Apple is demanding a factor. Sent upstream as [#531](https://github.com/mandarons/icloud-docker/pull/531).
- **Mobile: words no longer break mid-character.** `word-break: break-all` split every word rather than only those that cannot fit. Included in [#531](https://github.com/mandarons/icloud-docker/pull/531).

### Known limitations

- The image is still an overlay build layered on `0.9.2` rather than a clean build from a merged source tree. Four of the six branches it carries conflict against current upstream `main`. See [`build/README.md`](build/README.md).

## [0.9.2] — 2026-07-12

Last release before the changelog was kept. See the version table in [`README.md`](README.md) for what the image carries.
