# Building the plus image

The published image is `ghcr.io/epheterson/icloud-docker-plus`. It is **not** a plain build of `epheterson/icloud-docker` — it is upstream `main` plus the feature branches that are still open as PRs against `mandarons/icloud-docker`.

## Current state (2026-08-19)

`0.9.4` is an **overlay** build: it layers the verified-live source files onto `0.9.2` rather than rebuilding from a merged tree. This exists because four of the six still-open branches conflict against the current upstream `main`, and that integration was not worth rushing onto a live system:

| Branch | PR | Merges onto `upstream/main` |
| --- | --- | --- |
| `fix/drive-bundle-redownload-loop` | #473 | clean |
| `feat/photos-filename-format-simple` | #457 | clean |
| `fix/2fa-trigger-push` | #486 | conflict — `src/sync.py` |
| `fix/drive-package-single-file-bundles` | #461 | conflict — `src/drive_package_processing.py`, `src/drive_parallel_download.py`, tests |
| `feat/photos-preserve-originals-as-bak` | #458 | conflict — `src/config_parser.py`, `src/photo_path_utils.py` |
| `feat/telegram-2fa-clean` | #470 | conflict — `README.md`, `src/notify.py`, `src/sync.py` |

Note `feat/web-ui` (#464) is **merged upstream**, so the web UI now comes from `main` and no longer needs merging in.

## Rebuild (as done for 0.9.3)

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

Replace this with a source build once the six branches are integrated: resolve the four conflicts on a `plus/live` branch cut from `upstream/main`, run the suite, then build from that tree. A GitHub Actions workflow doing exactly that is the end state, so the image stops depending on someone remembering to build it by hand.
