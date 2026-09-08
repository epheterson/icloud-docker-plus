#!/usr/bin/env bash
#
# Prune pre-`filename_format: simple` orphans from the photo libraries.
#
# WHY THIS EXISTS
# ---------------
# Switching photos.filename_format from "metadata" to "simple" does not
# migrate files already on disk -- icloud-docker re-downloads every asset
# under the new plain name and leaves the old `NAME__filesize__<b64id>.EXT`
# copy behind. Those copies are untracked, so obsolete-file cleanup wants to
# delete them; but on a large library they exceed the 25% obsolete-delete
# limit, so the circuit breaker (photo_cleanup_utils.py) refuses -- correctly,
# and forever. Nothing resolves that standoff on its own. This script does,
# under conditions strictly tighter than the ones cleanup would apply.
#
# SAFETY PROPERTY
# ---------------
# A file is deleted only when ALL of these hold:
#
#   1. It is metadata-named: NAME__<filesize>__<base64id>.EXT
#   2. It is NOT a live filename-collision fallback. The collision fallback
#      (photo_download_manager.py) deliberately writes metadata-named files
#      when two distinct assets share one plain name, and TRACKS them. Those
#      must never be touched. The live set is read from the container log.
#   3. Its simple-format counterpart (NAME.EXT) exists on disk.
#   4. The counterpart is byte-for-byte the same SIZE.
#
# Conditions 1+2 alone are exactly what icloud-docker's own cleanup would
# delete. Conditions 3+4 are additional. So this script can never remove a
# file the application itself would have kept.
#
# Anything failing 3 or 4 is KEPT and listed in the review manifest.
#
# Usage:  ./prune-legacy-filename-orphans.sh            # dry run (default)
#         ./prune-legacy-filename-orphans.sh --apply    # actually delete
set -euo pipefail

PHOTO_ROOT="${PHOTO_ROOT:-/volume1/ELP NAS/Pictures/iCloud}"
CONTAINER="${CONTAINER:-icloud}"
DOCKER="${DOCKER:-/usr/local/bin/docker}"
CONTAINER_ROOT="/icloud/photos"
WORK="${WORK:-/tmp/prune-legacy-$(date +%Y%m%d-%H%M%S)}"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

mkdir -p "$WORK"
echo "workdir: $WORK"
echo "mode:    $([ $APPLY -eq 1 ] && echo 'APPLY (will delete)' || echo 'DRY RUN')"
echo

# --- Step 1: the live collision-fallback set -------------------------------
# Every fallback logs "using suffix path <path> to preserve both photos."
# We take the LAST COMPLETE photos pass so the set reflects current state.
echo "==> reading container log for collision fallbacks"
"$DOCKER" logs --since 168h "$CONTAINER" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$WORK/log.txt"

last_synced=$(grep -n 'Photos synced' "$WORK/log.txt" | tail -1 | cut -d: -f1 || true)
prev_synced=$(grep -n 'Photos synced' "$WORK/log.txt" | tail -2 | head -1 | cut -d: -f1 || true)
if [ -z "$last_synced" ] || [ -z "$prev_synced" ] || [ "$last_synced" = "$prev_synced" ]; then
  echo "REFUSING: could not find two complete photo passes in the log."
  echo "Without a full pass the collision-fallback set is incomplete, and"
  echo "deleting against a partial set could remove a tracked file."
  exit 1
fi

sed -n "$((prev_synced + 1)),${last_synced}p" "$WORK/log.txt" > "$WORK/lastpass.txt"
grep 'Filename collision' "$WORK/lastpass.txt" \
  | sed 's/.*using suffix path //; s/ to preserve both photos\.$//' \
  | sed "s|^${CONTAINER_ROOT}|${PHOTO_ROOT}|" \
  | sort -u > "$WORK/collision_paths.txt"

collisions=$(wc -l < "$WORK/collision_paths.txt")
echo "    collision fallbacks currently tracked: $collisions"
if [ "$collisions" -eq 0 ]; then
  echo "REFUSING: zero collision fallbacks found. Expected thousands."
  echo "The log window is probably too short or the format changed."
  exit 1
fi
echo

# --- Step 2: metadata-named files on disk -----------------------------------
echo "==> scanning $PHOTO_ROOT for metadata-named files"
find "$PHOTO_ROOT" -type f \
  \( -name '*__original__*'     -o -name '*__original_alt__*' \
  -o -name '*__medium__*'       -o -name '*__thumb__*' \
  -o -name '*__live_video_original__*' \
  -o -name '*__live_video_medium__*'   \
  -o -name '*__live_video_thumb__*' \) \
  | sort -u > "$WORK/metadata_files.txt"
echo "    metadata-named on disk: $(wc -l < "$WORK/metadata_files.txt")"

# --- Step 3: orphans = metadata-named MINUS live collision fallbacks --------
comm -23 "$WORK/metadata_files.txt" "$WORK/collision_paths.txt" > "$WORK/orphans.txt"
echo "    orphans (untracked, cleanup would delete these): $(wc -l < "$WORK/orphans.txt")"
echo

# --- Step 4: classify each orphan against its simple-format counterpart -----
echo "==> verifying every orphan has an identical simple-format counterpart"
: > "$WORK/safe_to_delete.txt"
: > "$WORK/review_no_counterpart.txt"
: > "$WORK/review_size_differs.txt"
: > "$WORK/review_unparseable.txt"
: > "$WORK/heal_by_rename.tsv"

# Map each orphan to the plain path it would occupy under `simple` naming.
# Strip ONLY the trailing __<filesize>__<base64id> block -- filenames can
# legitimately contain "__" of their own (e.g. 80369551201__DBD79095-...heic),
# so anchoring on the known file_size tokens at the end is the only safe cut.
VARIANTS='original_alt|original|medium|thumb|live_video_original|live_video_medium|live_video_thumb'
sed -E "s#__(${VARIANTS})__[A-Za-z0-9_=-]+(\\.[^./]+)?\$#\\2#" "$WORK/orphans.txt" > "$WORK/expected_simple.txt"
paste "$WORK/orphans.txt" "$WORK/expected_simple.txt" > "$WORK/pairs.tsv"

# Anything the sed did not actually change has no parseable variant block.
awk -F'\t' '$1==$2' "$WORK/pairs.tsv" | cut -f1 > "$WORK/review_unparseable.txt"

awk -F'\t' '$1!=$2' "$WORK/pairs.tsv" | while IFS=$'\t' read -r f simple; do
  if [ ! -e "$simple" ]; then
    # No counterpart AND the plain slot is free: this asset exists ONLY under
    # its legacy name -- it never re-downloaded under the new scheme. Deleting
    # it would lose the only copy. Rename it into the free slot instead, which
    # both preserves it and lets the next sync recognise it by size.
    printf '%s\t%s\n' "$f" "$simple" >> "$WORK/heal_by_rename.tsv"
  elif [ "$(stat -c%s "$f")" != "$(stat -c%s "$simple")" ]; then
    printf '%s\t%s\n' "$f" "$simple" >> "$WORK/review_size_differs.txt"
  else
    printf '%s\n' "$f" >> "$WORK/safe_to_delete.txt"
  fi
done

safe=$(wc -l < "$WORK/safe_to_delete.txt")
nocp=$(wc -l < "$WORK/review_no_counterpart.txt")
diff=$(wc -l < "$WORK/review_size_differs.txt")
unparse=$(wc -l < "$WORK/review_unparseable.txt")
heal=$(wc -l < "$WORK/heal_by_rename.tsv")
bytes=$(awk '{print}' "$WORK/safe_to_delete.txt" | tr '\n' '\0' | xargs -0 -r stat -c%s 2>/dev/null | awk '{s+=$1} END {print s+0}')

echo
echo "================ RESULT ================"
printf 'SAFE to delete      : %8d files  (%.1f GB)\n' "$safe" "$(echo "$bytes" | awk '{print $1/1073741824}')"
printf 'HEAL by rename       : %8d files  (only copy -- plain slot is free)\n' "$heal"
printf 'KEEP - size differs  : %8d files\n' "$diff"
printf 'KEEP - unparseable   : %8d files\n' "$unparse"
echo "========================================"
echo "manifests in $WORK/"
echo

if [ $APPLY -eq 0 ]; then
  echo "DRY RUN -- nothing deleted. Re-run with --apply to remove the SAFE set."
  exit 0
fi

if [ "$heal" -gt 0 ]; then
  echo "==> healing $heal legacy-only files by rename"
  while IFS=$'\t' read -r f simple; do
    [ -e "$simple" ] && { echo "    SKIP (slot taken since scan): $f"; continue; }
    mv -n -- "$f" "$simple" && echo "    $(basename "$f") -> $(basename "$simple")"
  done < "$WORK/heal_by_rename.tsv"
  echo
fi

echo "==> deleting $safe files"
n=0
while IFS= read -r f; do
  rm -f -- "$f"
  n=$((n + 1))
  [ $((n % 5000)) -eq 0 ] && echo "    $n / $safe"
done < "$WORK/safe_to_delete.txt"
echo "    done: $n files removed"
echo "Healed by rename: $heal. Kept for review: $nocp counterpart-taken, $diff size mismatch, $unparse unparseable."
