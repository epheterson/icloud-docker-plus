# Changelog

Versions track this image, not upstream `mandarons/icloud-docker`. Entries note when a change has been sent upstream and where.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning is [semantic](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

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
