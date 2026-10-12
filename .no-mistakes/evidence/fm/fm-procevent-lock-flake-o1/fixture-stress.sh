#!/usr/bin/env bash
# Stress old (poll -s pid) vs new (ready handshake) dead-owner fixtures; count leftover empty pid files.
set -u
REPO=$1; N=${2:-300}; LIB="$REPO/bin/fm-wake-lib.sh"
fail() { echo "FAIL: $*"; exit 1; }
. "$REPO/tests/lib.sh" 2>/dev/null || true
old_fixture() {
  local state=$1 lock=$2 holder i
  FM_STATE_OVERRIDE="$state" bash -c '. "$1"; fm_lock_try_create "$2" || exit 7; exec sleep 30' _ "$LIB" "$lock" >/dev/null 2>&1 &
  holder=$!; i=0
  while [ "$i" -lt 50 ] && [ ! -s "$lock/pid" ]; do sleep 0.02; i=$((i+1)); done
  kill -KILL "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
}
# CPU load to widen scheduling windows
for _ in 1 2 3 4 5 6 7 8; do ( while :; do :; done ) & done
LOADPIDS=$(jobs -p)
trap 'kill $LOADPIDS 2>/dev/null' EXIT
for mode in old new; do
  empty=0
  for n in $(seq "$N"); do
    st=$(mktemp -d); lock="$st/.x.lock.steal"
    if [ $mode = old ]; then old_fixture "$st" "$lock"; else fm_leave_dead_link_locks "$LIB" "$st" "$lock"; fi
    [ -s "$lock/pid" ] || empty=$((empty+1))
    rm -rf "$st"
  done
  echo "$mode fixture: $empty/$N runs left an empty/missing pid behind the dead-owner lock"
done
