# PR 11: Treat unhandled-mime "packages" as single-file downloads (stop re-downloading iWork/JMG files)

**Target:** `mandarons/icloud-docker` `main` (NOT stacked on existing 10 PRs)
**Branch:** `feat/single-file-package`
**Status:** Plan — implementation pending

## Problem

iCloud Drive serves "package files" — Finder bundle types like `.key`, `.pages`, `.numbers`, `.band`, `.app`, third-party `.jmb`, etc. — via `/packageDownload?` URLs. mandarons downloads the bytes, then calls `process_package()` to detect the archive type via libmagic and unpack it so the local copy mirrors iCloud's "bundle = directory tree" structure.

`process_package()` only handles `application/zip` and `application/gzip`. Apple's iWork formats and many third-party bundles report `application/octet-stream` — `process_package()` logs `Unhandled file type` and returns `False`. The caller in `drive_file_download.py` treats `False` as a download failure and returns `None` — which means the next sync run sees the path as "not done" and **re-downloads the file every time**.

The bytes ARE on disk (`os.path.getsize()` confirms the full file landed at the target path), so it's not data loss. But:

1. **Wasted bandwidth on every sync run** — Eric's iCloud Drive has ~40 `.jmb` files (8–50 MB each) and a few `.key` files (~100 MB each). Every container restart re-downloads ~300+ MB.
2. **Misleading `0 successful, N failed` log lines** make it look like the sync is broken.
3. **Bookkeeper drift** — mandarons' internal "what's done" state never marks these files as done, so they're always at the head of the next sync's queue.

## Root cause

`process_package()` is opportunistic *post-download transformation*, but the caller treats it as a required step. The original intent (2022 commit `62ac0c32c`, "Fix for re-downloading of package files") used a GarageBand `.band` file: it IS a directory bundle, gzipped over the wire, and unpacked → directory tree on disk → next-sync compares directory contents against iCloud and skips correctly.

The implicit contract: **"local representation must be the unpacked directory tree."** That contract breaks for non-zip/gzip bundles, because libmagic can't tell us how to unpack them — and we have no fallback comparator for the single-file form.

## Fix shape

Add a third branch to `process_package()` + a matching dedup comparator:

```
download bytes → libmagic detect
  ├─ application/zip  → unpack (existing behaviour)
  ├─ application/gzip → ungzip + recurse (existing behaviour)
  └─ unknown          → SAVE AS-IS, mark in metadata as "single-file package"
                        next-sync dedup uses size+mtime comparator
                        log as INFO ("kept as single-file"), not ERROR
```

Concrete changes:

1. **`src/drive_package_processing.py`** — `process_package()` returns a tri-state instead of bool:
   - `"unpacked"` → unpacked directory tree, existing dedup-by-tree applies
   - `"single_file"` → saved as flat file, dedup-by-size-mtime applies
   - `"error"` → genuine failure (couldn't write disk, corrupt download)
   
   Log level for `single_file` drops from ERROR to INFO. Wording: `"Package format not recognized for unpacking; kept as single file: {path}"`.

2. **`src/drive_file_download.py`** — caller branches on the tri-state instead of treating non-True as failure:
   ```python
   result = process_package(local_file=local_file)
   if result == "error":
       return None
   # Both "unpacked" and "single_file" are success states for the download.
   ```

3. **`src/drive_file_existence.py`** — `file_exists()` for items where the local path is a regular file AND the iCloud item is a package AND remote-vs-local size matches → treat as up-to-date.
   
   Need to verify: does iCloud's package response include a `size` field for the flat archive? If yes, this works directly. If no, fall back to mtime comparison against `lastModified` — also works.

4. **Tests** — add `tests/data/SinglefilePackage.foo` (a non-zip non-gzip binary) and verify:
   - First sync writes it to disk, no error log.
   - Second sync skips it (matching size, no re-download).
   - Existing zip/gzip package tests still pass.

## Why not stacked on the existing 10 PRs

This is a fix for a pre-existing mandarons bug, not part of the boredazfcuk-migration / web-UI / etc. feature work. Keeping it isolated:
- Easier review for Mandar (one focused change vs. interaction with 10 other diffs).
- If Mandar disagrees with the dedup-by-size-mtime approach, the rejection doesn't entangle the other PRs.
- We can land it independently of the 10.

## Validation plan (local)

1. Stop icloud container.
2. Clear the local `.jmb` and `.key` files from the Drive mount (so the bug-reproduction sequence is clean).
3. Build patched image, deploy, start container.
4. Verify Drive sync downloads each `.jmb`/`.key`, logs `"kept as single file"` at INFO, no `"0 successful, N failed"`.
5. Restart container.
6. Verify second sync run skips the same files (`No changes detected` per file, no re-download).

## Verification of "no data loss"

Before merging or deploying:
- File-count + total-bytes match for the Drive mount BEFORE and AFTER the patch (using `ls | wc -l` and `df -h`, NOT `find` or `du`).
- The boredazfcuk-era extracted JMB directories at `/volume1/@appdata/.../Archive/` remain untouched (read-only reference copies).

## Out of scope

- Removing the unpack step entirely (would re-introduce the original 2022 re-download bug for `.band` files and other genuine zipped bundles).
- Re-packing single-file bundles into directories on Linux (pointless — bundle semantics are OS-level, not filesystem-level).
- Adding an allowlist of known iWork extensions (libmagic-based detection is more general and doesn't drift as Apple adds formats).
