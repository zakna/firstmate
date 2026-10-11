#!/usr/bin/env bash
# Live Claude exit-dialog guard for the control plane (live-harness-optin family).
#
# Claude Code answers /exit with a "Background work is running" dialog while a
# background shell runs, and on Herdr that dialog's highlighted option reads as
# pending composer text. A stub can only replay the captured rows, so this
# guard launches real Claude Code in an isolated Herdr lab, starts a background
# shell, and drives bin/fm-control.sh exit for real: without --stop-background
# it must refuse, name the background work, and leave the agent and that work
# running; with it the agent must stop. It fails naming the harness and version
# rather than degrading quietly.
#
# Submits prompts, so it runs only with FM_CONTROL_EXIT_DIALOG_LIVE=1, after a
# Claude or Herdr upgrade and before trusting a refreshed
# docs/verification/runtime-backends.md "Claude exit dialog" entry.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fm_live_gate opt-in FM_CONTROL_EXIT_DIALOG_LIVE herdr jq claude

# shellcheck source=tests/herdr-test-safety.sh
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane

SESSION="fm-lab-control-exit-dialog-$$"
export HERDR_SESSION="$SESSION"
SCRATCH=
MARKER="FMEXITDIALOG$$x$RANDOM"
cleanup_all() {
  pkill -f "sleep 1801 # $MARKER" 2>/dev/null || true
  [ -n "$SCRATCH" ] && rm -rf "$SCRATCH"
  herdr_safe_stop_and_delete "$SESSION"
}
trap cleanup_all EXIT
fm_herdr_lab_prepare "$SESSION" || fail "could not prepare isolated Herdr lab session"

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/fm-control-exit-dialog.XXXXXX")
SCRATCH=$(cd "$SCRATCH" && pwd -P)
HOME_DIR="$SCRATCH/home"
PROJ="$SCRATCH/proj"
WT="$SCRATCH/wt"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/data/xdlg" "$PROJ"
printf '# brief for xdlg\n' > "$HOME_DIR/data/xdlg/brief.md"
git -C "$PROJ" init -q
git -C "$PROJ" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -q --allow-empty -m initial
git -C "$PROJ" worktree add --quiet -b xdlg "$WT"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"
fm_backend_source herdr || fail "fm_backend_source herdr failed"
CONTAINER_RAW=$(fm_backend_herdr_container_ensure "$WT") || fail "container_ensure failed"
CONTAINER=${CONTAINER_RAW%%$'\t'*}
WORKSPACE_ID=${CONTAINER#*:}
read -r TAB_ID PANE_ID <<EOF
$(fm_backend_herdr_create_task "$CONTAINER" fm-xdlg "$WT" "${CONTAINER_RAW#*$'\t'}")
EOF
[ -n "$TAB_ID" ] && [ -n "$PANE_ID" ] || fail "create_task did not return tab/pane ids"
{
  echo "window=$SESSION:$PANE_ID"
  echo "endpoint_task_id=xdlg"
  echo "worktree=$WT"
  echo "project=$PROJ"
  echo "harness=claude"
  echo "kind=ship"
  echo "mode=no-mistakes"
  echo "yolo=off"
  echo "model=default"
  echo "effort=default"
  echo "backend=herdr"
  echo "herdr_session=$SESSION"
  echo "herdr_workspace_id=$WORKSPACE_ID"
  echo "herdr_tab_id=$TAB_ID"
  echo "herdr_pane_id=$PANE_ID"
} > "$HOME_DIR/state/xdlg.meta"

VERSION=$(claude --version 2>/dev/null | head -1 || printf 'version-unknown')
HERDR_VER=$(herdr --version 2>/dev/null | head -1 || printf 'herdr-unknown')
version_fail() { fail "Claude Code ($VERSION) on $HERDR_VER: $1"; }
lab() { fm_backend_herdr_cli "$SESSION" "$@"; }
screen() { lab pane read "$PANE_ID" --source visible 2>/dev/null || true; }
run_control() {
  env FM_HOME="$HOME_DIR" HERDR_SESSION="$SESSION" FM_CONTROL_EXIT_WAIT=20 \
    "$ROOT/bin/fm-control.sh" "$@" 2>&1
}
wait_idle() {  # <what>
  local i=0 st
  while [ "$i" -lt 90 ]; do
    case "$(screen)" in
      *'Yes, I trust this folder'*)
        # The prompt preselects "No, exit"; a bare Enter would quit Claude.
        lab pane send-keys "$PANE_ID" down enter >/dev/null || version_fail "could not accept the folder-trust prompt"
        ;;
      *'bypass permissions on'*)
        st=$(lab agent get "$PANE_ID" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
        case "$st" in idle|done) return 0 ;; esac
        ;;
    esac
    i=$((i + 1))
    sleep 1
  done
  version_fail "never rendered an idle composer $1"
}

lab pane run "$PANE_ID" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false claude --model haiku --dangerously-skip-permissions" >/dev/null \
  || version_fail "could not launch in the isolated Herdr pane"
wait_idle "after launch"
verdict=$(fm_backend_herdr_send_text_submit "$SESSION:$PANE_ID" \
  "Use the Bash tool with run_in_background set to true to run exactly: sleep 1801 # $MARKER - then reply only STARTED." 3 0.4 0.4) \
  || version_fail "could not submit the background-shell prompt"
[ "$verdict" != send-failed ] || version_fail "the background-shell prompt was not submitted"
i=0
until pgrep -f "sleep 1801 # $MARKER" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -lt 90 ] || version_fail "never started the requested background shell"
  sleep 1
done
wait_idle "after starting the background shell"

OUT=$(run_control xdlg exit) && version_fail "exit without --stop-background should refuse at the background-work dialog, got: $OUT"
case "$OUT" in
  *"$MARKER"*--stop-background*) : ;;
  *) version_fail "the refusal should name the background work and --stop-background, got: $OUT" ;;
esac
[ "$(fm_backend_agent_state herdr "$SESSION:$PANE_ID")" = alive ] || version_fail "the agent should keep running after the refusal"
pgrep -f "sleep 1801 # $MARKER" >/dev/null 2>&1 || version_fail "the background shell should keep running after the refusal"
case "$(screen)" in
  *'Background work is running'*) version_fail "the refusal should close the dialog with Stay" ;;
esac
pass "live control exit: Claude Code ($VERSION) on $HERDR_VER refuses at the background-work dialog and keeps the agent and its work"

OUT=$(run_control xdlg exit --stop-background) || version_fail "exit --stop-background should stop the agent, got: $OUT"
case "$OUT" in
  "stopped xdlg"*"background-stopped="*"$MARKER"*) : ;;
  *) version_fail "exit --stop-background should report the stopped background work, got: $OUT" ;;
esac
i=0
while pgrep -f "sleep 1801 # $MARKER" >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -lt 20 ] || version_fail "'Exit and stop tasks' left the background shell running"
  sleep 0.5
done
pass "live control exit --stop-background: Claude Code ($VERSION) on $HERDR_VER confirms 'Exit and stop tasks' and stops"
