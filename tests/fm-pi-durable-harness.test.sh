#!/usr/bin/env bash
# Portable regression for the opt-in pi-durable pilot adapter. The live facts
# (real host, real model, crash and relaunch) are refreshed by
# fm-pi-durable-signals-live-e2e.test.sh; this suite needs no network, no
# model server, and no pi-durable install.
set -u
# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"
# shellcheck source=bin/fm-control-lib.sh
. "$ROOT/bin/fm-control-lib.sh"
# shellcheck source=bin/fm-busy-lib.sh
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=bin/fm-composer-lib.sh
. "$ROOT/bin/fm-composer-lib.sh"
# shellcheck source=bin/fm-agent-process-lib.sh
. "$ROOT/bin/fm-agent-process-lib.sh"
TMP_ROOT=$(fm_test_tmproot fm-pi-durable-harness)
HARNESS="$ROOT/bin/fm-harness.sh"
# GNU `stat -f` succeeds with filesystem status, so pick the dialect by kernel
# rather than falling back on failure.
file_mode() {
  if [ "$(uname)" = Darwin ]; then /usr/bin/stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}
unset CLAUDECODE PI_CODING_AGENT GROK_AGENT CURSOR_AGENT CURSOR_INVOKED_AS GEMINI_CLI FM_OMP_HARNESS FM_PI_HARNESS ATLASSIAN_AGENT_TYPE ROVODEV_CLI

# Identity: a real process named pi-durable is the adapter, by its own name
# and by argv[0] alone (Linux keeps comm=node for the real host), while a
# neighbouring name is not.
mkdir -p "$TMP_ROOT/names"
for name in pi-durable pi-durable-helper; do ln -s /bin/bash "$TMP_ROOT/names/$name"; done
# shellcheck disable=SC2016
out=$(CLAUDECODE=1 "$TMP_ROOT/names/pi-durable" -c '"$1"; :' _ "$HARNESS")
[ "$out" = pi-durable ] || fail "pi-durable ancestry must beat a foreign CLAUDECODE: $out"
# shellcheck disable=SC2016
out=$("$TMP_ROOT/names/pi-durable-helper" -c '"$1" ancestry "$$"; :' _ "$HARNESS")
[ "$out" != 'comm pi-durable' ] || fail 'pi-durable-helper claimed the adapter'
[ "$(fm_agent_process_classify node pi-durable 'pi-durable /x/bin/pi-durable/host.mjs')" = agent ] \
  || fail 'liveness lost the host when only argv[0] names it'
[ "$(fm_agent_process_classify_name pi-durable-helper)" = other ] || fail 'liveness claims an unrelated name'
[ "$(fm_agent_process_classify node node '/x/bin/pi-durable/host.mjs')" = other ] \
  || fail 'a bare node process claimed the adapter from its script path'
pass "pi-durable identity from name or argv[0]; anchored liveness"

[ "$(fm_control_harness_family pi-durable)" = pi-durable ] || fail 'family must be exact, never pi'
[ "$(fm_control_interrupt_key pi-durable)" = Escape ] || fail 'wrong interrupt key'
[ "$(fm_control_interrupt_repeat pi-durable)" = 1 ] || fail 'one Escape interrupts'
[ -z "$(fm_control_interrupt_clear_key pi-durable)" ] || fail 'no clear key'
[ "$(fm_control_exit_command pi-durable)" = /quit ] || fail 'wrong exit command'
[ -z "$(fm_control_harness_wiring_paths pi-durable /unused /state worker)" ] \
  || fail 'a relaunch away must never retire the pilot store'
fm_control_harness_supports_kind pi-durable ship || fail 'ship refused'
fm_control_harness_supports_kind pi-durable scout || fail 'scout refused'
! fm_control_harness_supports_kind pi-durable secondmate || fail 'secondmate accepted'
pass "worker-only lifecycle capabilities; the store is not relaunch wiring"

[ "$(fm_composer_classify_content 0 '⟫')" = empty ] || fail 'pi-durable glyph not recognized'
[ "$(fm_composer_classify_content 0 '⟫ unsubmitted draft')" = pending ] || fail 'typed draft not preserved'
! printf '⟫ working\n' | fm_busy_lines_match pi-durable || fail 'pi-durable borrowed a rendered busy signal'
pass "composer glyph and draft safety"

state="$TMP_ROOT/busy state"
mkdir -p "$state"
gen=$("$ROOT/bin/fm-busy-event.sh" arm "$state" worker)
"$ROOT/bin/fm-busy-event.sh" apply "$state" worker busy --gen "$gen" --source pi-durable-host --event run-start
[ "$(fm_busy_classify tmux fake:w pi-durable worker "$state")" = 'busy pi-durable-host' ] || fail 'run-start did not open busy'
"$ROOT/bin/fm-busy-event.sh" apply "$state" worker idle --gen "$gen" --source pi-durable-host --event run-end
[ "$(fm_busy_classify tmux fake:w pi-durable worker "$state")" = 'idle pi-durable-host' ] || fail 'run-end did not settle'
"$ROOT/bin/fm-busy-event.sh" apply "$state" worker busy --gen "$gen" --source pi-ext --event agent-start
case "$(fm_busy_classify tmux fake:w pi-durable worker "$state")" in
  unknown*) ;;
  *) fail 'a Pi CLI extension source classified the pilot' ;;
esac
pass "busy source pi-durable-host is trusted only for pi-durable"

# Runtime ownership: without a matching install, check and launch refuse.
rt_state="$TMP_ROOT/rt-state"
mkdir -p "$rt_state"
if out=$("$ROOT/bin/fm-pi-durable.sh" check --state "$rt_state" 2>&1); then fail 'check passed with no install'; fi
assert_contains "$out" 'fm-pi-durable.sh install' 'check did not name the install command'
if out=$("$ROOT/bin/fm-pi-durable.sh" launch --state "$rt_state" -- --model x/y 2>&1); then fail 'launch ran with no install'; fi
fakebin=$(fm_fakebin "$TMP_ROOT/oldnode")
printf '#!/bin/sh\necho v22.18.9\n' > "$fakebin/node"
chmod +x "$fakebin/node"
if out=$(PATH="$fakebin:$PATH" "$ROOT/bin/fm-pi-durable.sh" check --state "$rt_state" 2>&1); then fail 'Node below the floor passed'; fi
assert_contains "$out" 'below the required 22.19.0' 'Node floor refusal missing'
pass "runtime check and launch refuse without a matching install or the Node floor"

if ! command -v node >/dev/null 2>&1; then
  printf 'skip: spawn launch shape: node is not installed\n'
  exit 0
fi
# A stand-in install: the exact tracked lock, its digest, and a loader that
# serves empty modules, which is all `host.mjs --check` reads. The floor is
# answered by a wrapper so CI's older Node still runs the real host file.
case_dir="$TMP_ROOT/spawn"
home="$case_dir/home"
proj="$case_dir/project"
wt="$case_dir/wt"
fm_test_spawn_home "$home"
runtime="$home/state/pi-durable-runtime"
mkdir -p "$runtime"
cp "$ROOT/bin/pi-durable/package-lock.json" "$runtime/"
shasum -a 256 "$ROOT/bin/pi-durable/package-lock.json" | awk '{print $1}' > "$runtime/.fm-lock-sha256"
printf 'export const load = async () => ({});\n' > "$runtime/load.mjs"
fakebin=$(make_spawn_fakebin "$case_dir/fake")
real_node=$(command -v node)
# shellcheck disable=SC2016
printf '#!/bin/sh\n[ "$1" = --version ] && { echo v22.19.0; exit 0; }\nexec "%s" "$@"\n' "$real_node" > "$fakebin/node"
chmod +x "$fakebin/node"
PATH="$fakebin:$PATH" "$ROOT/bin/fm-pi-durable.sh" check --state "$home/state" >/dev/null || fail 'stand-in install did not pass check'
fm_git_worktree "$proj" "$wt" pd-test
fm_test_spawn_brief "$home" pd-worker
fm_test_spawn_brief "$home" pd-nomodel
fm_test_spawn_brief "$home" pd-bare
if out=$(fm_test_run_spawn "$home" "$wt" "$fakebin" pd-nomodel "$proj" --scout --harness pi-durable 2>&1); then
  fail 'spawn without a model was accepted'
fi
assert_contains "$out" 'pi-durable needs --model <provider>/<id>' 'wrong no-model refusal'
assert_absent "$home/state/pd-nomodel.meta" 'a refused spawn left a task record'
if out=$(fm_test_run_spawn "$home" "$wt" "$fakebin" pd-bare "$proj" --scout --harness pi-durable --model qwen-fast 2>&1); then
  fail 'spawn with a bare model id was accepted'
fi
assert_contains "$out" 'pi-durable needs --model <provider>/<id>' 'wrong bare-model refusal'
if ! out=$(FM_FAKE_LAUNCH_LOG="$case_dir/launch" fm_test_run_spawn "$home" "$wt" "$fakebin" pd-worker "$proj" --scout --harness pi-durable --model ollama/qwen-fast --effort high 2>&1)
then fail "spawn failed: $out"; fi
launch=$(cat "$case_dir/launch")
assert_contains "$launch" "bin/fm-pi-durable.sh' launch --state '$home/state' --" 'launch does not go through the runtime owner'
assert_contains "$launch" "--store '$home/state/pd-worker.pi-durable'" 'per-task store missing'
assert_contains "$launch" "--model 'ollama/qwen-fast'" 'model lost'
assert_contains "$launch" "--busy-id 'pd-worker'" 'busy wiring missing'
assert_contains "$launch" "--turnend '$home/state/pd-worker.turn-ended'" 'turn-end wiring missing'
assert_contains "$launch" 'encode launch-brief' 'typed launch envelope lost'
case "$launch" in *--effort*|*--thinking*) fail 'the effort axis reached the host argv' ;; esac
assert_grep 'effort=high' "$home/state/pd-worker.meta" 'effort not recorded'
assert_grep 'harness=pi-durable' "$home/state/pd-worker.meta" 'harness not recorded exactly'
mode=$(file_mode "$home/state/pd-worker.pi-durable")
[ "$mode" = 700 ] || fail "store directory mode is $mode, not 700"
[ "$(fm_busy_classify tmux fake:w pi-durable pd-worker "$home/state")" = 'busy fm-spawn' ] || fail 'launch not armed'
if out=$(fm_test_run_spawn "$home" "$wt" "$fakebin" pd-sm "$proj" --secondmate --harness pi-durable 2>&1)
then fail 'pi-durable secondmate launch accepted'; fi
assert_contains "$out" 'crewmate/scout adapter only' 'wrong secondmate refusal'
pass "scout launch: runtime owner, owner-only store, model, busy wiring; effort recorded only; refusals"
