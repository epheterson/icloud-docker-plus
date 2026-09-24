# Building the plus image

The published image is `ghcr.io/epheterson/icloud-docker-plus`. It is **not** a plain build of `epheterson/icloud-docker` — it is upstream `main` plus the feature branches that are still open as PRs against `mandarons/icloud-docker`.

## Current state (2026-09-24)

The integration branch is **`plus/live`** on `epheterson/icloud-docker`. It is cut from `upstream/main`, carries every open PR branch, and is currently level with upstream (0 commits behind). Suite green at 100% coverage, `ruff check` clean.

**Every open PR now merges cleanly against `upstream/main`.** The four conflicts that forced the `0.10.0` overlay build were resolved on 2026-08-31, so the overlay approach is retired — `plus/live` is a real merged tree and the image should be built from it.

| Running on the NAS | `0.14.0` |
| --- | --- |
| GHCR `latest` | `0.14.0` — same digest |
| `plus/live` vs that image | level |

Nothing is outstanding. icloudpy is pinned by SHA to the merge commit of [icloudpy#174](https://github.com/mandarons/icloudpy/pull/174) on `mandarons/icloudpy` (security-key sign-in; merged, not yet released). Swap for the released version when it ships.

**Keeping it current is standing policy:** whenever upstream `main` moves or an open PR branch changes, rebuild `plus/live` from `upstream/main` + the open PR branches + the plus-only commits, publish, promote, and deploy.

## Rebuild

**Do not build on the NAS.** Publish from CI:

```sh
gh workflow run build-publish.yml --repo epheterson/icloud-docker-plus \
   -f version=<version> -f move_latest=true
```

It tests the merged `plus/live` tree, then builds that tree's own root Dockerfile and pushes to GHCR. Use `move_latest=false` when the change affects how the artifact is composed — verify the NAS runs the pinned version first, then publish again with `move_latest=true`.

Then pin the NAS `docker-compose.yml` to the new version and `docker compose up -d --force-recreate`. The repo's `nas-deploy/docker-compose.yml` stays on `:latest` because it is a public template; the NAS gets an explicit pin so what is running is auditable.

## One-time GHCR setup

The `icloud-docker-plus` package was originally created by pushes from the NAS using a PAT, so it is **not linked to any repository** — and a workflow's `GITHUB_TOKEN` can only write to packages linked to its own repo. Until that link exists the build succeeds and the push fails with `denied: permission_denied: write_package`.

There is no REST API for this. Grant it once at
<https://github.com/users/epheterson/packages/container/icloud-docker-plus/settings>
→ **Manage Actions access** → **Add repository** → `icloud-docker-plus` → role **Write**.

Images now carry `org.opencontainers.image.source` pointing at the publishing repo, so the link stays put once established.
