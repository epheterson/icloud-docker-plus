# Headless re-auth for a security-key Apple account

**Goal:** restore syncing on an Apple account where security keys are enrolled, and make every future expiry a two-minute job instead of an outage.

## What is actually broken

Once security keys are enrolled, Apple stops issuing six-digit codes and returns an `fsaChallenge` (a WebAuthn assertion request) from every 2FA endpoint. Stock icloudpy has nothing to do with that challenge, so the account cannot complete two-factor at all. The container has been requesting a push every ~6.7 hours since 2026-09-20 17:46 and telling the user over Telegram to "reply the 6-digit code here" — a code Apple will never send. Nothing has synced since 2026-09-20 05:45.

## What will not work, and why

**Signing the challenge from the dashboard is impossible.** Apple's challenge carries `rpId: apple.com`. WebAuthn assertions are origin-bound by design: a browser on `icloud.zosia.io` will not sign for `apple.com`, and that restriction is the whole security property. No UI work changes this.

**The container cannot sign either.** `confirm_security_key()` needs an attached FIDO2 device and a physical touch. The NAS has no key and never will.

## What works

icloudpy [#174](https://github.com/mandarons/icloudpy/pull/174) (ours) adds the missing surface. `confirm_security_key()` signs the challenge with an attached key and then calls `trust_session()`, which yields a **trust token**. That token is what the container actually needs — with it, icloudpy authenticates without any second factor until it expires.

So: complete the key ceremony once on the machine that has the key, then move the trusted session to the NAS.

Two artifacts per account, both required:

- `session_data/<user>.session` — JSON: `client_id`, `session_id`, `scnt`, `session_token`, `trust_token`, `account_country`
- `session_data/<user>` — the cookiejar

## Steps

1. `nas-deploy/reauth-security-key.sh` — runs on the Mac with the key attached. Isolated venv, icloudpy from `feat/security-key` plus `fido2`, password read via `getpass` (never argv, never disk, never logged). Authenticates, detects the challenge, waits for the touch, confirms, verifies the session is trusted, then installs both artifacts on the NAS (backing up what is there) and restarts the container.
2. Pin icloudpy to `feat/security-key` on `plus/live` so the container can *recognise* an `fsaChallenge`.
3. Stop lying in the notification. When the challenge is an `fsaChallenge`, say the account needs the key ceremony and name the tool — instead of promising a code that cannot arrive.
4. Fix the dashboard grid blowout: `grid-template-columns: 1fr` is `minmax(auto, 1fr)`, whose `auto` floor is min-content; with `white-space: nowrap` library names, min-content is the full ID string, so the track outgrows the viewport and the ellipsis never fires. Use `minmax(0, 1fr)`.
5. Rebuild and publish through CI, deploy, verify a clean pass.

## Completion criteria

- The container authenticates with no second factor and completes a full sync
- Re-running the tool at the next expiry is one command plus one touch
- The notification tells the truth for this account type
- The dashboard does not scroll sideways on a phone

## Risks

- The trust token is minted against the Mac's session and `client_id`. Both move with the artifacts, so it should carry; if Apple rejects it on the NAS the container will say so immediately on the first attempt.
- `fido2` needs the key attached and a touch. Nothing about this can be automated, by design — that is the point of the key.
