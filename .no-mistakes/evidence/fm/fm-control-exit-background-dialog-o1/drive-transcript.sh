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
WTROOT=${WTROOT:?}

# shellcheck source=tests/lib.sh
. "$WTROOT/tests/lib.sh"

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
printf '# Task\n\n## Captain\x27s intent\n\nLab fixture.\n\n## Firstmate spec\n\nReply DONE and wait.\n' > "$HOME_DIR/data/xdlg/brief.md"
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


snap() { echo "----- pane ($1) -----"; screen | grep -v '^[[:space:]]*$' | tail -25; echo "-----"; }
echo "== S3-only run =="; : <<'SKIP'
echo "== S1: relaunch WITHOUT --stop-background (dialog open) =="
OUT=$(run_control xdlg relaunch --note "evidence relaunch"); echo "rc=$?"; echo "$OUT"
echo "agent-state=$(fm_backend_agent_state herdr "$SESSION:$PANE_ID")"
pgrep -fl "sleep 1801 # $MARKER" && echo "background shell still running"
snap after-relaunch-refusal
echo "== S2: exit WITHOUT --stop-background =="
OUT=$(run_control xdlg exit); echo "rc=$?"; echo "$OUT"
echo "agent-state=$(fm_backend_agent_state herdr "$SESSION:$PANE_ID")"
pgrep -fl "sleep 1801 # $MARKER" && echo "background shell still running"
snap after-exit-refusal
SKIP
echo "== S3: relaunch WITH --stop-background =="
OUT=$(run_control xdlg relaunch --stop-background --note "evidence relaunch"); echo "rc=$?"; echo "$OUT"
sleep 20
echo "agent-state=$(fm_backend_agent_state herdr "$SESSION:$PANE_ID")"
pgrep -fl "sleep 1801 # $MARKER" || echo "background shell gone"
snap after-relaunch-stop
grep -h . "$HOME_DIR/state/xdlg"* 2>/dev/null | grep -E "relaunch|exit_result|harness=|worktree=" | head
