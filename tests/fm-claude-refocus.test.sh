#!/usr/bin/env bash
# tests/fm-claude-refocus.test.sh - the Claude post-compaction refocus block
# (bin/fm-claude-refocus.sh) run against fixture briefs and steering inboxes.
#   1. The block carries the brief's Captain's intent and Definition of done
#      verbatim and the newest unhandled steer, skipping handled and older ones.
#   2. With no unhandled steer it says so in one line and still exits 0.
#   3. A missing brief is named rather than failing the hook.
#   4. The hook reads only its own task's inbox, never another task's.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REFOCUS="$ROOT/bin/fm-claude-refocus.sh"
TMP_ROOT=$(fm_test_tmproot fm-claude-refocus)

write_brief() {  # <path>
  cat >"$1" <<'EOF'
# Current worker role contract
Role text that is not an anchor.

# Task
## Captain's intent
Ship the widget exactly as asked.
Keep the old flag working.

## Firstmate spec
Spec text that is not an anchor.

# Rules
Rules text that is not an anchor.

# Definition of done
Delivery contract: mode=no-mistakes
Append done when the branch is committed.

# Home brief additions
Additions text that is not an anchor.
EOF
}

write_steer() {  # <state> <id> <text>
  bash -c '. "$1/bin/fm-task-inbox-lib.sh" && fm_task_inbox_write "$2" "$3" "$4" >/dev/null' _ "$ROOT" "$1" "$2" "$3"
}

handle_oldest() {  # <state> <id>
  local dir=$1/$2.inbox f
  mkdir -p "$dir/handled"
  for f in "$dir"/*.msg; do
    mv "$f" "$dir/handled/"
    return 0
  done
}

test_block_carries_anchors_and_newest_steer() {
  local dir=$TMP_ROOT/anchors state out
  state=$dir/state
  mkdir -p "$state"
  write_brief "$dir/brief.md"
  write_steer "$state" t1 "acknowledged steer t1"
  handle_oldest "$state" t1
  write_steer "$state" t1 "older unhandled steer"
  write_steer "$state" t1 "newest steer line one
newest steer line two"
  out=$("$REFOCUS" "$dir/brief.md" "$state" t1 </dev/null)
  expect_code 0 $? "refocus must exit 0"
  case "$out" in *"Ship the widget exactly as asked."*"Keep the old flag working."*) ;; *) fail "intent missing: $out" ;; esac
  case "$out" in *"Delivery contract: mode=no-mistakes"*"Append done when the branch is committed."*) ;; *) fail "definition of done missing: $out" ;; esac
  case "$out" in *"newest steer line one"*"newest steer line two"*) ;; *) fail "newest steer missing: $out" ;; esac
  case "$out" in *"$state/t1.inbox/003.msg"*) ;; *) fail "newest record path missing: $out" ;; esac
  for absent in "older unhandled steer" "acknowledged steer t1" "Spec text" "Rules text" "Role text" "Additions text"; do
    case "$out" in *"$absent"*) fail "block must not carry '$absent': $out" ;; esac
  done
  pass "refocus carries intent, definition of done, and only the newest unhandled steer"
}

test_no_unhandled_steer() {
  local dir=$TMP_ROOT/empty state out
  state=$dir/state
  mkdir -p "$state"
  write_brief "$dir/brief.md"
  write_steer "$state" t2 "acknowledged steer t2"
  handle_oldest "$state" t2
  out=$("$REFOCUS" "$dir/brief.md" "$state" t2 </dev/null)
  expect_code 0 $? "refocus with no steer must exit 0"
  case "$out" in *"No unhandled steering message is waiting in $state/t2.inbox."*) ;; *) fail "no-steer line missing: $out" ;; esac
  case "$out" in *"acknowledged steer t2"*) fail "a handled steer must not be re-injected: $out" ;; esac
  case "$out" in *"Ship the widget exactly as asked."*) ;; *) fail "intent missing without a steer: $out" ;; esac

  out=$("$REFOCUS" "$dir/brief.md" "$state" never-steered </dev/null)
  expect_code 0 $? "refocus with an absent inbox must exit 0"
  case "$out" in *"No unhandled steering message is waiting"*) ;; *) fail "absent inbox must read as no steer: $out" ;; esac
  pass "refocus says no steer is waiting when none is unhandled"
}

test_missing_brief_is_named() {
  local dir=$TMP_ROOT/nobrief out
  mkdir -p "$dir/state"
  out=$("$REFOCUS" "$dir/absent.md" "$dir/state" t3 </dev/null)
  expect_code 0 $? "refocus with a missing brief must exit 0"
  case "$out" in *"The brief is not readable at $dir/absent.md"*) ;; *) fail "missing brief not named: $out" ;; esac
  pass "refocus names a missing brief instead of failing"
}

test_reads_only_its_own_task() {
  local dir=$TMP_ROOT/isolation state out
  state=$dir/state
  mkdir -p "$state"
  write_brief "$dir/brief.md"
  write_steer "$state" other "steer for another task"
  out=$("$REFOCUS" "$dir/brief.md" "$state" mine </dev/null)
  case "$out" in *"steer for another task"*) fail "refocus read another task's inbox: $out" ;; esac
  case "$out" in *"No unhandled steering message is waiting in $state/mine.inbox."*) ;; *) fail "own empty inbox not reported: $out" ;; esac
  pass "refocus reads only its own task's inbox"
}

test_block_carries_anchors_and_newest_steer
test_no_unhandled_steer
test_missing_brief_is_named
test_reads_only_its_own_task

echo "all fm-claude-refocus tests passed"
