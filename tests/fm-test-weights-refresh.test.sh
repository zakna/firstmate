#!/usr/bin/env bash
# Contract tests for bin/fm-test-weights-refresh.sh: it rewrites only the
# portable-serial hint table of a runner copy from timing JSON, using the
# slowest passing sample per script, and is idempotent.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REFRESH="$ROOT/bin/fm-test-weights-refresh.sh"
RUNNER="$ROOT/bin/fm-test-run.sh"

assert_present "$REFRESH" "bin/fm-test-weights-refresh.sh is missing"
command -v jq >/dev/null 2>&1 || fail "jq is required"

serial_hint() {  # <runner-file> <path>
  awk -v want="$2" '
    /^portable_serial_weight_hints\(\) \{/ { inf = 1 }
    inf && $1 == want { print $2; exit }
  ' "$1"
}

test_refresh_uses_slowest_passing_sample_and_is_idempotent() {
  local tmp target a b before_parallel
  tmp=$(fm_test_tmproot fm-weights-refresh) || fail "tmproot"
  target="$tmp/fm-test-run.sh"
  cp "$RUNNER" "$target"
  a="tests/fm-ask-user-authority.test.sh"
  b="tests/fm-backend.test.sh"
  before_parallel=$(sed -n '/^portable_parallel_weight_hints() {/,/^EOF$/p' "$target" | wc -l)

  jq -n --arg a "$a" --arg b "$b" '{scripts:[
    {path:$a,exit:0,duration_ms:1000},
    {path:$b,exit:0,duration_ms:5000},
    {path:$b,exit:1,duration_ms:999999}]}' >"$tmp/one.json"
  jq -n --arg b "$b" '{scripts:[{path:$b,exit:0,duration_ms:7000}]}' >"$tmp/two.json"

  "$REFRESH" --target "$target" "$tmp/one.json" "$tmp/two.json" >"$tmp/out" \
    || fail "refresh failed: $(cat "$tmp/out")"
  assert_equals "1000" "$(serial_hint "$target" "$a")" "fast script takes its sample"
  assert_equals "7000" "$(serial_hint "$target" "$b")" "slowest passing sample wins, failed sample ignored"
  assert_equals "$before_parallel" "$(sed -n '/^portable_parallel_weight_hints() {/,/^EOF$/p' "$target" | wc -l)" "parallel table untouched"
  assert_equals "$(serial_hint "$RUNNER" "tests/fm-backend-orca.test.sh")" "$(serial_hint "$target" "tests/fm-backend-orca.test.sh")" "script with no sample keeps its hint"
  bash -n "$target" || fail "rewritten runner must still parse"

  cp "$target" "$tmp/after-first"
  "$REFRESH" --target "$target" "$tmp/one.json" "$tmp/two.json" >"$tmp/out2" || fail "second refresh failed"
  cmp -s "$tmp/after-first" "$target" || fail "second refresh must leave the file byte-identical"
  assert_contains "$(cat "$tmp/out2")" "unchanged" "idempotent run says unchanged"
  pass "refresh takes the slowest passing sample, keeps unmeasured hints, and is idempotent"
}

test_refresh_refuses_bad_input() {
  local tmp
  tmp=$(fm_test_tmproot fm-weights-refresh-bad) || fail "tmproot"
  "$REFRESH" >/dev/null 2>&1 && fail "no timing file must be refused"
  "$REFRESH" "$tmp/missing.json" >/dev/null 2>&1 && fail "missing timing file must be refused"
  pass "refresh refuses missing input"
}

test_refresh_uses_slowest_passing_sample_and_is_idempotent
test_refresh_refuses_bad_input
