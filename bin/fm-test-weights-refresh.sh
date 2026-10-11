#!/usr/bin/env bash
# fm-test-weights-refresh.sh - rewrite the portable-serial duration hints in
# bin/fm-test-run.sh from measured CI timing artifacts.
#
#   fm-test-weights-refresh.sh [--target <runner-file>] <timing.json> [more...]
#
# Inputs are the `fm-test-timing-portable-serial-*` JSON artifacts that
# `fm-test-run.sh --json` writes (the same data as the FM_TEST_END
# duration_ms= markers). Each script's new hint is the slowest exit-0
# duration across all inputs, the convention docs/fm-test-portable-shards.md
# records. A script with no passing sample keeps its current hint; a script
# in the serial lane with no hint at all and no sample stays unhinted, and a
# hint for a script no longer in the lane is dropped.
#
# Only the serial table is refreshed: the serial shards are packed from it at
# run time, so fresh values rebalance them with no further edit. The parallel
# lanes keep stored memberships, so refreshing their values alone would not
# rebalance anything; that stays the manual step the same doc describes.
#
# --target defaults to the sibling fm-test-run.sh, which also supplies the
# serial lane membership. The rewrite is idempotent: unchanged measurements
# leave the file byte-identical. Prints a one-line summary on stdout.
set -euo pipefail

SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUNNER="$SELF_DIR/fm-test-run.sh"
TARGET=$RUNNER

die() { printf 'fm-test-weights-refresh: %s\n' "$*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) [ "$#" -ge 2 ] || die "--target needs a file"; TARGET=$2; shift 2 ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d;s/^# \{0,1\}//'; exit 0 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[ "$#" -ge 1 ] || die "at least one timing JSON is required"
[ -f "$TARGET" ] || die "target not found: $TARGET"
command -v jq >/dev/null 2>&1 || die "jq is required"
for f in "$@"; do [ -f "$f" ] || die "timing file not found: $f"; done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/fm-weights-refresh.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

jq -r '.scripts[]? | select(.exit == 0) | [.path, .duration_ms] | @tsv' "$@" \
  | awk -F'\t' 'NF == 2 && ($2 + 0) > m[$1] { m[$1] = $2 + 0 } END { for (p in m) print p, m[p] }' \
  | LC_ALL=C sort >"$tmp/samples"

"$RUNNER" --list --lane portable-serial | LC_ALL=C sort >"$tmp/lane"
[ -s "$tmp/lane" ] || die "could not list the portable-serial lane"

awk '
  /^portable_serial_weight_hints\(\) \{/ { inf = 1; next }
  inf && /^EOF$/ { if (seen) exit; next }
  inf && /^  cat <<.EOF.$/ { seen = 1; next }
  inf && seen && NF == 2 { print }
' "$TARGET" >"$tmp/current"
[ -s "$tmp/current" ] || die "no serial hint table found in $TARGET"

awk '
  FILENAME == ARGV[1] { lane[$1] = 1; next }
  FILENAME == ARGV[2] { cur[$1] = $2; next }
  { smp[$1] = $2 }
  END {
    for (p in lane) {
      if (p in smp) print p, smp[p]; else if (p in cur) print p, cur[p]
    }
  }
' "$tmp/lane" "$tmp/current" "$tmp/samples" | LC_ALL=C sort >"$tmp/new"

if cmp -s <(LC_ALL=C sort "$tmp/current") "$tmp/new"; then
  printf 'serial hints unchanged (%s scripts)\n' "$(wc -l <"$tmp/new" | tr -d ' ')"
  exit 0
fi

awk -v newfile="$tmp/new" '
  /^portable_serial_weight_hints\(\) \{/ { inf = 1 }
  inf && /^  cat <<.EOF.$/ { print; while ((getline line < newfile) > 0) print line; skip = 1; next }
  skip && /^EOF$/ { skip = 0; inf = 0 }
  !skip { print }
' "$TARGET" >"$tmp/out"
cat "$tmp/out" >"$TARGET"

changed=$(awk 'FILENAME == ARGV[1] { o[$1] = $2; next } !($1 in o) || o[$1] != $2 { n++ } END { print n + 0 }' "$tmp/current" "$tmp/new")
printf 'serial hints refreshed: %s of %s scripts changed\n' "$changed" "$(wc -l <"$tmp/new" | tr -d ' ')"
