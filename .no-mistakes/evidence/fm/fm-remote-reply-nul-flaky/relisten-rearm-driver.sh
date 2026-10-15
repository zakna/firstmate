#!/usr/bin/env bash
# Behavior tests for the generic process-to-event runner and its Lavish adapter.
#
# The source under test is a fake blocking process that returns only when its
# trigger file appears, so completion is a real process event and no test here
# depends on a discovery timer. The Lavish adapter is exercised through its own
# public commands against the currently published poll shape; no live Lavish
# server is started.
#
# Delivery is deliberately NOT asserted as at-least-once or lossless: the
# published Lavish poll clears feedback destructively before returning it, so
# the only durability under test is the runner's own - output that reached the
# runner is stored before it is announced.
set -u

# shellcheck source=tests/lib.sh
. "/Users/olivier/.no-mistakes/worktrees/0b1ab7dd6182/01M50VAJ051H3R0W7CPGS0ET4R/tests/lib.sh"

ROOT="/Users/olivier/.no-mistakes/worktrees/0b1ab7dd6182/01M50VAJ051H3R0W7CPGS0ET4R"
TMP_ROOT=$(fm_test_tmproot fm-procevent-tests)
export FM_PROCEVENT_CLAIM_ROOT="$TMP_ROOT/claims"
export LAVISH_AXI_STATE_DIR="$TMP_ROOT/lavish-state"
mkdir -p "$LAVISH_AXI_STATE_DIR"

# Lavish owns this persisted session contract. The fake CLI fixtures exercise
# its published poll and synchronous reply command boundaries without starting a server.
lavish_session() {  # <artifact> [session-url]
  perl -MJSON::PP -MCwd=realpath -MDigest::SHA=sha256_hex -MEncode=decode -e '
    my ($path, $artifact, $url) = @ARGV;
    my $real = realpath($artifact) // die "missing fixture artifact";
    my $key = substr(sha256_hex($real), 0, 16);
    my $state = { sessions => {} };
    if (-f $path) { open my $in, "<", $path or die $!; local $/; $state = decode_json(<$in>); }
    $state->{sessions}{$key} = {
      key => $key, file => decode("UTF-8", $real), status => "open", url => $url,
    };
    open my $out, ">", $path or die $!;
    print $out encode_json($state);
  ' "$LAVISH_AXI_STATE_DIR/state.json" "$1" "${2:-http://127.0.0.1:14387/session/0123456789abcdef}"
}

BLOCKER="$TMP_ROOT/blocker.sh"
cat > "$BLOCKER" <<'SH'
#!/usr/bin/env bash
# Blocks until the trigger exists, then emits its payload. Completion is the
# event; nothing here polls on a schedule. The wait is bounded so a stub that
# escapes its test cannot keep spawning processes indefinitely.
trigger=$1; shift
while [ ! -e "$trigger" ]; do
  [ "$SECONDS" -lt "${FM_TEST_STUB_MAX_BLOCK_SECONDS:-120}" ] || exit 75
  sleep 0.05
done
[ -n "${BLOCKER_STDERR:-}" ] && printf 'noise on stderr\n' >&2
[ -n "${BLOCKER_EXIT:-}" ] && exit "$BLOCKER_EXIT"
printf '%s\n' "$@"
SH
chmod +x "$BLOCKER"

# Records that the wrapped command actually started, then becomes it. A claim
# only proves its runner got as far as claiming; a test that needs the runner
# already inside its source command waits for this marker instead of a settle
# window, because a runner still short of that command retires itself when its
# registration goes away.
STARTED_BLOCKER="$TMP_ROOT/started-blocker.sh"
cat > "$STARTED_BLOCKER" <<'SH'
#!/usr/bin/env bash
printf 'started\n' > "$1"
shift
exec "$@"
SH
chmod +x "$STARTED_BLOCKER"

pe() { FM_HOME="$1" "$ROOT/bin/fm-procevent.sh" "${@:2}"; }

# Every home this suite registers a source in is tracked so teardown can stop
# its runners. A runner started by reconcile is detached and reparented, so a
# source that never completes outlives the suite unless its home is swept -
# removing the fixture directory does not stop an already-running child.
# tests/lib.sh owns that sweep and runs it from every cleanup path.
pe_register() {  # <home> <adapter> <source-id> -- <argv>...
  local home=$1 adapter=$2 id=$3
  shift 3
  fm_test_track_procevent_home "$home"
  pe "$home" register "$adapter" "$id" "$@"
}
new_home() { mkdir -p "$1/state"; }
# A worker-owned board can only be armed for a task whose endpoint metadata the
# runner can ring, so every fixture worker needs the same durable record a real
# spawn leaves behind.
new_task_endpoint() {  # <home> <task-id>
  mkdir -p "$1/state"
  printf 'window=fmtest:fm-%s\nworktree=%s/worktree-%s\nproject=fmtest\n' "$2" "$1" "$2" \
    > "$1/state/$2.meta"
}
wake_payloads() { awk -F '\t' '{print $5}' "$1/state/.wake-queue" 2>/dev/null; }

# The wake queue is a durable tab-separated record firstmate consumes:
# <epoch> <sequence> <kind> <key> <payload>. These read the rows reconcile
# publishes for a source it stranded, keyed by that source and its claim
# generation.
stranded_wake_keys() {  # <home> <source-id>
  [ -e "$1/state/.wake-queue" ] || return 0
  awk -F '\t' -v id="$2" \
    '$3 == "check" && index($4, "procevent:" id ":stranded:") == 1 { print $4 }' \
    "$1/state/.wake-queue"
}
stranded_wake_count() {  # <home> <source-id>
  stranded_wake_keys "$1" "$2" | grep -c . || true
}
stranded_wake_payloads() {  # <home> <source-id>
  [ -e "$1/state/.wake-queue" ] || return 0
  awk -F '\t' -v id="$2" \
    '$3 == "check" && index($4, "procevent:" id ":stranded:") == 1 { print $5 }' \
    "$1/state/.wake-queue"
}
# The same rows for a launch reconcile could not confirm, keyed by that source
# and the registration identity the launch ran under.
launch_failed_wake_keys() {  # <home> <source-id>
  [ -e "$1/state/.wake-queue" ] || return 0
  awk -F '\t' -v id="$2" \
    '$3 == "check" && index($4, "procevent:" id ":launch-failed:") == 1 { print $4 }' \
    "$1/state/.wake-queue"
}
launch_failed_wake_count() {  # <home> <source-id>
  launch_failed_wake_keys "$1" "$2" | grep -c . || true
}
launch_failed_wake_payloads() {  # <home> <source-id>
  [ -e "$1/state/.wake-queue" ] || return 0
  awk -F '\t' -v id="$2" \
    '$3 == "check" && index($4, "procevent:" id ":launch-failed:") == 1 { print $5 }' \
    "$1/state/.wake-queue"
}

first_result() {  # <home> <source-id>: print the first captured result, if any
  local g
  for g in "$1/state/procevent-inbox/$2".*.result; do
    [ -e "$g" ] || continue
    printf '%s\n' "$g"
    return 0
  done
  return 1
}

count_results() {  # <home> <source-id>
  local g n=0
  for g in "$1/state/procevent-inbox/$2".*.result; do
    [ -e "$g" ] && n=$((n + 1))
  done
  printf '%s\n' "$n"
}

wait_for() {  # <file> [tries]
  local f=$1 n=${2:-100}
  for _ in $(seq 1 "$n"); do [ -s "$f" ] && return 0; sleep 0.1; done
  return 1
}

# Arm now starts the listener, so a later start would poll again. Wait for the
# capture that listener is already producing, and for its runner to release the
# claim: the result lands before the runner publishes and exits, and a retire or
# re-arm in that gap meets a live claim the synchronous start never left behind.
wait_capture() {  # <home> <source-id> [tries]
  local home=$1 id=$2 n=${3:-100}
  local _
  for _ in $(seq 1 "$n"); do
    if first_result "$home" "$id" >/dev/null 2>&1 \
      && [ ! -e "$FM_PROCEVENT_CLAIM_ROOT/$id.claim" ]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

# <file> <count> [tries]: wait until <file> holds at least <count> lines. A
# detached runner appends its execution marker after the command that started it
# has already returned, so a caller that needs that append must wait for it
# rather than assume a fixed settle window covered it on a loaded machine.
wait_for_lines() {
  local f=$1 want=$2 n=${3:-100} have
  for _ in $(seq 1 "$n"); do
    if [ -f "$f" ]; then
      have=$(wc -l < "$f" | tr -d ' ')
    else
      have=0
    fi
    case "$have" in ''|*[!0-9]*) have=0 ;; esac
    [ "$have" -ge "$want" ] && return 0
    sleep 0.1
  done
  return 1
}

hold_source_lock() {  # <source-id> <ready-file> <release-file>
  local id=$1 ready=$2 release=$3 parent=$$
  FM_HOME="$TMP_ROOT/lock-helper-home" bash -c '
    . "$1/bin/fm-pr-lib.sh"
    . "$1/bin/fm-wake-lib.sh"
    . "$1/bin/fm-procevent-lib.sh"
    fm_procevent_source_lock_acquire "$2" || exit 1
    trap "fm_procevent_source_lock_release \"$2\"" EXIT
    printf "ready\n" > "$3"
    while [ ! -e "$4" ]; do
      kill -0 "$5" 2>/dev/null || exit 0
      sleep 0.02
    done
  ' _ "$ROOT" "$id" "$ready" "$release" "$parent" &
  HOLDER_PID=$!
}

hold_source_lock_then_handle() {  # <home> <source-id> <sequence> <ready-file> <release-file>
  local home=$1 id=$2 seq=$3 ready=$4 release=$5 parent=$$
  FM_HOME="$home" bash -c '
    . "$1/bin/fm-pr-lib.sh"
    . "$1/bin/fm-wake-lib.sh"
    . "$1/bin/fm-procevent-lib.sh"
    fm_procevent_source_lock_acquire "$2" || exit 1
    trap "fm_procevent_source_lock_release \"$2\"" EXIT
    printf "ready\n" > "$4"
    while [ ! -e "$5" ]; do
      kill -0 "$6" 2>/dev/null || exit 1
      sleep 0.02
    done
    fm_procevent_mark_handled "$3/state" "$2" "$7"
  ' _ "$ROOT" "$id" "$home" "$ready" "$release" "$parent" "$seq" &
  HOLDER_PID=$!
}
# A relisten runner adopts a re-registration of its unchanged command whenever
# that re-arm lands, including while it sleeps out the launch floor after an
# empty window. Treating that re-arm as a superseding generation ended the only
# listener while it still looked live, so nothing polled until a reconcile.
HRELISTEN="$TMP_ROOT/relisten-rearm"; new_home "$HRELISTEN"
RELISTEN_LOG="$TMP_ROOT/relisten-rearm.log"
EMPTY_WINDOW_SOURCE="$TMP_ROOT/empty-window-source.sh"
cat > "$EMPTY_WINDOW_SOURCE" <<'SH'
#!/usr/bin/env bash
printf 'launch\n' >> "$1"
exit 75
SH
chmod +x "$EMPTY_WINDOW_SOURCE"
pe_register "$HRELISTEN" remote-reply relisten-src -- "$EMPTY_WINDOW_SOURCE" "$RELISTEN_LOG" >/dev/null
FM_PROCEVENT_LAUNCH_FLOOR_SECONDS=4 \
  pe "$HRELISTEN" start relisten-src > "$TMP_ROOT/relisten-rearm.out" 2>&1 &
RELISTEN_PID=$!
wait_for "$RELISTEN_LOG" || fail "the relisten fixture never launched its source"
# Re-arm only once the runner has adopted its unchanged registration and is
# sleeping on that generation's launch-pacing stamp, so the re-arm cannot be
# picked up by the relisten adoption that precedes the floor.
relisten_stamp_prefix=$(printf '%s' "$HRELISTEN/state/procevent/relisten-src." \
  | sed 's/[][\\.*^$+?(){}|]/\\&/g')
relisten_floor_waiting=0
for _ in $(seq 1 100); do
  if pgrep -f "$relisten_stamp_prefix.*\.last-launch" >/dev/null 2>&1; then
    relisten_floor_waiting=1
    break
  fi
  sleep 0.05
done
[ "$relisten_floor_waiting" = 1 ] || fail "the relisten fixture never waited on its launch floor"
pe_register "$HRELISTEN" remote-reply relisten-src -- "$EMPTY_WINDOW_SOURCE" "$RELISTEN_LOG" >/dev/null
for _ in $(seq 1 100); do
  [ "$(wc -l < "$RELISTEN_LOG" | tr -d ' ')" -ge 2 ] && break
  kill -0 "$RELISTEN_PID" 2>/dev/null || break
  sleep 0.1
done
[ "$(wc -l < "$RELISTEN_LOG" | tr -d ' ')" -ge 2 ] \
  || fail "re-arming an unchanged relisten command during its launch floor ended the listener: $(cat "$TMP_ROOT/relisten-rearm.out")"
pe "$HRELISTEN" list | awk '$1 == "relisten-src" { print $3 }' | grep -qx live \
  || fail "the relisten runner did not keep the re-armed source"
pe "$HRELISTEN" retire relisten-src >/dev/null
wait "$RELISTEN_PID" 2>/dev/null || true
pass "a relisten runner adopts an unchanged re-arm that lands during its launch floor"
printf "
relisten regression passed
"
