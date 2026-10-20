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
        cache_creation_input_tokens: $cw, cache_read_input_tokens: $cr}}} * $extra'
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
  out=$(read_usage --since "$((NOW - 3600))" | jq -c 'del(.cost_usd, .cost_source, .price_table_date, .unpriced_models, .models[].cost_usd)') \
    || fail "read exited non-zero"
  assert_equals "$(jq -cn --argjson since "$((NOW - 3600))" '{source: "claude-transcript", basis: "dispatch-window", since: $since, partial: false,
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
  out=$(read_usage | jq -c '[.basis, .since, .partial, .messages, .input_tokens]')
  assert_equals "[\"launch-window\",$((NOW - 60)),true,1,2]" "$out" "launch-window usage"
  pass "launch window: without a dispatch time, only responses since the record's spawn_gen count"
}

test_named_sessions_add_to_the_window_without_replacing_it() {
  local out
  make_case sessions
  printf 'claude_session_id=bbbb-2\nclaude_prior_session_ids=aaaa-1\n' >> "$META"
  msg aaaa-1 m1 claude-opus-5-5 1 1 0 0 2020-01-01T00:00:00Z > "$TDIR/aaaa-1.jsonl"
  msg bbbb-2 m2 claude-opus-5-5 2 2 0 0 > "$TDIR/bbbb-2.jsonl"
  mkdir -p "$TDIR/bbbb-2/subagents"
  msg bbbb-2 m3 claude-opus-5-5 4 4 0 0 > "$TDIR/bbbb-2/subagents/agent-x.jsonl"
  msg cccc-3 m4 claude-opus-5-5 8 8 0 0 > "$TDIR/cccc-3.jsonl"
  msg dddd-4 m5 claude-opus-5-5 100 100 0 0 2020-01-01T00:00:00Z > "$TDIR/dddd-4.jsonl"
  out=$(read_usage --since "$((NOW - 3600))" | jq -c '[.basis, .partial, .sessions, .messages, .input_tokens]')
  assert_equals '["dispatch-window",false,3,4,15]' "$out" "named sessions plus the window"
  pass "named sessions: a named earlier session counts whatever its age, and a launch with no recorded id still counts through the window"
}

test_prior_roots_are_searched() {
  local out old_root old_dir
  make_case roots
  # A root may hold `,` and `%`, which the record writes as %2C and %25.
  old_root="$CASE_DIR/claude,old%2C"
  old_dir="$old_root/projects/$(printf '%s' "$WT" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$old_dir"
  printf 'claude_prior_roots=%s,%s\nclaude_prior_session_ids=eeee-5\n' "$CASE_DIR/none" "$CASE_DIR/claude%2Cold%252C" >> "$META"
  msg eeee-5 m1 claude-opus-5-5 1 1 0 0 2020-01-01T00:00:00Z > "$old_dir/eeee-5.jsonl"
  msg ffff-6 m2 claude-opus-5-5 2 2 0 0 > "$old_dir/ffff-6.jsonl"
  msg gggg-7 m3 claude-opus-5-5 4 4 0 0 > "$TDIR/gggg-7.jsonl"
  out=$(read_usage --since "$((NOW - 3600))" | jq -c '[.sessions, .messages, .input_tokens]')
  assert_equals '[3,3,7]' "$out" "usage across roots"
  pass "prior roots: sessions an earlier launch left under another Claude root, even one whose path holds a comma, are counted, named or in the window"
}

test_cost_is_estimated_from_the_dated_price_table() {
  local out
  make_case estimate
  {
    msg s1 m1 claude-opus-5-5 1000000 1000000 1000000 1000000 "$NOW_ISO" "$WT" \
      '{"message":{"usage":{"cache_creation":{"ephemeral_1h_input_tokens":250000,"ephemeral_5m_input_tokens":750000}}}}'
    msg s1 m2 claude-haiku-5-5 50000 1000000 0 0
    msg s1 m3 claude-haiku-5-5 150000 1000000 0 0
    msg s1 m4 claude-sonnet-5-5-20261001 1000000 0 0 1000000
  } > "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.cost_usd, .cost_source, .price_table_date, .unpriced_models,
    (.models | to_entries | map([.key, .value.cost_usd]))]')
  # opus: 4 + 20 + 0.75*5 + 0.25*8 + 0.2 = 29.95; haiku: 0.005+0.5 and 0.075+2.5 (over 100K); sonnet: 2 + 0.1
  assert_equals '[35.13,"price-table","2026-10-19",[],[["claude-haiku-5-5",3.08],["claude-opus-5-5",29.95],["claude-sonnet-5-5-20261001",2.1]]]' \
    "$(printf '%s' "$out" | jq -c '.[0] |= (. * 100 | round / 100) | .[4] |= map(.[1] |= (. * 100 | round / 100))')" "estimated cost"
  msg s1 m5 claude-unknown-9 1 1 0 0 >> "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.cost_usd, .unpriced_models, .models["claude-unknown-9"].cost_usd, (.models["claude-opus-5-5"].cost_usd != null)]')
  assert_equals '[null,["claude-unknown-9"],null,true]' "$out" "unpriced model"
  pass "cost: estimated from the dated list-price table per model, 1-hour writes and Haiku's long-prompt card included, and an unknown model leaves the total unpriced rather than partial"
}

test_reported_cost_is_used_when_every_response_has_one() {
  local out
  make_case cost
  {
    msg s1 m1 claude-opus-5-5 1 1 0 0 "$NOW_ISO" "$WT" '{"costUSD":0.25}'
    msg s1 m2 claude-opus-5-5 1 1 0 0 "$NOW_ISO" "$WT" '{"costUSD":0.5}'
    msg s1 m3 claude-sonnet-5-5 1 1 0 0 "$NOW_ISO" "$WT" '{"costUSD":0.125}'
  } > "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.cost_usd, .cost_source, has("price_table_date"), .models["claude-opus-5-5"].cost_usd, .models["claude-sonnet-5-5"].cost_usd]')
  assert_equals '[0.875,"claude-transcript",false,0.75,0.125]' "$out" "reported cost"
  # One response served by two models cannot be split between them.
  msg s1 m4 claude-sonnet-5-5 1 1 0 0 "$NOW_ISO" "$WT" \
    '{"costUSD":1,"message":{"usage":{"iterations":[{"type":"message","model":"claude-opus-5-5","input_tokens":1,"output_tokens":0},{"type":"fallback_message","model":"claude-sonnet-5-5","input_tokens":1,"output_tokens":1}]}}}' \
    >> "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.cost_usd, .models["claude-opus-5-5"].cost_usd, .models["claude-sonnet-5-5"].cost_usd]')
  assert_equals '[1.875,null,null]' "$out" "reported cost across models"
  msg s1 m5 claude-opus-5-5 1 1 0 0 >> "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.cost_source, .messages]')
  assert_equals '["price-table",5]' "$out" "partial reported cost"
  pass "cost: the tool's own cost is used, in total and per model, when every response reports one, otherwise the estimate"
}

test_usage_iterations_are_summed_per_model() {
  local out
  make_case iterations
  {
    # A compaction step: the top-level counts leave it out.
    msg s1 m1 claude-opus-5-5 10 20 0 0 "$NOW_ISO" "$WT" \
      '{"message":{"usage":{"iterations":[{"type":"compaction","input_tokens":1000,"output_tokens":300},{"type":"message","input_tokens":10,"output_tokens":20}]}}}'
    # A fallback: the declined attempt ran on another model.
    msg s1 m2 claude-opus-4-8 412 264 0 0 "$NOW_ISO" "$WT" \
      '{"message":{"usage":{"iterations":[{"type":"message","model":"claude-fable-5","input_tokens":535,"output_tokens":0},{"type":"fallback_message","model":"claude-opus-4-8","input_tokens":412,"output_tokens":264}]}}}'
  } > "$TDIR/s1.jsonl"
  out=$(read_usage | jq -c '[.messages, .input_tokens, .output_tokens,
    (.models | to_entries | map([.key, .value.messages, .value.input_tokens, .value.output_tokens, (.value.cost_usd * 1e6 | round)])),
    (.cost_usd * 1e6 | round)]')
  # opus-5-5: 1010*4 + 320*20; fable-5: 535*10; opus-4-8: 412*5 + 264*25 (micro-dollars)
  assert_equals '[2,1957,584,[["claude-fable-5",1,535,0,5350],["claude-opus-4-8",1,412,264,8660],["claude-opus-5-5",1,1010,320,10440]],24450]' \
    "$out" "usage iterations"
  pass "iterations: a response's server-side steps and fallback attempts are summed, each under the model that ran it"
}

test_capture_takes_the_dispatch_window_and_keeps_its_figures() {
  local out sg="s$((NOW - 60)).1.2"
  make_case capture
  msg s1 m1 claude-opus-5-5 2 2 0 0 > "$TDIR/s1.jsonl"
  printf '{"v":1,"ts":%s,"event":"task.dispatched","task":"capture"}\n' "$((NOW - 3600))" > "$CASE_DIR/state/fleet-ledger.jsonl"
  "$USAGE" capture "$META" || fail "capture exited non-zero"
  out=$(jq -c '[.spawn_gen, .usage.basis, .usage.since, .usage.input_tokens]' "$CASE_DIR/state/capture.usage")
  assert_equals "[\"$sg\",\"dispatch-window\",$((NOW - 3600)),2]" "$out" "captured usage"
  msg s1 m2 claude-opus-5-5 40 40 0 0 >> "$TDIR/s1.jsonl"
  "$USAGE" capture "$META"
  out=$(jq -c '.usage.input_tokens' "$CASE_DIR/state/capture.usage")
  assert_equals 2 "$out" "a repeated capture of the same launch"
  printf '{"v":1,"ts":%s,"event":"task.cleaned_up","task":"capture","spawn_gen":"s1.1.1"}\n' "$((NOW - 1800))" \
    >> "$CASE_DIR/state/fleet-ledger.jsonl"
  rm -f "$CASE_DIR/state/capture.usage"
  "$USAGE" capture "$META"
  out=$(jq -c '[.usage.basis, .usage.input_tokens]' "$CASE_DIR/state/capture.usage")
  assert_equals '["launch-window",42]' "$out" "a dispatch of an earlier incarnation"
  rm -f "$TDIR/s1.jsonl" "$CASE_DIR/state/capture.usage"
  "$USAGE" capture "$META"
  assert_equals "{\"spawn_gen\":\"$sg\",\"usage\":null}" "$(cat "$CASE_DIR/state/capture.usage")" "nothing to measure"
  pass "capture: the window starts at this incarnation's dispatch, a saved figure of the same launch is kept, and nothing to measure saves null"
}

test_capture_counts_responses_written_before_the_dispatch_record() {
  local out
  make_case early
  msg s1 m1 claude-opus-5-5 5 5 0 0 "$(jq -nr --argjson t "$((NOW - 45))" '$t | todate')" > "$TDIR/s1.jsonl"
  printf '{"v":1,"ts":%s,"event":"task.dispatched","task":"early"}\n' "$((NOW - 30))" > "$CASE_DIR/state/fleet-ledger.jsonl"
  "$USAGE" capture "$META" || fail "capture exited non-zero"
  out=$(jq -c '[.usage.basis, .usage.since, .usage.input_tokens]' "$CASE_DIR/state/early.usage")
  assert_equals "[\"dispatch-window\",$((NOW - 60)),5]" "$out" "a response between launch and dispatch record"
  pass "capture: a response written after launch but before the dispatch record is counted"
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
  local u1='{"source":"claude-transcript","basis":"dispatch-window","since":1,"partial":false,"sessions":1,"messages":2,"input_tokens":10,"output_tokens":20,"cache_write_tokens":30,"cache_read_tokens":40,"models":{},"cost_usd":0.00321,"cost_source":"price-table","price_table_date":"2026-10-06","unpriced_models":[]}'
  local u2='{"source":"claude-transcript","basis":"dispatch-window","since":1,"partial":false,"sessions":1,"messages":1,"input_tokens":1,"output_tokens":2,"cache_write_tokens":3,"cache_read_tokens":4,"models":{},"cost_usd":0.5,"cost_source":"claude-transcript"}'
  local u3='{"source":"claude-transcript","basis":"launch-window","since":1,"partial":true,"sessions":1,"messages":1,"input_tokens":100,"output_tokens":0,"cache_write_tokens":0,"cache_read_tokens":0,"models":{},"cost_usd":null,"cost_source":"price-table","price_table_date":"2026-10-06","unpriced_models":["claude-unknown-9"]}'
  {
    printf '%s\n' '{"v":1,"ts":1790000000,"event":"task.dispatched","task":"a","kind":"ship","project":"webapp","harness":"claude","model":null}'
    printf '%s\n' '{"v":1,"ts":1790000100,"event":"task.status","task":"a","state":"working","key":null,"text":" go"}'
    printf '%s\n' "{\"v\":1,\"ts\":1790086400,\"event\":\"task.cleaned_up\",\"task\":\"a\",\"spawn_gen\":\"a1\",\"usage\":$u1}"
    printf '%s\n' '{"v":1,"ts":1790086500,"event":"task.dispatched","task":"a","kind":"scout","project":"api","harness":"claude","model":null}'
    printf '%s\n' "{\"v\":1,\"ts\":1790172700,\"event\":\"task.cleaned_up\",\"task\":\"a\",\"spawn_gen\":\"a2\",\"usage\":$u2}"
    printf '%s\n' "{\"v\":1,\"ts\":1790172800,\"event\":\"task.cleaned_up\",\"task\":\"a\",\"spawn_gen\":\"a2\",\"usage\":$u2}"
    printf '%s\n' '{"v":1,"ts":1790172900,"event":"task.dispatched","task":"b","kind":"ship","project":"webapp","harness":"codex","model":null}'
    printf '%s\n' '{"v":1,"ts":1790173000,"event":"task.cleaned_up","task":"b","spawn_gen":"b1"}'
    printf '%s\n' '{"v":1,"ts":1790173100,"event":"task.cleaned_up","task":"c"}'
    printf '%s\n' '{"v":1,"ts":1790173200,"event":"task.dispatched","task":"d","kind":"ship","project":"webapp","harness":"claude","model":null}'
    printf '%s\n' "{\"v\":1,\"ts\":1790173300,\"event\":\"task.cleaned_up\",\"task\":\"d\",\"spawn_gen\":\"d1\",\"usage\":$u3}"
    printf '%s\n' "{\"v\":1,\"ts\":1790173400,\"event\":\"task.cleaned_up\",\"task\":\"d\",\"spawn_gen\":\"d2\",\"usage\":$u3}"
  } > "$1"
}

test_report_totals_tasks_and_projects_over_a_period() {
  local out
  mkdir -p "$TMP_ROOT/report/state"
  write_ledger "$TMP_ROOT/report/state/fleet-ledger.jsonl"
  report() { FM_STATE_OVERRIDE="$TMP_ROOT/report/state" "$USAGE" report "$@"; }
  out=$(report --json | jq -c '[.tasks[] | [.task, .project, .measured, .input_tokens, .cost_usd]]')
  assert_equals '[["a","webapp",true,10,0.00321],["a","api",true,1,0.5],["b","webapp",false,null,null],["c",null,false,null,null],["d","webapp",true,100,null],["d",null,true,100,null]]' \
    "$out" "per-task rows"
  out=$(report --json | jq -c '[.projects[] | [.project, .tasks, .measured, .unmeasured, .input_tokens, .cost_usd, .estimated]]')
  assert_equals '[[null,2,1,1,100,null,true],["api",1,1,0,1,0.5,false],["webapp",3,2,1,110,null,true]]' "$out" "per-project totals"
  out=$(report --since 2026-09-23 --until 1790172801 --json | jq -c '[.since, .until, [.tasks[].task]]')
  assert_equals '[1790121600,1790172801,["a"]]' "$out" "period filter"
  out=$(report)
  assert_contains "$out" "  a,webapp,2026-09-22,10,20,30,40,~0.0032" "text estimated sub-cent cost"
  assert_contains "$out" "  a,api,2026-09-23,1,2,3,4,0.5000" "text reported cost"
  assert_contains "$out" "  b,webapp,2026-09-23,unmeasured" "text unmeasured row"
  assert_contains "$out" "  d,-,2026-09-23,100,0,0,0,- (partial)" "text unpriced partial row"
  assert_contains "$out" "  api,1,0,1,2,3,4,0.5000" "text project row"
  assert_contains "$out" "note: token totals cover measured tasks only" "unmeasured note"
  assert_contains "$out" "note: ~ marks a cost estimated from list prices" "estimate note"
  out=$(FM_STATE_OVERRIDE="$TMP_ROOT/report/missing" "$USAGE" report --json)
  assert_equals '[]' "$(printf '%s' "$out" | jq -c '.tasks')" "no ledger"
  pass "report: a retried cleanup counts once, a reused task id never takes an earlier incarnation's project, costs keep sub-cent precision, and the period filters by cleanup time"
}

test_dispatch_window_counts_each_response_once
test_launch_window_falls_back_to_spawn_gen
test_named_sessions_add_to_the_window_without_replacing_it
test_prior_roots_are_searched
test_cost_is_estimated_from_the_dated_price_table
test_reported_cost_is_used_when_every_response_has_one
test_usage_iterations_are_summed_per_model
test_capture_takes_the_dispatch_window_and_keeps_its_figures
test_capture_counts_responses_written_before_the_dispatch_record
test_unmeasurable_usage_prints_nothing
test_report_totals_tasks_and_projects_over_a_period
