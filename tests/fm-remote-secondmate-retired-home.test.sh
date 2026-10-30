#!/usr/bin/env bash
# tests/fm-remote-secondmate-retired-home.test.sh - the host-local steering and
# retire verbs of bin/fm-remote-secondmate-control.sh treat an absent home, or a
# shell of empty directories left under a removed home, as already retired and
# leave the home absent; a home they cannot fully read is never classified as
# retired.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot fm-remote-secondmate-retired-home)
HOME_DIR="$TMP/home"
CONTROL="$ROOT/bin/fm-remote-secondmate-control.sh"

control() { FM_HOME="$HOME_DIR" "$CONTROL" "$@"; }

[ -z "$(control steering ios)" ] || fail "an absent home listed steering records"
[ "$(control retire ios)" = "already-retired: ios" ] || fail "an absent home was not reported as already retired"
[ ! -e "$HOME_DIR" ] || fail "the verbs of an absent home created it"
pass "an absent remote home is already retired"

mkdir -p "$HOME_DIR/state/parent-route"
[ -z "$(control steering ios)" ] || fail "an empty home shell listed steering records"
[ ! -e "$HOME_DIR" ] || fail "the steering listing left an empty home shell behind"
mkdir -p "$HOME_DIR/state/parent-route"
[ "$(control retire ios)" = "already-retired: ios" ] || fail "an empty home shell was not reported as already retired"
[ ! -e "$HOME_DIR" ] || fail "a retried retirement left an empty home shell behind"
pass "a home holding only empty directories is already retired and removed"

if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$HOME_DIR/state/locked"
  printf 'live\n' > "$HOME_DIR/state/locked/record"
  chmod 000 "$HOME_DIR/state/locked"
  if out=$(control retire ios 2>&1); then
    fail "a home with an unreadable directory was retired: $out"
  fi
  case "$out" in *already-retired*) fail "a home with an unreadable directory was reported as already retired" ;; esac
  if control steering ios >/dev/null 2>&1; then
    fail "the steering listing of a home with an unreadable directory succeeded"
  fi
  chmod 700 "$HOME_DIR/state/locked"
  [ -f "$HOME_DIR/state/locked/record" ] || fail "a refused retirement removed the unreadable home's contents"
  pass "a home that cannot be fully read is never classified as retired"
fi

# A seeded home whose steering record cannot be read must refuse the listing,
# never emit an empty record the parent would archive before retiring the home.
if [ "$(id -u)" -ne 0 ]; then
  SEEDED="$TMP/seeded"
  mkdir -p "$SEEDED/bin" "$SEEDED/state/parent-route/ios.inbox"
  printf 'ios\n' > "$SEEDED/.fm-secondmate-home"
  : > "$SEEDED/AGENTS.md"
  printf 'steer that must not be lost\n' > "$SEEDED/state/parent-route/ios.inbox/001.msg"
  chmod 000 "$SEEDED/state/parent-route/ios.inbox/001.msg"
  if out=$(FM_HOME="$SEEDED" "$CONTROL" steering ios 2>/dev/null); then
    chmod 600 "$SEEDED/state/parent-route/ios.inbox/001.msg"
    fail "an unreadable steering record was listed with exit 0: $out"
  fi
  chmod 600 "$SEEDED/state/parent-route/ios.inbox/001.msg"
  pass "an unreadable steering record refuses the listing"

  # An empty home shell that cannot be removed is not retired.
  mkdir -p "$TMP/ro/home/state"
  chmod 555 "$TMP/ro"
  if out=$(FM_HOME="$TMP/ro/home" "$CONTROL" retire ios 2>&1); then
    chmod 755 "$TMP/ro"
    fail "an empty home that could not be removed was reported retired: $out"
  fi
  chmod 755 "$TMP/ro"
  [ -d "$TMP/ro/home" ] || fail "fixture home vanished"
  pass "an empty home that cannot be removed is not reported as already retired"
fi
