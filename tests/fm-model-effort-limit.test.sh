#!/usr/bin/env bash
# Behavior tests for the Sonnet/Haiku effort ceiling enforced at spawn and relaunch time.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HARNESS="$ROOT/bin/fm-harness.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-model-effort-limit)

# <harness> <model> <effort> <allow|refuse> <expected error substring, refuse only>
while IFS='|' read -r harness model effort want expect; do
  [ -n "$harness" ] || continue
  out=$(bash "$HARNESS" validate-model-effort "$harness" "$model" "$effort" 2>&1)
  rc=$?
  case "$want" in
    allow) [ "$rc" -eq 0 ] && [ -z "$out" ] || fail "$harness $model $effort should be allowed (rc=$rc): $out" ;;
    refuse)
      [ "$rc" -ne 0 ] || fail "$harness $model $effort should be refused"
      case "$out" in *"$expect"*) ;; *) fail "$harness $model $effort refusal lacks '$expect': $out" ;; esac
      case "$out" in *"$model"*"$effort"*) ;; *) fail "refusal must name model and effort: $out" ;; esac
      ;;
  esac
done <<'TABLE'
claude|claude-sonnet-5-5|low|allow|
claude|claude-sonnet-5-5|medium|allow|
claude|claude-sonnet-5-5|high|refuse|maximum for Sonnet is medium
claude|claude-sonnet-5-5|xhigh|refuse|maximum for Sonnet is medium
claude|claude-sonnet-5-5|max|refuse|maximum for Sonnet is medium
claude|sonnet|high|refuse|maximum for Sonnet is medium
claude|Claude-Sonnet-4-5|high|refuse|maximum for Sonnet is medium
claude|claude-haiku-5-5|low|allow|
claude|claude-haiku-5-5|medium|refuse|maximum for Haiku is low
claude|claude-haiku-5-5|high|refuse|maximum for Haiku is low
claude|haiku|xhigh|refuse|maximum for Haiku is low
claude|claude-opus-5-5|max|allow|
claude|claude-fable-5-1|xhigh|allow|
claude|claude-sonnet-5-5|default|allow|
claude|claude-sonnet-5-5||allow|
claude||high|allow|
codex|sonnet|high|allow|
pi|claude-haiku-5-5|high|allow|
TABLE
pass "validate-model-effort table"

# The spawn entry point refuses before any provisioning.
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config" "$HOME_DIR/data"
out=$(FM_HOME="$HOME_DIR" bash "$SPAWN" model-effort-t1 "$TMP_ROOT/nowhere" --scout --harness claude --model claude-sonnet-5-5 --effort high 2>&1)
rc=$?
[ "$rc" -ne 0 ] || fail "spawn should refuse Sonnet at high effort"
case "$out" in *"maximum for Sonnet is medium"*) ;; *) fail "spawn refusal missing: $out" ;; esac
pass "fm-spawn refuses Sonnet at high effort"
