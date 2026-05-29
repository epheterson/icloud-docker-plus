# PR 12: Streaming photo enumeration — bound memory by chunk size, not library size

**Target:** `mandarons/icloud-docker` `main` (separate from PRs 1–11)
**Branch:** `perf/streaming-photo-enumeration`
**Status:** Plan — implementation deferred until PR 11 lands

## Problem

mandarons' Photos sync OOM-kills on large libraries because
`album_sync_orchestrator._collect_album_download_tasks()` materializes
the full per-photo download-task list in memory before passing any of
it to `execute_parallel_downloads`:

```python
def _collect_album_download_tasks(album, ...):
    download_tasks = []
    for photo in album:
        download_tasks.extend(_collect_photo_download_tasks(photo, ...))
    return download_tasks
```

For Eric's 111K-photo iCloud library this peaks at ~4 GB RSS during
enumeration (kernel-confirmed via cgroup OOM at the 4 GB cap:
`total-vm:4270872kB anon-rss:4181524kB`). Memory rises monotonically
through enumeration and stays high through parallel download — the
download tasks reference photo objects that hold per-asset metadata
(filenames, URLs, version dicts) until the whole album is done.

**Empirical evidence (tonight, 2026-05-28):**
- 1 GB cap → OOM at the ~30-second mark
- 4 GB cap → OOM at the ~30-minute mark (mid-enumeration)
- 8 GB cap → completes (currently in flight as of plan write time)

## Root cause

The album orchestrator treats enumeration and download as two sequential
phases instead of a streaming pipeline. The "build the full list, then
download" pattern made sense when libraries were small. It doesn't scale
past ~50K photos without proportional RAM.

## Fix shape

Convert `_collect_album_download_tasks` from "build complete list" to
"buffer-and-drain in fixed-size chunks." Memory bounded by chunk size,
not library size.

```python
def _collect_and_execute_album_in_chunks(
    album, destination_path, file_sizes, extensions, files,
    folder_format, hardlink_registry, config,
    chunk_size: int = 1000,
) -> tuple[int, int]:
    """Stream album → chunked download → release. Memory bounded
    by chunk_size, not by len(album)."""
    buffer: list[DownloadTaskInfo] = []
    total_succ, total_fail = 0, 0
    for photo in album:
        buffer.extend(_collect_photo_download_tasks(
            photo, destination_path, file_sizes, extensions,
            files, folder_format, hardlink_registry,
        ))
        if len(buffer) >= chunk_size:
            s, f = execute_parallel_downloads(buffer, config)
            total_succ += s
            total_fail += f
            buffer.clear()
    if buffer:
        s, f = execute_parallel_downloads(buffer, config)
        total_succ += s
        total_fail += f
    return total_succ, total_fail
```

`sync_album` then calls the new function instead of doing
`collect_album_download_tasks → execute_parallel_downloads` as two
separate steps.

Memory math:
- chunk_size=1000, per-DownloadTaskInfo ≈ 8–12 KB → ~10 MB resident
- Album-of-1000 enumeration: ~3 MB icloudpy Photo objects + 10 MB tasks ≈ ~15 MB peak
- vs current: 111K × 12 KB = ~1.3 GB tasks alone, plus icloudpy's photo-asset cache

## Concrete changes

1. **`src/album_sync_orchestrator.py`**
   - New `_collect_and_execute_album_in_chunks()` per shape above.
   - `sync_album()` calls the new function instead of the
     two-step `_collect_album_download_tasks` + `execute_parallel_downloads`.
   - Keep `_collect_album_download_tasks` as a thin wrapper for legacy
     test compatibility (or delete if it has no external callers).
   - Add `chunk_size` config knob: `photos.enumeration_chunk_size`
     (default 1000). Lets sysadmins tune for memory vs. throughput.

2. **`src/config_parser.py`**
   - `get_photos_enumeration_chunk_size(config)` with sane default (1000).

3. **`src/sync_photos.py`**
   - Pass chunk size down to orchestrator.

4. **Tests** (`tests/test_album_sync_orchestrator.py`):
   - **Chunking matches non-chunked semantics** — same total counts and
     same files-touched set whether chunk_size=1, 100, or len(album).
   - **Memory bounded** — use `tracemalloc` to verify peak allocation
     stays under `(chunk_size × 50 KB) + base_overhead` regardless of
     album size. Fake album with 10K photo mocks, snapshot peak.
   - **Chunk boundary errors** — failed photo in middle of chunk doesn't
     abort the remainder; failed chunk doesn't abort subsequent chunks.
   - **Aggregation** — total_successful/total_failed match per-chunk sum.

5. **Docs** (`README.md` in mandarons upstream; mirror in
   icloud-docker-plus):
   - Document the new `photos.enumeration_chunk_size` knob.
   - Update memory-sizing guidance: streaming reduces baseline by ~10×
     for large libraries.

## Validation plan

**Locally before push:**
1. Run existing test suite — all passes, no regressions.
2. Run new tests — chunking equivalence + memory bounds.
3. Local Docker build, run against a synthetic 10K-photo mock album,
   profile RSS with `docker stats` — should stay under 500 MB.

**On Eric's NAS after merge:**
1. Bump `mem_limit` back DOWN to 2 GB.
2. Restart container.
3. Watch first Photos sync — should complete without OOM (was killed at
   1 GB and 4 GB, would have needed 8 GB without this PR).
4. If it completes under 2 GB → PR validated, document the new minimum.
5. If still pressures memory → tune chunk_size down to 500 and retry.

## Why separate from PR 11

PR 11 (drive_package_processing fix) is a correctness fix — wrong code
path treats non-archive-bytes as a download failure. PR 12 is a
performance fix — right code path, wrong memory profile. Different
reviewers care about different aspects; cleaner to land independently.

Also: PR 12 is the bigger refactor of the two and more likely to need
discussion with Mandar about chunk-size defaults and whether to expose
the knob. Better to debate that in isolation.

## Risks

- **Chunked downloads change the log shape.** Users will see N×
  `Parallel downloads completed: X successful, Y failed` lines instead
  of one. Document this in the PR description; consider a per-album
  summary line at the end.
- **Failure aggregation semantics change subtly.** Today, a single
  enormous parallel-download call returns total counts. Chunked version
  sums per-chunk counts. Edge cases (partial album failures, retries)
  need to align with what the sync_summary notifications expect.
- **Throughput could drop slightly.** Fewer parallel-download
  opportunities within a chunk vs. across the whole album. In practice
  iCloud's per-account concurrency limit is the bottleneck anyway, but
  worth measuring on a real library.

## Out of scope

- **Streaming the photo-object cache inside icloudpy.** That's the
  deeper problem (icloudpy caches photo asset metadata as it iterates).
  This PR works around it at the mandarons layer; an icloudpy-side fix
  would be more thorough but is a separate, larger change.
- **Memory limits as adaptive (auto-tune chunk_size).** Static chunk
  size is fine for v1; adaptive can come later if needed.
- **Live Photos pairing across chunk boundaries.** Already handled by
  the per-photo task collector — a Live Photo's HEIC and MOV land in
  the same chunk as a unit because they're both produced by
  `_collect_photo_download_tasks`.

## Out of scope (also)

Touching the Drive sync path. Drive sync is already memory-light
(linear folder walk, no all-in-RAM enumeration). The OOM is purely on
the Photos side.
