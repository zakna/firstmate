#!/usr/bin/env bash
# Drive bin/fm-watch-checkpoint.sh (from a given git rev) with a watcher stand-in
# that ignores TERM; report wall time, exit status, and whether the watcher survived.
set -u
REPO=$1 REV=$2
W=$(mktemp -d "${TMPDIR:-/tmp}/fm-ckpt-drive.XXXXXX")
mkdir -p "$W/home/state" "$W/home/data" "$W/home/config" "$W/root/bin"
for f in fm-watch-checkpoint.sh fm-supervision-engine-lib.sh fm-timeout-lib.sh; do
  git -C "$REPO" show "$REV:bin/$f" > "$W/root/bin/$f" 2>/dev/null || true
done
cat > "$W/root/bin/fm-watch.sh" <<'SH'
#!/usr/bin/env bash
trap '' TERM
printf '%s\n' "$$" > "$FM_HOME/stub-pid"
while :; do sleep 0.2; done
SH
chmod +x "$W/root/bin/"*.sh
start=$(date +%s)
FM_HOME="$W/home" FM_SIGNAL_GRACE=1 "$W/root/bin/fm-watch-checkpoint.sh" --seconds 1 >"$W/out" 2>"$W/err" &
pid=$!
i=0; while kill -0 $pid 2>/dev/null && [ $i -lt 200 ]; do sleep 0.1; i=$((i+1)); done
stub=$(cat "$W/home/stub-pid" 2>/dev/null)
if kill -0 $pid 2>/dev/null; then
  echo "rev=$REV RESULT: checkpoint --seconds 1 STILL RUNNING after 20s (hang); watcher pid $stub alive=$(kill -0 $stub 2>/dev/null && echo yes || echo no)"
  pkill -KILL -P $pid 2>/dev/null; kill -KILL $pid $stub 2>/dev/null; wait $pid 2>/dev/null
else
  wait $pid; rc=$?
  echo "rev=$REV RESULT: checkpoint --seconds 1 exited rc=$rc after $(( $(date +%s)-start ))s; watcher pid $stub alive=$(kill -0 $stub 2>/dev/null && echo yes || echo no)"
  echo "  stdout: $(cat "$W/out")"
fi
pkill -KILL -f "$W/root/bin/fm-watch.sh" 2>/dev/null
rm -rf "$W"
