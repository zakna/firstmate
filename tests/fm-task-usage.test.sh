#!/usr/bin/env bash
# tests/fm-task-usage.test.sh - bin/fm-task-usage.sh: a task worker's token
# usage read from fixture Claude transcripts, and the per-task and per-project
# report over a fixture fleet ledger. The cleanup record written through the
# real teardown is covered in tests/fm-fleet-ledger.test.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-task-usage)
USAGE="$ROOT/bin/fm-task-usage.sh"
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%S.123Z)
NOW=$(date +%s)

# Sets CASE_DIR WT CLAUDE_ROOT TDIR META for one isolated case.
make_case() {  # <name>
  CASE_DIR="$TMP_ROOT/$1"
  WT="$CASE_DIR/wt"
  CLAUDE_ROOT="$CASE_DIR/claude"
  mkdir -p "$WT" "$CASE_DIR/state"
  WT=$(cd "$WT" && pwd -P)
  TDIR="$CLAUDE_ROOT/projects/$(printf '%s' "$WT" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$TDIR"
  META="$CASE_DIR/state/$1.meta"
  printf 'worktree=%s\nharness=claude\nkind=ship\nclaude_root=%s\nspawn_gen=s%s.1.2\n' \
    "$WT" "$CLAUDE_ROOT" "$((NOW - 60))" > "$META"
}

# One assistant transcript line.
msg() {  # <session> <message-id> <model> <input> <output> <cache-write> <cache-read> [<timestamp>] [<cwd>] [<extra-json>]
  local extra=${10:-}
  [ -n "$extra" ] || extra='{}'
  jq -cn --arg s "$1" --arg id "$2" --arg m "$3" --argjson i "$4" --argjson o "$5" \
    --argjson cw "$6" --argjson cr "$7" --arg ts "${8:-$NOW_ISO}" --arg cwd "${9:-$WT}" \
    --argjson extra "$extra" \
    '{type: "assistant", sessionId: $s, cwd: $cwd, timestamp: $ts, requestId: ("req-" + $id),
      message: {id: $id, model: $m, usage: {input_tokens: $i, output_tokens: $o,
        cache_creation_input_tokens: $cw, cache_read_input_tokens: $cr}}} + $extra'
}

read_usage() {  # [read args after the meta...]
  "$USAGE" read "$META" "$@"
}

test_dispatch_window_counts_each_response_once() {
  local out
  make_case window
  {
    printf '%s\n' '{"type":"user","sessionId":"s1","cwd":"'"$WT"'","message":{"content":"what is the usage?"}}'
    msg s1 m1 claude-opus-5-5 3 5 100 1000
    msg s1 m1 claude-opus-5-5 3 20 100 1000
    msg s1 m2 claude-sonnet-5-5 1 7 0 50
    msg s1 m3 '<synthetic>' 0 0 0 0
    msg s1 m4 claude-opus-5-5 900 900 900 900 2020-01-01T00:00:00.000Z
    msg s1 m5 claude-opus-5-5 800 800 800 800 "$NOW_ISO" /somewhere/else
    msg s1 m7 claude-opus-5-5 700 700 700 700 "$NOW_ISO" "$WT-sibling"
    msg s1 m8 claude-sonnet-5-5 4 6 0 0 "$NOW_ISO" "$WT/sub/dir"
    printf 'not json at all "usage"\n'
  } > "$TDIR/s1.jsonl"
  mkdir -p "$TDIR/s1/subagents"
  msg s1 m6 claude-haiku-5-5 2 4 10 0 > "$TDIR/s1/subagents/agent-a.jsonl"
  out=$(read_usage --since "$((NOW - 3600))") || fail "read exited non-zero"
  assert_equals "$(jq -cn --argjson since "$((NOW - 3600))" '{source: "claude-transcript", basis: "dispatch-window", since: $since,
    sessions: 1, messages: 4, input_tokens: 10, output_tokens: 37, cache_write_tokens: 110, cache_read_tokens: 1050,
    models: {"claude-haiku-5-5": {messages: 1, input_tokens: 2, output_tokens: 4, cache_write_tokens: 10, cache_read_tokens: 0},
      "claude-opus-5-5": {messages: 1, input_tokens: 3, output_tokens: 20, cache_write_tokens: 100, cache_read_tokens: 1000},
      "claude-sonnet-5-5": {messages: 2, input_tokens: 5, output_tokens: 13, cache_write_tokens: 0, cache_read_tokens: 50}}}')" \
    "$out" "dispatch-window usage"
  pass "dispatch window: repeated lines count once (last wins), subagents and subdirectory-cwd responses count, and synthetic, earlier, and other-cwd responses do not"
}

test_launch_window_falls_back_to_spawn_gen() {
  local out
  make_case launch
  {
    msg s1 m1 claude-opus-5-5 1 1 0 0 "$(date -u -r "$((NOW - 120))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((NOW - 120))" +%Y-%m-%dT%H:%M:%SZ)"
    msg s1 m2 claude-opus-5-5 2 3 0 0
  } > "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.basis, .since, .messages, .input_tokens]')
  assert_equals "[\"launch-window\",$((NOW - 60)),1,2]" "$out" "launch-window usage"
  pass "launch window: without a dispatch time, only responses since the record's spawn_gen count"
}

test_session_ids_read_exactly_the_named_sessions() {
  local out
  make_case sessions
  printf 'claude_session_id=bbbb-2\nclaude_prior_session_ids=aaaa-1\n' >> "$META"
  msg aaaa-1 m1 claude-opus-5-5 1 1 0 0 2020-01-01T00:00:00Z > "$TDIR/aaaa-1.jsonl"
  msg bbbb-2 m2 claude-opus-5-5 2 2 0 0 > "$TDIR/bbbb-2.jsonl"
  mkdir -p "$TDIR/bbbb-2/subagents"
  msg bbbb-2 m3 claude-opus-5-5 4 4 0 0 > "$TDIR/bbbb-2/subagents/agent-x.jsonl"
  msg cccc-3 m4 claude-opus-5-5 100 100 0 0 > "$TDIR/cccc-3.jsonl"
  out=$(read_usage --since "$NOW" | jq -c '[.basis, .since, .sessions, .messages, .input_tokens]')
  assert_equals '["session-ids",null,2,3,7]' "$out" "session-ids usage"
  pass "session ids: exactly the recorded sessions and their subagents count, whatever their age"
}

test_reported_cost_is_kept_only_when_every_response_has_one() {
  local out
  make_case cost
  {
    msg s1 m1 claude-opus-5-5 1 1 0 0 "$NOW_ISO" "$WT" '{"costUSD":0.25}'
    msg s1 m2 claude-opus-5-5 1 1 0 0 "$NOW_ISO" "$WT" '{"costUSD":0.5}'
  } > "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.cost_usd, .cost_source]')
  assert_equals '[0.75,"claude-transcript"]' "$out" "reported cost"
  msg s1 m3 claude-opus-5-5 1 1 0 0 >> "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[has("cost_usd"), has("cost_source"), .messages]')
  assert_equals '[false,false,3]' "$out" "partial cost"
  pass "cost: kept when every response reports one, otherwise left out rather than partial"
}

test_unmeasurable_usage_prints_nothing() {
  local out rc
  make_case absent
  out=$(read_usage) || fail "read without a transcript exited non-zero"
  assert_equals "" "$out" "no transcript"
  msg s1 m1 claude-opus-5-5 1 1 0 0 > "$TDIR/s1.jsonl"
  out=$(FM_TASK_USAGE_MAX_BYTES=10 read_usage)
  assert_equals "" "$out" "over the byte bound"
  sed -i.bak 's/^harness=claude$/harness=codex/' "$META"
  out=$(read_usage)
  assert_equals "" "$out" "another harness"
  sed -i.bak 's/^harness=codex$/harness=claude/; s/^kind=ship$/kind=secondmate/' "$META"
  out=$(read_usage)
  assert_equals "" "$out" "a second mate"
  out=$("$USAGE" read "$CASE_DIR/state/missing.meta"); rc=$?
  expect_code 0 "$rc" "missing record"
  assert_equals "" "$out" "missing record"
  "$USAGE" read "$META" --since soon >/dev/null 2>&1; rc=$?
  expect_code 2 "$rc" "malformed --since"
  pass "unmeasurable: no transcript, the byte bound, another harness, a second mate, or no record print nothing and exit 0"
}

write_ledger() {  # <file>
  local u1='{"source":"claude-transcript","basis":"dispatch-window","since":1,"sessions":1,"messages":2,"input_tokens":10,"output_tokens":20,"cache_write_tokens":30,"cache_read_tokens":40,"models":{}}'
  local u2='{"source":"claude-transcript","basis":"session-ids","since":null,"sessions":1,"messages":1,"input_tokens":1,"output_tokens":2,"cache_write_tokens":3,"cache_read_tokens":4,"models":{},"cost_usd":0.5,"cost_source":"claude-transcript"}'
  {
    printf '%s\n' '{"v":1,"ts":1790000000,"event":"task.dispatched","task":"a","kind":"ship","project":"webapp","harness":"claude","model":null}'
    printf '%s\n' '{"v":1,"ts":1790000100,"event":"task.status","task":"a","state":"working","key":null,"text":" go"}'
    printf '%s\n' "{\"v\":1,\"ts\":1790086400,\"event\":\"task.cleaned_up\",\"task\":\"a\",\"usage\":$u1}"
    printf '%s\n' '{"v":1,"ts":1790086500,"event":"task.dispatched","task":"a","kind":"scout","project":"api","harness":"claude","model":null}'
    printf '%s\n' "{\"v\":1,\"ts\":1790172800,\"event\":\"task.cleaned_up\",\"task\":\"a\",\"usage\":$u2}"
    printf '%s\n' '{"v":1,"ts":1790172900,"event":"task.dispatched","task":"b","kind":"ship","project":"webapp","harness":"codex","model":null}'
    printf '%s\n' '{"v":1,"ts":1790173000,"event":"task.cleaned_up","task":"b"}'
    printf '%s\n' '{"v":1,"ts":1790173100,"event":"task.cleaned_up","task":"c"}'
  } > "$1"
}

test_report_totals_tasks_and_projects_over_a_period() {
  local out
  mkdir -p "$TMP_ROOT/report/state"
  write_ledger "$TMP_ROOT/report/state/fleet-ledger.jsonl"
  out=$(FM_STATE_OVERRIDE="$TMP_ROOT/report/state" "$USAGE" report --json | jq -c '.projects')
  assert_equals '[{"project":null,"tasks":1,"measured":0,"unmeasured":1,"input_tokens":0,"output_tokens":0,"cache_write_tokens":0,"cache_read_tokens":0,"cost_usd":null},{"project":"api","tasks":1,"measured":1,"unmeasured":0,"input_tokens":1,"output_tokens":2,"cache_write_tokens":3,"cache_read_tokens":4,"cost_usd":0.5},{"project":"webapp","tasks":2,"measured":1,"unmeasured":1,"input_tokens":10,"output_tokens":20,"cache_write_tokens":30,"cache_read_tokens":40,"cost_usd":null}]' \
    "$out" "per-project totals"
  out=$(FM_STATE_OVERRIDE="$TMP_ROOT/report/state" "$USAGE" report --json | jq -c '[.tasks[] | [.task, .project, .measured, .input_tokens]]')
  assert_equals '[["a","webapp",true,10],["a","api",true,1],["b","webapp",false,null],["c",null,false,null]]' "$out" "per-task rows"
  out=$(FM_STATE_OVERRIDE="$TMP_ROOT/report/state" "$USAGE" report --since 2026-09-23 --until 1790172801 --json \
    | jq -c '[.since, .until, [.tasks[].task]]')
  assert_equals '[1790121600,1790172801,["a"]]' "$out" "period filter"
  out=$(FM_STATE_OVERRIDE="$TMP_ROOT/report/state" "$USAGE" report)
  assert_contains "$out" "  a,api,2026-09-23,1,2,3,4,0.5" "text task row"
  assert_contains "$out" "  b,webapp,2026-09-23,unmeasured" "text unmeasured row"
  assert_contains "$out" "  webapp,2,1,10,20,30,40,-" "text project row"
  assert_contains "$out" "note: token totals cover measured tasks only" "unmeasured note"
  out=$(FM_STATE_OVERRIDE="$TMP_ROOT/report/missing" "$USAGE" report --json)
  assert_equals '[]' "$(printf '%s' "$out" | jq -c '.tasks')" "no ledger"
  pass "report: tasks join their own dispatch for the project, unmeasured tasks stay unmeasured, and the period filters by cleanup time"
}

test_dispatch_window_counts_each_response_once
test_launch_window_falls_back_to_spawn_gen
test_session_ids_read_exactly_the_named_sessions
test_reported_cost_is_kept_only_when_every_response_has_one
test_unmeasurable_usage_prints_nothing
test_report_totals_tasks_and_projects_over_a_period
