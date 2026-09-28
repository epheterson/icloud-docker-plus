# Upstreaming what is still plus-only

Status 2026-09-27: every icloud-docker PR behind this image is merged (#457, #461, #470, #473 today). What remains in `plus/live` beyond `upstream/main` is about 2 500 lines in two unrelated features, plus build glue. The goal is to retire this image, so both go upstream as separate PRs.

## Step 0 — ask for icloudpy 0.10.0 (blocks PR A only)

Security-key sign-in needs icloudpy#174 (merged 2026-09-24) and benefits from #186 (merged 2026-09-27). PyPI is still 0.9.0 from May. Upstream will not merge a git-commit pin, so PR A cannot land until a release exists. Ask now while the maintainer is active; see the draft below.

## PR B — per-library dashboard state and unavailable libraries (no dependency, open first)

- `web_signals`: `record_library_started` / `record_library_finished` / `get_library_states` / `clear_stale_library_states`
- `sync_photos._signal_library` hooks
- `web._build_libraries`, `_is_permanently_unavailable` (`BAD_REQUEST`, `ZONE_NOT_FOUND`): libraries Apple created but never serves are set aside, not shown as failed
- `dashboard.html` / `base.html`: one row per library, grid minmax fix
- the "stop reporting a healthy account while sync is stuck" fix
- tests from `test_web.py`, `test_web_signals.py`, `test_sync_photos.py`

Small, visual, and builds on #464 and #534, which he already merged. A good warm-up before the big one.

## PR A — sign in with a hardware security key (after icloudpy 0.10.0)

- `web.py`: `/auth/security-key` GET/POST and `/start`, challenge packing, ceremony cookie dir, throttle detection, `_session_authenticates`, the wake-on-success paths
- `src/icloud_sign.py`: the PEP 723 signer (prints what it signs before asking for a touch)
- `auth.html`: the key-first page, the one-line command, the offline fallback, the WebAuthn-redirection note (Microsoft RDP/AVD, Citrix)
- `sync.py`: `_detect_security_key_account`; skip the 2FA push, the Telegram wait and the reply prompt for such accounts
- `notify.py`: the security-key wording
- `web_signals`: `record_auth_method` / `get_auth_method`
- `requirements.txt`: `icloudpy==0.10.0`, replacing the commit pin
- tests: `test_security_key.py` (868 lines) and the related cases in `test_sync.py`, `test_trust_expiry.py`
- closes icloud-docker's side of icloudpy#21

**Upstream change to the signer URL.** Plus pins the one-liner to `epheterson/icloud-docker@<PLUS_SOURCE_SHA>`, which needs a build arg that upstream's CI does not pass. Upstream builds releases from `v*` tags and already passes `APP_VERSION`, so upstream uses `https://raw.githubusercontent.com/mandarons/icloud-docker/v${APP_VERSION}/src/icloud_sign.py`. That means no workflow change. Builds that are not releases (`dev`, `pr-N`) show only the offline command. Tradeoff: a tag can be moved, a SHA cannot. That's acceptable for the maintainer's own repo, and the page still links the exact file to read first. Plus keeps the SHA.

Size: large (~2 000 lines, over half of it tests). He merged #464 (the whole web UI) at a similar size, so one PR is fine. If he asks, split it into backend (routes, detection, signer) and page.

## Order

1. Post the icloudpy release request (Eric approves the text).
2. Cut `feat/dashboard-library-state` from `upstream/main`, carry PR B, suite at 100%, open the PR (Eric approves the description).
3. Cut `feat/security-key-signin`, carry PR A with the tag-based URL, suite at 100%, keep the commit pin until the release, open it as a draft that references the release request.
4. When icloudpy 0.10.0 ships: swap the pin for the release in PR A and in plus, mark the PR ready, rebuild plus.
5. When both merge and upstream releases: README says switch back; archive this repo.
