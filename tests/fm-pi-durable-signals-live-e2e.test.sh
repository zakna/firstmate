#!/usr/bin/env bash
# Live guard for the opt-in pi-durable pilot worker. Opt in with
# FM_PI_DURABLE_SIGNALS_LIVE=1; it submits prompts to a local OpenAI-compatible
# server. FM_PI_DURABLE_BASE_URL (default http://localhost:11434/v1) and
# FM_PI_DURABLE_MODEL (default qwen-fast) choose the server and model.
# Runs the real fm-spawn launch command in a private tmux server against a
# private home whose pinned runtime is installed by bin/fm-pi-durable.sh.
# Only worktree allocation and initial endpoint delivery use fixtures; every
# later steer, interrupt, relaunch, and exit goes through the real control plane.
# A recording proxy sits between the host and the server, so the guard can
# prove which request options the declared compat flags allowed through.
set -u
# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"
fm_live_gate opt-in FM_PI_DURABLE_SIGNALS_LIVE node npm tmux jq sqlite3 curl
REAL_TMUX=$(command -v tmux)
BASE_URL=${FM_PI_DURABLE_BASE_URL:-http://localhost:11434/v1}
MODEL_ID=${FM_PI_DURABLE_MODEL:-qwen-fast}
NODE_VERSION=$(node --version)
VERSION="pi-durable $(jq -r '.packages["node_modules/@earendil-works/pi-durable"].version' "$ROOT/bin/pi-durable/package-lock.json") on node $NODE_VERSION, $MODEL_ID"
if ! curl -fsS -m 5 "$BASE_URL/models" >/dev/null 2>&1; then
  printf 'not ok - %s: no OpenAI-compatible server answers at %s\n' "$VERSION" "$BASE_URL" >&2
  exit 1
fi
LAB=$(mktemp -d "${TMPDIR:-/tmp}/pd.XXXXXX")
LAB=$(cd "$LAB" && pwd -P)
SOCKET="$LAB/tmux.sock"
case "$SOCKET" in "$PWD"/*) SOCKET=${SOCKET#"$PWD"/} ;; esac
PROXY_PID=
cleanup() {
  "$REAL_TMUX" -S "$SOCKET" kill-server >/dev/null 2>&1 || true
  [ -z "$PROXY_PID" ] || kill "$PROXY_PID" 2>/dev/null || true
  # The spawn leaves its commit-msg hook directory read-only.
  chmod -R u+w "$LAB" 2>/dev/null || true
  rm -rf "$LAB"
}
if [ "${FM_PI_DURABLE_KEEP_LAB:-0}" = 1 ]; then
  printf 'lab: %s\n' "$LAB" >&2
else
  trap cleanup EXIT
fi
fail() { printf 'not ok - %s: %s\n' "$VERSION" "$1" >&2; exit 1; }
# shellcheck source=bin/fm-busy-lib.sh
. "$ROOT/bin/fm-busy-lib.sh"
# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"
# shellcheck source=bin/fm-composer-lib.sh
. "$ROOT/bin/fm-composer-lib.sh"
# shellcheck source=bin/fm-task-inbox-lib.sh
. "$ROOT/bin/fm-task-inbox-lib.sh"
H="$LAB/home"
WT="$LAB/wt"
PROJ="$LAB/project"
ID=pd-live
STORE="$H/state/$ID.pi-durable"
fm_test_spawn_home "$H" pi-durable
fm_git_worktree "$PROJ" "$WT" pd-live
git -C "$WT" config user.name 'Pi Durable Live Guard'
git -C "$WT" config user.email pi-durable-live-guard@example.invalid
"$ROOT/bin/fm-pi-durable.sh" install --state "$H/state" > "$LAB/install.log" 2>&1 \
  || fail "runtime install failed: $(cat "$LAB/install.log")"

# The recording proxy: forwards every request to the real server and logs each
# request body, so the declared compat flags are checked on the wire.
cat > "$LAB/proxy.mjs" <<'EOF'
import { createServer } from "node:http";
import { appendFileSync, writeFileSync } from "node:fs";
const [upstream, log, portFile] = process.argv.slice(2);
const server = createServer(async (req, res) => {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = Buffer.concat(chunks);
  if (body.length) appendFileSync(log, body.toString("utf8").replace(/\n/g, " ") + "\n");
  try {
    const headers = { ...req.headers };
    delete headers.host;
    delete headers["content-length"];
    const reply = await fetch(upstream + req.url.replace(/^\/v1/, ""), { method: req.method, headers, body: body.length ? body : undefined });
    res.writeHead(reply.status, Object.fromEntries(reply.headers));
    if (reply.body) for await (const chunk of reply.body) res.write(chunk);
    res.end();
  } catch (error) {
    res.writeHead(502);
    res.end(String(error));
  }
});
server.listen(0, "127.0.0.1", () => writeFileSync(portFile, String(server.address().port)));
EOF
node "$LAB/proxy.mjs" "$BASE_URL" "$LAB/requests.jsonl" "$LAB/proxy.port" &
PROXY_PID=$!
for _ in $(seq 1 50); do [ -s "$LAB/proxy.port" ] && break; sleep 0.1; done
[ -s "$LAB/proxy.port" ] || fail 'recording proxy did not start'
PROXY_URL="http://127.0.0.1:$(cat "$LAB/proxy.port")/v1"
mkdir -p "$H/user-home/.pi/agent"
jq -n --arg url "$PROXY_URL" --arg id "$MODEL_ID" '{providers: {ollama: {
  baseUrl: $url, api: "openai-completions", apiKey: "ollama",
  compat: {supportsDeveloperRole: false, supportsReasoningEffort: false},
  models: [{id: $id, name: $id, reasoning: true, input: ["text"], contextWindow: 131072, maxTokens: 16384}]}}}' \
  > "$H/user-home/.pi/agent/models.json"

# 7 and 8. The host refuses what it cannot carry faithfully: an OAuth provider
# with no credential bridge, and a thinking level it does not translate.
refuse() {  # <expected> <host args...>
  local expected=$1 out
  shift
  if out=$(HOME="$H/user-home" "$ROOT/bin/fm-pi-durable.sh" launch --state "$H/state" -- --store "$LAB/refused" --cwd "$WT" \
    --models-json "$H/user-home/.pi/agent/models.json" "$@" < /dev/null 2>&1); then
    fail "host accepted $*"
  fi
  assert_contains "$out" "$expected" "wrong refusal for $*"
}
refuse 'no credential bridge' --model openai-codex/gpt-5.5
refuse 'no credential bridge' --model github-copilot/gpt-5.5
refuse 'not declared under provider ollama' --model ollama/absent-model
refuse '--thinking is not supported' --model "ollama/$MODEL_ID" --thinking high
[ ! -e "$LAB/refused" ] || fail 'a refused launch created a store'
pass "$VERSION: OAuth providers, undeclared models, and thinking levels are refused before any store exists"

fm_test_spawn_brief "$H" "$ID" "Runtime verification only. First use your read tool on README.md. Then use your bash tool to run exactly: echo \$((12345 + 67890)) > answer.txt; '$ROOT/bin/fm-harness.sh' > harness.txt . Then reply with the single word DONE. Do no other work."
fakebin=$(make_spawn_fakebin "$LAB/fake")
FM_FAKE_LAUNCH_LOG="$LAB/launch.sh" fm_test_run_spawn "$H" "$WT" "$fakebin" "$ID" "$PROJ" \
  --scout --harness pi-durable --model "ollama/$MODEL_ID" --effort high > "$LAB/spawn.log" 2>&1 \
  || fail "fm-spawn failed: $(cat "$LAB/spawn.log")"
grep -q -- '--thinking\|--effort' "$LAB/launch.sh" && fail 'the effort axis reached the host argv'
printf '#!/bin/sh\nexec "%s" -S "%s" "$@"\n' "$REAL_TMUX" "$SOCKET" > "$LAB/bin-tmux"
mkdir -p "$LAB/bin" && mv "$LAB/bin-tmux" "$LAB/bin/tmux" && chmod +x "$LAB/bin/tmux"
export PATH="$LAB/bin:$PATH" FM_HOME="$H"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
TARGET="firstmate:fm-$ID"
# The pane's own HOME, not just the first launch's, so a relaunch typed into
# its shell also reads the lab models.json and talks through the proxy.
"$REAL_TMUX" -S "$SOCKET" new-session -d -s firstmate -n "fm-$ID" -x 140 -y 45 -c "$WT" -e "HOME=$H/user-home" \
  "/bin/sh '$LAB/launch.sh'; exec /bin/bash --noprofile --norc" || fail 'could not start pane'
capture() { "$REAL_TMUX" -S "$SOCKET" capture-pane -p -e -t "$TARGET"; }
screen_text() { "$REAL_TMUX" -S "$SOCKET" capture-pane -p -S -200 -t "$TARGET"; }
busy_state() { fm_busy_classify tmux "$TARGET" pi-durable "$ID" "$H/state"; }
wait_file() {
  local path=$1 i
  for i in $(seq 1 360); do [ -s "$path" ] && return 0; sleep 0.5; done
  fail "timed out waiting for ${path##*/}: $(screen_text | tail -15)"
}
wait_busy() {
  local i
  for i in $(seq 1 240); do
    [ "$(busy_state)" = 'busy pi-durable-host' ] && return 0
    sleep 0.25
  done
  fail "no semantic busy (last: $(busy_state))"
}
wait_idle() {
  local i
  for i in $(seq 1 480); do
    [ "$(busy_state)" = 'idle pi-durable-host' ] && return 0
    sleep 0.5
  done
  fail "run did not settle idle (last: $(busy_state)): $(screen_text | tail -15)"
}
host_pid() {
  local tty
  tty=$("$REAL_TMUX" -S "$SOCKET" display-message -p -t "$TARGET" '#{pane_tty}')
  ps -t "${tty#/dev/}" -o pid=,args= | awk '$2 == "pi-durable" { print $1 }'
}
entries() { sqlite3 "file:$STORE/conversation.sqlite?mode=ro" 'select count(*) from entries'; }

# 1. Start, stream, complete; and 6. the busy and settled transitions.
wait_busy
wait_file "$WT/answer.txt"
wait_file "$WT/harness.txt"
[ "$(tr -d '[:space:]' < "$WT/answer.txt")" = 80235 ] || fail 'launch brief did not execute'
[ "$(tr -d '[:space:]' < "$WT/harness.txt")" = pi-durable ] || fail "tool ancestry did not identify pi-durable: $(cat "$WT/harness.txt")"
wait_idle
screen_text | grep -q 'DONE' || fail "the final answer was not streamed to the pane: $(screen_text | tail -10)"
[ -f "$H/state/$ID.turn-ended" ] || fail 'no turn-end notification'
[ "$(fm_backend_agent_state tmux "$TARGET")" = alive ] || fail 'the host process is not classified alive'
grep -q '"name":"read"\|"read"' "$LAB/requests.jsonl" || fail 'no request offered the read tool'
pass "$VERSION: spawn brief, safe read tool, bash tool, identity, streamed answer, busy then idle"

# 8. The declared compat flags keep unsupported options off the wire.
! grep -q '"role":"developer"' "$LAB/requests.jsonl" || fail 'a developer-role message reached the server'
! grep -q '"reasoning_effort"' "$LAB/requests.jsonl" || fail 'reasoning_effort reached the server'
pass "$VERSION: no developer role and no reasoning_effort in $(wc -l < "$LAB/requests.jsonl" | tr -d ' ') requests"

# 9. Store permissions. GNU `stat -f` succeeds with filesystem status, so pick
# the dialect by kernel rather than falling back on failure.
file_mode() {
  if [ "$(uname)" = Darwin ]; then /usr/bin/stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}
[ "$(file_mode "$STORE")" = 700 ] || fail 'store directory is not 0700'
for f in "$STORE"/*; do
  mode=$(file_mode "$f")
  [ "$mode" = 600 ] || fail "store file ${f##*/} is mode $mode, not 0600"
done
pass "$VERSION: store is owner-only"

verdict=$(fm_composer_classify_screen $'styled=1\ncursor=1\nidentity=1\nrows=0' "$(capture)" \
  "$("$REAL_TMUX" -S "$SOCKET" display-message -p -t "$TARGET" '#{cursor_y}')" pi-durable)
case "$verdict" in empty*) ;; *) fail "idle composer was $verdict" ;; esac

# 4. A steer delivered while busy arrives once, in order.
"$ROOT/bin/fm-send.sh" "$ID" 'Runtime verification: run exactly this shell command now and wait for it: sleep 20' > "$LAB/send1.log" 2>&1 \
  || fail "first steer failed: $(cat "$LAB/send1.log")"
wait_busy
for _ in $(seq 1 120); do screen_text | grep -q 'sleep 20' && break; sleep 0.5; done
"$ROOT/bin/fm-send.sh" "$ID" "Runtime steering verification: run exactly this shell command once: echo STEERED >> '$WT/steer.txt' . Then stop. Do no other work." > "$LAB/send2.log" 2>&1 \
  || fail "busy steer failed: $(cat "$LAB/send2.log")"
# The host acknowledges once the steer is placed. Restoring the record models a
# crash between placement and that move; the re-rung doorbell must not admit it again.
wait_file "$H/state/$ID.inbox/handled/002.msg"
cp "$H/state/$ID.inbox/handled/002.msg" "$H/state/$ID.inbox/002.msg"
"$REAL_TMUX" -S "$SOCKET" send-keys -t "$TARGET" -l "$(fm_task_inbox_doorbell_line "$H/state/$ID.inbox/002.msg")"
"$REAL_TMUX" -S "$SOCKET" send-keys -t "$TARGET" Enter
wait_file "$WT/steer.txt"
for _ in $(seq 1 60); do [ ! -e "$H/state/$ID.inbox/002.msg" ] && break; sleep 0.5; done
[ ! -e "$H/state/$ID.inbox/002.msg" ] || fail 'the restored record was not acknowledged again'
wait_idle
bells=$(sqlite3 "file:$STORE/conversation.sqlite?mode=ro" "select count(*) from entries where record like '%Firstmate instruction waiting%'")
[ "$bells" = 0 ] || fail "$bells doorbell lines reached the conversation"
[ "$(grep -c STEERED "$WT/steer.txt")" = 1 ] || fail "the steer ran $(grep -c STEERED "$WT/steer.txt") times"
admitted=$(sqlite3 "file:$STORE/conversation.sqlite?mode=ro" "select count(*) from submissions where record like '%fm-inbox:002.msg:%'")
[ "$admitted" = 1 ] || fail "message 002 was admitted $admitted times"
pass "$VERSION: fm-send while busy admitted and acknowledged by the host, once despite a replayed record and re-ring, ran once"

# 6. Interrupt cancels a running tool and settles idle.
"$ROOT/bin/fm-send.sh" "$ID" "Runtime interrupt verification: run exactly this shell command and wait for it: sleep 90; echo late >> '$WT/late.txt'" > "$LAB/send3.log" 2>&1 || fail 'could not steer interrupt probe'
wait_busy
for _ in $(seq 1 120); do screen_text | grep -q 'sleep 90' && break; sleep 0.5; done
"$ROOT/bin/fm-control.sh" "$ID" interrupt > "$LAB/interrupt.log" 2>&1 || fail "interrupt failed: $(cat "$LAB/interrupt.log")"
wait_idle
screen_text | grep -q 'interrupted' || fail 'interrupt did not render'
[ "$(fm_backend_agent_state tmux "$TARGET")" = alive ] || fail 'interrupt killed the host'
sleep 2
[ ! -e "$WT/late.txt" ] || fail 'the interrupted command kept running'
pass "$VERSION: Escape aborts the running tool and the host stays alive"

# 3. A crash mid side-effecting tool never runs that call again, and
# 5. relaunch through fm-control reopens the same store and resumes the run.
"$ROOT/bin/fm-send.sh" "$ID" "Runtime crash verification: run exactly this shell command once: echo start >> '$WT/side.txt'; sleep 15 . If that command is reported as interrupted, do not run it again; instead run exactly: echo INTERRUPTED > '$WT/crash.txt' and stop." > "$LAB/send4.log" 2>&1 || fail 'could not steer crash probe'
wait_file "$WT/side.txt"
before=$(entries)
pid=$(host_pid)
[ -n "$pid" ] || fail 'could not find the host process'
kill -9 "$pid"
for _ in $(seq 1 40); do [ "$(fm_backend_agent_state tmux "$TARGET")" = dead ] && break; sleep 0.25; done
[ "$(fm_backend_agent_state tmux "$TARGET")" = dead ] || fail 'killed host still classified alive'
"$ROOT/bin/fm-control.sh" "$ID" relaunch --note "The host was killed mid-command; the reopened store continues the run." > "$LAB/relaunch.log" 2>&1 || fail "relaunch failed: $(cat "$LAB/relaunch.log")"
TARGET=$(sed -n 's/^window=//p' "$H/state/$ID.meta")
# The relaunch note carries a recap of the killed pane; the doorbell lines rung
# into that pane must not reach the model through it.
for _ in $(seq 1 120); do
  [ "$(sqlite3 "file:$STORE/conversation.sqlite?mode=ro" "select count(*) from entries where record like '%Firstmate relaunched this worker%'")" = 1 ] && break
  sleep 0.5
done
bells=$(sqlite3 "file:$STORE/conversation.sqlite?mode=ro" "select count(*) from entries where record like '%Firstmate instruction waiting%'")
[ "$bells" = 0 ] || fail 'the relaunch recap handed doorbell lines to the model'
wait_file "$WT/crash.txt"
wait_idle
[ "$(grep -c start "$WT/side.txt")" = 1 ] || fail "the interrupted side-effecting call ran $(grep -c start "$WT/side.txt") times"
[ "$(entries)" -gt "$before" ] || fail 'the relaunch did not continue the same conversation'
[ "$(sed -n 's/^harness=//p' "$H/state/$ID.meta")" = pi-durable ] || fail 'relaunch changed the recorded harness'
pass "$VERSION: crash mid-tool is not replayed; relaunch reopens the same store ($before -> $(entries) entries)"

# 6. An endpoint error settles idle and the host survives it.
kill "$PROXY_PID" 2>/dev/null
wait "$PROXY_PID" 2>/dev/null
PROXY_PID=
endpoint_errors() { screen_text | grep -c 'input not answered\|retrying'; }
errors_before=$(endpoint_errors)
"$ROOT/bin/fm-send.sh" "$ID" 'Say OK.' > "$LAB/send5.log" 2>&1 || fail 'could not steer error probe'
for _ in $(seq 1 240); do [ "$(endpoint_errors)" -gt "$errors_before" ] && break; sleep 0.5; done
[ "$(endpoint_errors)" -gt "$errors_before" ] || fail "the endpoint failure was not rendered: $(screen_text | tail -8)"
[ "$(fm_backend_agent_state tmux "$TARGET")" = alive ] || fail 'the endpoint failure killed the host'
pass "$VERSION: endpoint failure is rendered and the host survives (state: $(busy_state))"

# 6. Exit stops the host and the pane returns to its shell.
"$ROOT/bin/fm-control.sh" "$ID" exit > "$LAB/exit.log" 2>&1 || fail "exit failed: $(cat "$LAB/exit.log")"
[ "$(fm_backend_agent_state tmux "$TARGET")" = dead ] || fail '/quit did not return to the shell'
pass "$VERSION: /quit stops the host"

# 10. Rollback: relaunching on the ordinary Pi adapter keeps the store.
if command -v pi >/dev/null 2>&1; then
  "$ROOT/bin/fm-control.sh" "$ID" relaunch --harness pi --note "Rollback check only: reply OK and stop." > "$LAB/rollback.log" 2>&1 \
    || fail "rollback relaunch failed: $(cat "$LAB/rollback.log")"
  [ "$(sed -n 's/^harness=//p' "$H/state/$ID.meta")" = pi ] || fail 'rollback did not record the pi harness'
  [ -s "$STORE/conversation.sqlite" ] || fail 'rollback removed the pilot store'
  [ "$(tr -d '[:space:]' < "$WT/answer.txt")" = 80235 ] || fail 'rollback touched the worktree'
  pass "$VERSION: rollback to pi keeps the pilot store and the worktree"
else
  printf 'skip: rollback: pi is not installed\n'
fi
