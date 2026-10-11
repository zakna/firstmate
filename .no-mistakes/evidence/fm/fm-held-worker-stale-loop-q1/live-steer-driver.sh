#!/usr/bin/env bash
# Live driver: the real bin/fm-watch.sh from <code-root> supervises a real
# Claude CLI pane on a private lab tmux socket inside a disposable lab FM_HOME.
# Usage: live-steer-driver.sh <code-root> <case> where case is
#   young-hold     captain-held status written just now
#   rechecked-hold captain-held status older than the re-surface window
#   no-hold        an ordinary "working:" status (adversarial: must still surface)
set -u
CODE=$1; CASE=$2
. "$CODE/bin/fm-classify-lib.sh"
size_of() { LC_ALL=C wc -c < "$1" | tr -d '[:space:]'; }
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$CODE/bin/fm-lab-home.sh" create "$LAB" >/dev/null
TD=$("$CODE/bin/fm-lab-home.sh" tmux-dir "$LAB")
STATE="$LAB/state"
T() { TMUX_TMPDIR="$TD" tmux -L fm-lab "$@"; }
cleanup() { T kill-server 2>/dev/null; "$CODE/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1; rm -rf "$LAB"; }
trap cleanup EXIT

WIN=fleet:fm-held
T new-session -d -s fleet -n fm-held -x 160 -y 45 -c "$CODE" claude
SOCK=$(T display -p '#{socket_path}')
sleep 6
printf 'window=%s\nkind=ship\nharness=claude\nbackend=tmux\n' "$WIN" > "$STATE/held.meta"
GEN=$("$CODE/bin/fm-busy-event.sh" arm "$STATE" held --state idle --source fm-recovery --event reset)
case "$CASE" in
  no-hold) printf 'working: implementing the parser\n' > "$STATE/held.status" ;;
  *) printf 'captain-held [key=route]: tracked by held-decision-route\n' > "$STATE/held.status" ;;
esac
if [ "$CASE" = rechecked-hold ]; then
  touch -t "$(date -r $(( $(date +%s) - 2000 )) +%Y%m%d%H%M.%S)" "$STATE/held.status"
fi
printf 'v2\t%s\t%s@%s' "$(status_observed_signature "$STATE/held.status")" \
  "$(size_of "$STATE/held.status")" "$(_fm_open_decisions_file_ident "$STATE/held.status")" \
  > "$STATE/.seen-held_status"

round() {  # <label> <polls>
  local pid i=0
  env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
    FM_HOME="$LAB" TMUX="$SOCK,0,0" TMUX_TMPDIR="$TD" FM_WATCH_HANDLING_SUCCESSOR=1 \
    FM_PAUSE_RESURFACE_SECS=999 FM_POLL=1 FM_SIGNAL_GRACE=1 \
    FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 "$CODE/bin/fm-watch.sh" >> "$LAB/watch.out" 2>&1 &
  pid=$!
  sleep "$2"; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  printf '%-34s stale-wakes-so-far=%s  busy=%s\n' "$1" \
    "$(awk -F '\t' -v w="$WIN" '$3=="stale" && $4==w {n++} END{print n+0}' "$STATE/.wake-queue" 2>/dev/null || echo 0)" \
    "$(cut -d' ' -f4 "$STATE/held.busy-state" 2>/dev/null)"
}

echo "### case=$CASE code=$(git -C "$CODE" rev-parse --short HEAD)"
echo "status: $(cat "$STATE/held.status")  (age $(( $(date +%s) - $(stat -f %m "$STATE/held.status") ))s)"
round "1 quiet worker (initial sight)" 10
# The steer: supervision types into the pane and the worker turns busy.
"$CODE/bin/fm-busy-event.sh" apply "$STATE" held busy --gen "$GEN" --source claude-hook --event UserPromptSubmit >/dev/null
T send-keys -t "$WIN" -l 'steer: please re-check the routing note'
round "2 worker busy answering steer" 6
# The worker answers and goes quiet again: a NEW stale hash.
"$CODE/bin/fm-busy-event.sh" apply "$STATE" held idle --gen "$GEN" --source claude-hook --event Stop >/dev/null
T send-keys -t "$WIN" C-u; T send-keys -t "$WIN" -l 'steer answered'
round "3 quiet again after steer" 12
echo "--- wake queue (all rows) ---"
cut -c1-220 "$STATE/.wake-queue" 2>/dev/null
echo "--- watcher stdout/stderr (tail) ---"
tail -8 "$LAB/watch.out"
echo "--- pause bookkeeping ---"; ls -a "$STATE" | grep -E "paused|stale-|count-" 
echo "--- pane (last 6 lines) ---"
T capture-pane -p -t "$WIN" | grep -v '^\s*$' | tail -6
