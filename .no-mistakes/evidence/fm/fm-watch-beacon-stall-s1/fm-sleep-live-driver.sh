#!/usr/bin/env bash
# Live drive: real fm-watch.sh in a lab home, suspended with SIGSTOP (lid close), beacon aged, then a real re-arm.
# usage: fm-sleep-live.sh <bin-root> <label> <mode: seam-recent|seam-stalled|real-probe>
set -u
ROOTDIR=$1 LABEL=$2 MODE=$3
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$ROOTDIR/bin/fm-lab-home.sh" create "$LAB" >/dev/null 2>&1 || bin/fm-lab-home.sh create "$LAB" >/dev/null
E="env -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u FM_TEST_SYSTEM_WAKE_EPOCH -u FM_TEST_SEAM FM_HOME=$LAB"
echo "== [$LABEL] lab=$LAB bin=$ROOTDIR mode=$MODE"
$E "$ROOTDIR/bin/fm-watch-arm.sh" > "$LAB/arm1.out" 2>&1 &
ARM1=$!
for i in $(seq 1 100); do grep -q 'watcher:' "$LAB/arm1.out" && break; sleep 0.2; done
echo "first arm: $(cat "$LAB/arm1.out")"
WPID=$(cat "$LAB/state/.watch.lock/pid")
echo "watcher pid=$WPID ($(ps -o command= -p "$WPID"))"
kill -STOP "$WPID"; echo "lid closed: SIGSTOP watcher pid=$WPID (state $(ps -o stat= -p "$WPID"))"
now=$(date +%s)
touch -t "$(date -r $((now-900)) +%Y%m%d%H%M.%S)" "$LAB/state/.last-watcher-beat"
echo "beacon mtime now $(stat -f %Sm "$LAB/state/.last-watcher-beat") (wall-clock age ~900s; grace default 300s)"
case "$MODE" in
  seam-recent) X="FM_TEST_SEAM=1 FM_TEST_SYSTEM_WAKE_EPOCH=$((now-5))"; echo "host wake pinned to now-5s" ;;
  seam-stalled) X="FM_TEST_SEAM=1 FM_TEST_SYSTEM_WAKE_EPOCH=$((now-400))"; echo "host wake pinned to now-400s (> grace ago)" ;;
  real-probe) X=""; echo "host wake from real kern.waketime: $(sysctl -n kern.waketime)" ;;
esac
$E $X FM_ARM_CONFIRM_TIMEOUT=5 "$ROOTDIR/bin/fm-watch-arm.sh" > "$LAB/arm2.out" 2>&1 &
ARM2=$!
for i in $(seq 1 60); do grep -q 'watcher:' "$LAB/arm2.out" && break; kill -0 $ARM2 2>/dev/null || break; sleep 0.25; done
sleep 1
echo "re-arm output: $(cat "$LAB/arm2.out")"
if kill -0 $ARM2 2>/dev/null; then echo "re-arm still running (following watcher)"; else wait $ARM2; echo "re-arm exited rc=$?"; fi
kill -CONT "$WPID"; echo "lid opened: SIGCONT watcher"
sleep 2
echo "watcher alive after resume: $(kill -0 $WPID 2>/dev/null && echo yes || echo no)"
kill -TERM $ARM2 $ARM1 2>/dev/null; kill -TERM "$WPID" 2>/dev/null; sleep 1
pkill -f "$LAB" 2>/dev/null
rm -rf "$LAB"; echo "lab removed"
