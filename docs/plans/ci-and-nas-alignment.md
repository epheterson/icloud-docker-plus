# CI + NAS alignment

**Goal:** the NAS always runs the latest published release, and that release is reproducible by CI rather than by hand on the NAS.

## Why

`docker ps` says the NAS runs `0.11.1`. GHCR's newest tag is `0.10.0`. Everything from `0.10.1` through `0.11.1` was built by hand on the NAS as an **overlay** (`FROM ghcr.io/epheterson/icloud-docker-plus:0.9.2` + `COPY` of individual source files) and never pushed. The running image therefore exists on exactly one disk and cannot be rebuilt from anything but that disk.

The overlay existed because four open branches conflicted against upstream `main`. That ended 2026-08-31 — every open PR merges clean and `plus/live` is a real merged tree, level with upstream, suite green at 100%.

## Policy

The NAS runs the latest **published** release. Running ahead of public is only for testing something before it ships; once it ships, the NAS goes back to the published tag. No more hand-built images that exist nowhere else.

## Steps

1. `test-plus-live.yml` — check out `epheterson/icloud-docker@plus/live`, run `ruff check` + full pytest at the 100% coverage gate. On push/PR to the plus repo, weekly, and manual.
2. `build-publish.yml` — check out `plus/live`, build its **root** Dockerfile (a real source build, not the overlay), push `ghcr.io/epheterson/icloud-docker-plus:<version>` and `:latest`. Manual with a version input; gated on the test job passing.
3. Publish `0.11.2` = upstream main + all open PR branches + #540.
4. Pin `nas-deploy/docker-compose.yml` to `0.11.2` (the repo copy currently says `:latest` while the NAS says `0.11.1` — both wrong).
5. Deploy: pull + recreate on the NAS, verify version, restarts, and a clean pass.
6. Retire `build/Dockerfile` (the overlay) and update `build/README.md` + `CHANGELOG.md`.

## Completion criteria

- GHCR `latest` == the tag the NAS runs == a CI-built image from `plus/live`
- The overlay Dockerfile is gone
- A rebuild needs no NAS access
- `'fields'` errors stop appearing (that is #540 shipping)

## Risk

Switching from overlay to source build changes how the artifact is composed. The Dockerfile is upstream's own and the suite is green on `plus/live`, but the first source-built image should be verified running before `latest` is moved.
