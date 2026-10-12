#!/usr/bin/env bash
# Show the acquirer outcome for a dead steal owner whose pid file is complete (new fixture)
# vs. truncated to empty (what the old fixture left when SIGKILL hit fm_lock_claim's pid rewrite).
set -u
REPO=$1; LIB="$REPO/bin/fm-wake-lib.sh"
fail() { echo "FAIL: $*"; exit 1; }
. "$REPO/tests/lib.sh" 2>/dev/null || true
run() {
  local label=$1 truncate=$2 st lock rc=0
  st=$(mktemp -d); lock="$st/.contend.lock"
  mkdir "$lock"; printf '%s\n' 999999 > "$lock/pid"
  fm_leave_dead_link_locks "$LIB" "$st" "$lock.steal"
  [ "$truncate" = 1 ] && : > "$lock.steal/pid"
  printf '%s steal pid=[%s] -> ' "$label" "$(cat "$lock.steal/pid")"
  FM_STATE_OVERRIDE="$st" bash -c '. "$1"; fm_lock_try_acquire "$2" || exit 8; fm_lock_release "$2"' _ "$LIB" "$lock" || rc=$?
  echo "acquirer rc=$rc"
  rm -rf "$st"
}
run "complete-pid (new fixture output)" 0
run "empty-pid (old fixture race output)" 1
