#!/usr/bin/env bash
# fm-task-usage.sh - a task worker's own token usage, read from its agent
# tool's records, with an estimated cost, and the per-task and per-project
# report of what the fleet ledger recorded.
#
# docs/fleet-ledger.md ("Task usage") owns the public `usage` member of
# task.cleaned_up, its fields, and what is covered. This header owns how it is
# measured and how the report reads it.
#
# Usage:
#   fm-task-usage.sh capture <state>/<task>.meta
#   fm-task-usage.sh read <state>/<task>.meta [--since <epoch>]
#   fm-task-usage.sh report [--since <when>] [--until <when>] [--json]
#
# capture saves the task's usage to <state>/<task>.usage as one JSON object
# {spawn_gen, usage}, where usage is read's output or null. bin/fm-teardown.sh
# runs it while the ledger is on, after the worker is stopped and before the
# task's worktree is returned to its pool or removed, so a worker that leases
# the same worktree later is never counted. A saved file whose spawn_gen
# matches the record is kept as it is, so a retried cleanup after the worktree
# was returned reuses the figures taken before the return. capture runs read
# bounded by fm_run_timed at FM_TASK_USAGE_TIMEOUT seconds (default 30), with
# --since the ts of the task's latest task.dispatched record in
# <state>/fleet-ledger.jsonl when no task.cleaned_up of another incarnation (a
# different or missing spawn_gen) follows it. Any failure saves usage null,
# and capture always exits 0 apart from a usage error (2).
# bin/fm-fleet-ledger.sh cleaned_up copies the saved usage into the record.
#
# read prints one JSON object, the usage member, on one line, or nothing when
# the task's usage cannot be measured. It always exits 0 apart from a usage
# error (2).
#
# Covered: harness=claude ship and scout tasks. Every other harness, and every
# second mate, prints nothing. The Claude transcripts are
# <claude-root>/projects/<encoded worktree>/<session>.jsonl, with subagent
# transcripts in <session>/subagents/*.jsonl. The roots searched are the
# record's claude_root= (else its account= pin: `ordinary` is $HOME/.claude, a
# path is that root) and every root in claude_prior_roots=, the roots earlier
# launches of a relaunched task used (bin/fm-spawn.sh). The worktree is encoded
# as Claude does, every non-alphanumeric character replaced by `-`, for both
# the recorded and the physical path. A response counts when either:
#   - its session is named by claude_session_id= or claude_prior_session_ids=
#     (opt-in seat memory), whatever its time; or
#   - its cwd is the worktree or a directory under it, and its timestamp is at
#     or after the window start.
# The window start, named by the member's basis, is --since (dispatch-window)
# or else the start epoch of the record's spawn_gen= (launch-window). A
# launch-window figure is marked partial, because it misses any earlier
# launch of a relaunched task whose session was not named. A worktree serves
# one task at a time, so a window of its transcripts holds only that task's
# worker, plus any other Claude session someone ran in that worktree during
# the task.
#
# Counting. One API response is written as several transcript lines that
# repeat its usage, so responses are deduplicated by message id and request id
# and the last line of each counts. Synthetic responses (model "<synthetic>")
# are skipped. A response counts only when its input and output token counts
# are numbers; its cache counts default to 0 when the response omits them.
# Claude's input_tokens excludes cache reads and cache writes, so the four
# token members are disjoint. A cache write is priced at the 1-hour rate for
# the part the response's cache_creation reports as ephemeral_1h, and at the
# 5-minute rate otherwise.
#
# Cost. When every counted response carries a numeric costUSD, cost_usd is
# their sum and cost_source is "claude-transcript"; current Claude Code
# transcripts carry none. Otherwise cost_usd is an estimate at the PRICES
# table below, cost_source is "price-table", and price_table_date is
# PRICE_TABLE_DATE. A model is matched by its name with any trailing
# -YYYYMMDD removed. A model the table does not list stays unpriced: it is
# named in unpriced_models, its own cost_usd is null, and the task's cost_usd
# is null, never a partial sum.
#
# report reads <state>/fleet-ledger.jsonl whether or not the ledger is on, and
# prints the task.cleaned_up records whose ts falls in [--since, --until).
# Records of one task incarnation (the same task and spawn_gen, as a retried
# cleanup writes) count once, as the last of them. Each counted record is
# joined, for its project, to the task's latest task.dispatched record before
# it that no task.cleaned_up of another incarnation follows. Totals are added
# per project. <when> is a Unix epoch or a UTC date YYYY-MM-DD (its midnight);
# the defaults are the start of the ledger and now. A task with no usage
# member counts as unmeasured, never as zero, and a project total that
# includes an unmeasured or unpriced task says so and has no cost. The text
# form shows costs to four decimal places, an estimate prefixed with `~`.
# --json prints the same model as one JSON object.
#
# Environment: FM_HOME and FM_STATE_OVERRIDE resolve the home exactly as the
# other bin/ scripts do; FM_TASK_USAGE_MAX_BYTES (default 268435456) bounds
# the transcript bytes read, beyond which read prints nothing.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
MAX_BYTES=${FM_TASK_USAGE_MAX_BYTES:-268435456}
case "$MAX_BYTES" in ''|*[!0-9]*) MAX_BYTES=268435456 ;; esac
TIMEOUT=${FM_TASK_USAGE_TIMEOUT:-30}
case "$TIMEOUT" in ''|0|*[!0-9]*) TIMEOUT=30 ;; esac

# Anthropic first-party API list prices in USD per million tokens, as the
# Claude API reference listed them on PRICE_TABLE_DATE: input, output, 5-minute
# cache write, 1-hour cache write, cache read. claude-haiku-5-5 has a second
# card for prompts over 100K tokens (input + cache write + cache read).
PRICE_TABLE_DATE=2026-10-06
# shellcheck disable=SC2016 # jq, not shell expansion
PRICES='{
  "claude-fable-5-1":  [10, 50, 12.5, 20, 0.25],
  "claude-mythos-5-1": [10, 50, 12.5, 20, 0.25],
  "claude-fable-5":    [10, 50, 12.5, 20, 1],
  "claude-opus-5-5":   [4, 20, 5, 8, 0.2],
  "claude-opus-5":     [5, 25, 6.25, 10, 0.5],
  "claude-opus-4-8":   [5, 25, 6.25, 10, 0.5],
  "claude-opus-4-7":   [5, 25, 6.25, 10, 0.5],
  "claude-opus-4-6":   [5, 25, 6.25, 10, 0.5],
  "claude-sonnet-5-5": [2, 10, 2.5, 4, 0.2],
  "claude-sonnet-5":   [2, 10, 2.5, 4, 0.2],
  "claude-sonnet-4-6": [3, 15, 3.75, 6, 0.3],
  "claude-haiku-5-5":  [0.1, 0.5, 0.125, 0.2, 0.01],
  "claude-haiku-5-5>100k": [0.5, 2.5, 0.625, 1, 0.05],
  "claude-haiku-4-5":  [1, 5, 1.25, 2, 0.1]
}'

usage() {
  sed -n '2,/^set -u$/s/^# \{0,1\}//p' "$0"
}

if [ "$(uname)" = Darwin ]; then
  file_mtime() { /usr/bin/stat -f %m "$1" 2>/dev/null; }
else
  file_mtime() { stat -c %Y "$1" 2>/dev/null; }
fi

meta_value() {  # <meta> <key>: the last value of key=, or empty
  local line value=''
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$2="*) value=${line#*=} ;; esac
  done < "$1" 2>/dev/null
  printf '%s' "$value"
}

# Print the transcript files to read, one per line, possibly repeated.
claude_files() {  # <roots, newline-separated> <worktree> <since> <session-ids, comma-separated>
  local roots=$1 wt=$2 since=$3 ids=$4 wtp root enc dir f m sid
  wtp=$(cd "$wt" 2>/dev/null && pwd -P) || wtp=$wt
  while IFS= read -r root; do
    case "$root" in /*) ;; *) continue ;; esac
    for enc in "$wt" "$wtp"; do
      dir="$root/projects/$(printf '%s' "$enc" | sed 's/[^A-Za-z0-9]/-/g')"
      [ -d "$dir" ] || continue
      for sid in ${ids//,/ }; do
        case "$sid" in ''|*[!A-Za-z0-9-]*) continue ;; esac
        for f in "$dir/$sid.jsonl" "$dir/$sid"/subagents/*.jsonl; do
          [ -f "$f" ] && printf '%s\n' "$f"
        done
      done
      for f in "$dir"/*.jsonl "$dir"/*/subagents/*.jsonl; do
        [ -f "$f" ] || continue
        m=$(file_mtime "$f") || continue
        [ "$m" -ge "$since" ] && printf '%s\n' "$f"
      done
    done
  done <<< "$roots"
}

# shellcheck disable=SC2016 # jq variables, not shell expansion
CLAUDE_JQ='
def num: if type == "number" then . else null end;
def under($p): . == $p or startswith($p + "/");
def ts: (.timestamp // "") | tostring | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null);
def model_key: sub("-[0-9]{8}$"; "");
def tok: {
  input_tokens: .u.input_tokens,
  output_tokens: .u.output_tokens,
  cache_write_tokens: (.u.cache_creation_input_tokens // 0),
  cache_read_tokens: (.u.cache_read_input_tokens // 0)
};
def w1h: ([(.u.cache_creation.ephemeral_1h_input_tokens | num // 0), (.u.cache_creation_input_tokens // 0)] | min);
def price:
  (.model | model_key) as $m
  | tok as $t
  | (if $m == "claude-haiku-5-5" and ($t.input_tokens + $t.cache_write_tokens + $t.cache_read_tokens) > 100000
     then $prices[$m + ">100k"] else $prices[$m] end) as $p
  | if $p == null then null
    else ($t.input_tokens * $p[0] + $t.output_tokens * $p[1] + ($t.cache_write_tokens - w1h) * $p[2]
          + w1h * $p[3] + $t.cache_read_tokens * $p[4]) / 1000000 end;
def tally: {
  messages: length,
  input_tokens: (map(.t.input_tokens) | add),
  output_tokens: (map(.t.output_tokens) | add),
  cache_write_tokens: (map(.t.cache_write_tokens) | add),
  cache_read_tokens: (map(.t.cache_read_tokens) | add)
};
def total_cost: if all(.[]; .est != null) then (map(.est) | add) else null end;
[inputs | fromjson? // empty
  | select(type == "object" and .type == "assistant" and (.message | type) == "object")
  | select((.message.usage | type) == "object" and (.message.model // "") != "<synthetic>")
  | select((.message.usage.input_tokens | num) != null and (.message.usage.output_tokens | num) != null)
  | select(((.sessionId // "") as $s | any($ids[]; . == $s))
      or (((.cwd // "") | tostring | under($a) or under($b)) and ((ts // -1) >= $since)))
  | {key: [(.message.id // .uuid // ""), (.requestId // "")], session: .sessionId,
     model: (.message.model // "unknown"), u: .message.usage, cost: (.costUSD | num)}]
| group_by(.key) | map(.[-1]) | map(. + {t: tok, est: price})
| if length == 0 then empty else
  (all(.[]; .cost != null)) as $reported
  | {source: "claude-transcript", basis: $basis, since: $since, partial: ($basis == "launch-window"),
     sessions: (map(.session) | unique | length)}
  + tally
  + {models: (group_by(.model) | map({key: .[0].model, value: (tally + (if $reported then {} else {cost_usd: total_cost} end))}) | from_entries)}
  + (if $reported then {cost_usd: (map(.cost) | add), cost_source: "claude-transcript"}
     else {cost_usd: total_cost, cost_source: "price-table", price_table_date: $date,
           unpriced_models: (map(select(.est == null) | .model) | unique)} end)
  end'

cmd_read() {
  local meta=$1 since=$2 harness kind root account wt wtp roots prior ids basis files total size f
  [ -f "$meta" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  harness=$(meta_value "$meta" harness)
  kind=$(meta_value "$meta" kind)
  [ "$harness" = claude ] || return 0
  case "$kind" in ship|scout) ;; *) return 0 ;; esac
  root=$(meta_value "$meta" claude_root)
  if [ -z "$root" ]; then
    account=$(meta_value "$meta" account)
    case "$account" in
      ordinary) root=${HOME:+$HOME/.claude} ;;
      /*) root=$account ;;
    esac
  fi
  prior=$(meta_value "$meta" claude_prior_roots)
  roots=$(printf '%s\n%s\n' "$root" "${prior//,/$'\n'}" | awk 'NF && !seen[$0]++')
  [ -n "$roots" ] || return 0
  wt=$(meta_value "$meta" worktree)
  case "$wt" in /*) ;; *) return 0 ;; esac
  ids=$(meta_value "$meta" claude_prior_session_ids),$(meta_value "$meta" claude_session_id)
  if [ -n "$since" ]; then
    basis=dispatch-window
  else
    since=$(meta_value "$meta" spawn_gen)
    case "$since" in s[0-9]*.*) since=${since#s}; since=${since%%.*} ;; *) return 0 ;; esac
    case "$since" in *[!0-9]*) return 0 ;; esac
    basis=launch-window
  fi
  files=$(claude_files "$roots" "$wt" "$since" "$ids" | awk '!seen[$0]++')
  [ -n "$files" ] || return 0
  total=0
  while IFS= read -r f; do
    size=$(wc -c < "$f" 2>/dev/null | tr -d ' ') || return 0
    total=$((total + ${size:-0}))
  done <<< "$files"
  [ "$total" -le "$MAX_BYTES" ] || return 0
  wtp=$(cd "$wt" 2>/dev/null && pwd -P) || wtp=$wt
  while IFS= read -r f; do
    grep -F '"usage"' "$f" 2>/dev/null
  done <<< "$files" | jq -c -n -R --arg a "$wt" --arg b "$wtp" --arg basis "$basis" \
    --argjson since "$since" --arg date "$PRICE_TABLE_DATE" --argjson prices "$PRICES" \
    --argjson ids "$(printf '%s' "$ids" | jq -R -c 'split(",") | map(select(length > 0))')" \
    "$CLAUDE_JQ" 2>/dev/null || true
}

cmd_capture() {
  local meta=$1 dir task out spawn_gen since='' usage=''
  dir=$(dirname "$meta")
  task=$(basename "$meta" .meta)
  out="$dir/$task.usage"
  [ -f "$meta" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  spawn_gen=$(meta_value "$meta" spawn_gen)
  if [ -f "$out" ] && [ "$(jq -r '.spawn_gen // ""' "$out" 2>/dev/null)" = "$spawn_gen" ]; then
    return 0
  fi
  if [ -f "$dir/fleet-ledger.jsonl" ]; then
    # shellcheck disable=SC2016 # jq variables, not shell expansion
    since=$(grep -F "\"task\":\"$task\"" "$dir/fleet-ledger.jsonl" 2>/dev/null | jq -n -r -R --arg t "$task" --arg sg "$spawn_gen" '
      [inputs | fromjson? // empty
        | select(type == "object" and .task == $t and (.event == "task.dispatched" or .event == "task.cleaned_up"))]
      | reduce .[] as $r (null;
          if $r.event == "task.dispatched" then ($r.ts | if type == "number" then floor else null end)
          elif ($r.spawn_gen // "") != $sg or $sg == "" then null else . end)
      | . // empty' 2>/dev/null) || since=
  fi
  # shellcheck source=bin/fm-timeout-lib.sh
  . "$SCRIPT_DIR/fm-timeout-lib.sh" 2>/dev/null || return 0
  usage=$(fm_run_timed "$TIMEOUT" "$SCRIPT_DIR/fm-task-usage.sh" read "$meta" ${since:+--since "$since"} 2>/dev/null) || usage=
  printf '%s' "$usage" | jq -e 'type == "object"' >/dev/null 2>&1 || usage=null
  if jq -cn --arg sg "$spawn_gen" --argjson usage "$usage" '{spawn_gen: $sg, usage: $usage}' > "$out.tmp" 2>/dev/null; then
    mv -f "$out.tmp" "$out" 2>/dev/null || rm -f "$out.tmp"
  else
    rm -f "$out.tmp"
  fi
  return 0
}

when_epoch() {  # <epoch|YYYY-MM-DD> <out-var>
  local v=$1
  case "$v" in
    ''|*[!0-9-]*) return 1 ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
      v=$(jq -nr --arg d "$v" '$d + "T00:00:00Z" | fromdateiso8601' 2>/dev/null) || return 1 ;;
    *-*) return 1 ;;
  esac
  printf -v "$2" '%s' "$v"
}

# shellcheck disable=SC2016 # jq variables, not shell expansion
REPORT_JQ='
def tok: ["input_tokens", "output_tokens", "cache_write_tokens", "cache_read_tokens"];
def sum($rows): reduce tok[] as $k ({}; .[$k] = ($rows | map(.usage[$k] // 0) | add // 0));
def cost($rows): ($rows | map(.usage.cost_usd) | if length > 0 and all(.[]; type == "number") then add else null end);
[inputs | fromjson? // empty | select(type == "object" and (.task | type) == "string")] as $all
| [$all | to_entries[] | select(.value.event == "task.dispatched" or .value.event == "task.cleaned_up")
   | .value + {i: .key}] as $rows
| ($rows | map(select(.event == "task.cleaned_up"))) as $cleanups
| [$cleanups[] | select((.ts | type) == "number" and .ts >= $since and .ts < $until)
   | . as $c
   | select(($c.spawn_gen // null) == null
       or ([$cleanups[] | select(.task == $c.task and .spawn_gen == $c.spawn_gen and .i > $c.i)] | length) == 0)
   | ([$rows[] | select(.task == $c.task and .i < $c.i and .event == "task.cleaned_up"
         and ((.spawn_gen // null) == null or .spawn_gen != $c.spawn_gen)) | .i] | max // -1) as $boundary
   | ([$rows[] | select(.event == "task.dispatched" and .task == $c.task and .i < $c.i and .i > $boundary)] | last) as $d
   | {task, ts, project: ($d.project // null), harness: ($d.harness // null),
      usage: (if (.usage | type) == "object" then .usage else null end)}] as $tasks
| {since: $since, until: $until,
   tasks: [$tasks[] | {task, ts, project, harness, measured: (.usage != null)}
     + (if .usage != null then (.usage | {basis, partial: (.partial // false), sessions, messages} + sum([{usage: .}])
         + {cost_usd: (.cost_usd // null), cost_source: (.cost_source // null)}) else {} end)],
   projects: ($tasks | group_by(.project) | map(
     map(select(.usage != null)) as $m
     | {project: .[0].project, tasks: length, measured: ($m | length), unmeasured: (length - ($m | length))}
       + sum($m)
       + {cost_usd: (if length == ($m | length) then cost($m) else null end),
          estimated: any($m[]; .usage.cost_source == "price-table")}))}'

cmd_report() {
  local since=0 until json=0 ledger="$STATE/fleet-ledger.jsonl" model
  until=$(date +%s)
  until=$((until + 1))
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --since) when_epoch "${2-}" since || { echo "error: --since takes an epoch or YYYY-MM-DD" >&2; exit 2; }; shift ;;
      --until) when_epoch "${2-}" until || { echo "error: --until takes an epoch or YYYY-MM-DD" >&2; exit 2; }; shift ;;
      --json) json=1 ;;
      *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
    shift
  done
  command -v jq >/dev/null 2>&1 || { echo "error: jq is required" >&2; exit 1; }
  if [ -f "$ledger" ]; then
    model=$(jq -c -n -R --argjson since "$since" --argjson until "$until" "$REPORT_JQ" < "$ledger") \
      || { echo "error: could not read $ledger" >&2; exit 1; }
  else
    model=$(jq -c -n --argjson since "$since" --argjson until "$until" '{since: $since, until: $until, tasks: [], projects: []}')
  fi
  if [ "$json" = 1 ]; then
    printf '%s\n' "$model"
    return 0
  fi
  # shellcheck disable=SC2016 # jq variables, not shell expansion
  printf '%s\n' "$model" | jq -r '
    def d: todate | sub("T.*"; "");
    def n: if . == null then "-" else tostring end;
    def usd($est): if . == null then "-"
      elif . > 0 and . < 0.00005 then (if $est then "~" else "" end) + "<0.0001"
      else (. * 10000 | round) as $c | ($c / 10000 | floor | tostring) as $w
        | ("0000" + ($c % 10000 | tostring))[-4:] as $f
        | (if $est then "~" else "" end) + $w + "." + $f end;
    def row: [.input_tokens, .output_tokens, .cache_write_tokens, .cache_read_tokens] | map(n) | join(",");
    "period: \(.since | d) to \(.until | d) UTC, by cleanup time",
    "tasks[\(.tasks | length)]{task,project,cleaned_up,input,output,cache_write,cache_read,cost_usd}:",
    (.tasks[] | "  \(.task),\(.project | n),\(.ts | d)," + (if .measured then "\(row),\((.cost_source == "price-table") as $e | .cost_usd | usd($e))" + (if .partial then " (partial)" else "" end) else "unmeasured" end)),
    "projects[\(.projects | length)]{project,tasks,unmeasured,input,output,cache_write,cache_read,cost_usd}:",
    (.projects[] | "  \(.project | n),\(.tasks),\(.unmeasured),\(row),\(.estimated as $e | .cost_usd | usd($e))"),
    (if any(.projects[]; .unmeasured > 0) then "note: token totals cover measured tasks only; a project with unmeasured tasks has a lower bound and no cost" else empty end),
    (if any(.tasks[]; .cost_source == "price-table") then "note: ~ marks a cost estimated from list prices, not a billed amount" else empty end),
    (if any(.tasks[]; .measured and .cost_usd == null) then "note: - as a measured task cost means a model it used has no price" else empty end),
    (if any(.tasks[]; .partial) then "note: (partial) may miss earlier launches of a relaunched task" else empty end)'
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  read)
    [ "$#" -eq 2 ] || { [ "$#" -eq 4 ] && [ "$3" = --since ]; } || { usage >&2; exit 2; }
    SINCE=${4:-}
    case "$SINCE" in *[!0-9]*) usage >&2; exit 2 ;; esac
    cmd_read "$2" "$SINCE"
    exit 0
    ;;
  capture)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    case "$2" in */*.meta) ;; *) usage >&2; exit 2 ;; esac
    cmd_capture "$2"
    exit 0
    ;;
  report) shift; cmd_report "$@" ;;
  *) usage >&2; exit 2 ;;
esac
