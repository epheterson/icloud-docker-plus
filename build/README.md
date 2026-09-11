# Building the plus image

The published image is `ghcr.io/epheterson/icloud-docker-plus`. It is **not** a plain build of `epheterson/icloud-docker` — it is upstream `main` plus the feature branches that are still open as PRs against `mandarons/icloud-docker`.

## Current state (2026-09-11)

The integration branch is **`plus/live`** on `epheterson/icloud-docker`. It is cut from `upstream/main`, carries every open PR branch, and is currently level with upstream (0 commits behind). Suite green at 100% coverage, `ruff check` clean.

**Every open PR now merges cleanly against `upstream/main`.** The four conflicts that forced the `0.10.0` overlay build were resolved on 2026-08-31, so the overlay approach is retired — `plus/live` is a real merged tree and the image should be built from it.

| Running on the NAS | `0.11.1` |
| --- | --- |
| `plus/live` vs that image | ahead — adds [#540](https://github.com/mandarons/icloud-docker/pull/540) and the upstream ruff bumps |

So a rebuild is pending if you want #540 (the CloudKit error-record fix for unexplained `'fields'` download failures) running live. Nothing else is outstanding.

## Rebuild

Run on the NAS — it has docker but no buildx, and the NAS is the only amd64 host:

```sh
cd /volume1/docker/icloud/build
docker build -t ghcr.io/epheterson/icloud-docker-plus:<version> \
             -t ghcr.io/epheterson/icloud-docker-plus:latest .
docker push ghcr.io/epheterson/icloud-docker-plus:<version>
docker push ghcr.io/epheterson/icloud-docker-plus:latest
```

Then pin `docker-compose.yml` to the new version and `docker compose up -d --force-recreate`.

## Next

The build is still manual. The end state is a GitHub Actions workflow that builds from `plus/live` on push, so the image stops depending on someone remembering to build it by hand. There is no workflow in this repo yet.
