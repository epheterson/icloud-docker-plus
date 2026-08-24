# Changelog

Versions track this image, not upstream `mandarons/icloud-docker`. Entries note when a change has been sent upstream and where.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is [semantic](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

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
