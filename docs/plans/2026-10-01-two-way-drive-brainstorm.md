# Two-way iCloud Drive sync — brainstorm in progress

Status 2026-10-01: brainstorming (architectural path), paused overnight on one open question. No spec yet, no code. Target: upstream `mandarons/icloud-docker` (answers issue #79, open since 2022 with steady demand: backups into iCloud, local edits landing in iCloud).

## What icloudpy 0.10.0 offers

Drive writes already exist: `send_file` / `node.upload`, `create_folders` / `mkdir`, `rename_items`, `move_items_to_trash` (lands in iCloud's Recently Deleted, recoverable for 30 days).

## Decided

1. **Three opt-in modes, ideally per folder:** `download` (today's behaviour, the default), `push` (local → iCloud only; never deletes or overwrites in iCloud), `mirror` (both directions).
2. **Deletes go to a recycle bin wherever possible.** A NAS delete in mirror mode moves the iCloud item to Recently Deleted.
3. **One shared local recycle bin** (`.deleted/`, one retention setting) used by both Drive mirror and Photos obsolete cleanup. Photos cleanup today deletes outright the moment iCloud drops a photo, so the NAS never outlives iCloud's own 30-day window; the bin fixes that. Can ship on its own first.
4. **Conflicts keep both:** iCloud's version keeps the name; the NAS version is saved beside it as `name (conflict from NAS YYYY-MM-DD).ext` and uploaded too.

## Open — resume here

**What happens to a file deleted in iCloud, in mirror mode, and to the NAS-only files present when mirror is first switched on?**

Eric runs Drive with `remove_obsolete: false`, so the NAS holds files iCloud deleted long ago. A mirror that sees them as "new on the NAS" would re-upload them.

- **Option A (recommended):** iCloud deletions move the NAS copy into `.deleted/`; retention can be `forever`, which keeps everything `remove_obsolete: false` keeps today, outside the mirrored tree. The first mirror pass moves NAS-only files into the bin after a dry-run preview; a one-time `adopt` uploads any that really should go up. In mirror mode the bin's retention replaces `remove_obsolete`.
- **Option B (Eric's first instinct):** iCloud deletions never touch the NAS copy; files stay in place and the sync remembers "deleted in iCloud, keep, never upload". Asymmetric and workable, but the folder stops being a true mirror and a later local edit to such a file has no obvious meaning.
- Eric was unsure between these on 2026-10-01 and wanted to sleep on it.

## Still to cover after that

- Configuration shape (global mode plus per-folder overrides).
- Saved sync state: what is recorded per file (iCloud id/etag, size, mtimes) and where it lives in `/config`.
- Safety rails: dry run, a cap on mass uploads and deletes, behaviour when the destination is unmounted (reuse `require_mount_marker`).
- Packages (`.pages`, `.band` …) — almost certainly download-only to start.
- Upstream strategy: an RFC comment on #79 before building, since this is the largest change yet and Mandar should agree to the shape.
