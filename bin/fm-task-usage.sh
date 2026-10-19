#!/usr/bin/env bash
# fm-task-usage.sh - a task worker's own token usage, read from its agent
# tool's records, and the per-task and per-project report of what the fleet
# ledger recorded.
#
# docs/fleet-ledger.md ("Task usage") owns the public `usage` member of
# task.cleaned_up, its fields, and what is covered. This header owns how it is
# measured and how the report reads it.
#
# Usage:
#   fm-task-usage.sh read <state>/<task>.meta [--since <epoch>]
#   fm-task-usage.sh report [--since <when>] [--until <when>] [--json]
#
# read prints one JSON object, the usage member, on one line, or nothing when
# the task's usage cannot be measured. It always exits 0 apart from a usage
# error (2), so a caller can never be stopped by it. bin/fm-fleet-ledger.sh
# runs it for cleaned_up, bounded by fm_run_timed, before it takes the ledger
# lock, and passes --since as the time of the task's own task.dispatched record
# when the ledger holds one.
#
# Covered: harness=claude ship and scout tasks. Every other harness, and every
# second mate, prints nothing. The Claude transcript is
# <claude-root>/projects/<encoded worktree>/<session>.jsonl, with subagent
# transcripts in <session>/subagents/*.jsonl, where <claude-root> is the
# record's claude_root= (else its account= pin: `ordinary` is $HOME/.claude, a
# path is that root) and the worktree is encoded as Claude does, every
# non-alphanumeric character replaced by `-`, for both the recorded and the
# physical path. The sessions counted are chosen in this order, named by the
# member's basis:
#   session-ids      the record names claude_session_id= (and any
#                    claude_prior_session_ids=): exactly those sessions
#   dispatch-window  otherwise, with --since: every message in that worktree's
#                    transcripts whose cwd is the worktree or a directory
#                    under it and whose timestamp is at or after --since
#   launch-window    otherwise the same, from the start epoch of the record's
#                    spawn_gen=, which covers only the latest launch of a
#                    relaunched task
# A worktree serves one task at a time, so a window of its transcripts holds
# only that task's worker, plus any other Claude session someone ran with that
# worktree as its cwd during the task.
#
# Counting. One API response is written as several transcript lines that
# repeat its usage, so responses are deduplicated by message id and request id
# and the last line of each counts. Synthetic responses (model "<synthetic>")
# are skipped. A response counts only when its input and output token counts
# are numbers; its cache counts default to 0 when the response omits them.
# Claude's input_tokens excludes cache reads and cache writes, so the four
# token members are disjoint. cost_usd is present only when every counted
# response carries a numeric costUSD, which current Claude Code transcripts
# do not, and no price is ever derived here.
#
# report reads <state>/fleet-ledger.jsonl whether or not the ledger is on, and
# prints the task.cleaned_up records whose ts falls in [--since, --until),
# each joined to its task's latest earlier task.dispatched record for the
# project, plus totals per project. <when> is a Unix epoch or a UTC date
# YYYY-MM-DD (its midnight); the defaults are the start of the ledger and now.
# A task with no usage member counts as unmeasured, never as zero, and a
# project total that includes an unmeasured task says so. --json prints the
# same model as one JSON object.
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

# Print the transcript files to read, one per line.
claude_files() {  # <root> <worktree> <since> <session-ids, comma-separated>
  local root=$1 wt=$2 since=$3 ids=$4 wtp enc dir seen='' f m sid
  wtp=$(cd "$wt" 2>/dev/null && pwd -P) || wtp=$wt
  for enc in "$wt" "$wtp"; do
    dir="$root/projects/$(printf '%s' "$enc" | sed 's/[^A-Za-z0-9]/-/g')"
    case " $seen " in *" $dir "*) continue ;; esac
    seen="$seen $dir"
    [ -d "$dir" ] || continue
    if [ -n "$ids" ]; then
      for sid in ${ids//,/ }; do
        case "$sid" in ''|*[!A-Za-z0-9-]*) continue ;; esac
        for f in "$dir/$sid.jsonl" "$dir/$sid"/subagents/*.jsonl; do
          [ -f "$f" ] && printf '%s\n' "$f"
        done
      done
    else
      for f in "$dir"/*.jsonl "$dir"/*/subagents/*.jsonl; do
        [ -f "$f" ] || continue
        m=$(file_mtime "$f") || continue
        [ "$m" -ge "$since" ] && printf '%s\n' "$f"
      done
    fi
  done
}

# shellcheck disable=SC2016 # jq variables, not shell expansion
CLAUDE_JQ='
def num: if type == "number" then . else null end;
def under($p): . == $p or startswith($p + "/");
def ts: (.timestamp // "") | tostring | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch null);
def tally: {
  messages: length,
  input_tokens: (map(.u.input_tokens) | add),
  output_tokens: (map(.u.output_tokens) | add),
  cache_write_tokens: (map(.u.cache_creation_input_tokens // 0) | add),
  cache_read_tokens: (map(.u.cache_read_input_tokens // 0) | add)
};
[inputs | fromjson? // empty
  | select(type == "object" and .type == "assistant" and (.message | type) == "object")
  | select((.message.usage | type) == "object" and (.message.model // "") != "<synthetic>")
  | select((.message.usage.input_tokens | num) != null and (.message.usage.output_tokens | num) != null)
  | select(($window | not) or (((.cwd // "") | tostring | under($a) or under($b)) and ((ts // -1) >= $since)))
  | {key: [(.message.id // .uuid // ""), (.requestId // "")], session: .sessionId,
     model: (.message.model // "unknown"), u: .message.usage, cost: (.costUSD | num)}]
| group_by(.key) | map(.[-1])
| if length == 0 then empty else
  {source: "claude-transcript", basis: $basis, since: (if $window then $since else null end),
   sessions: (map(.session) | unique | length)}
  + tally
  + {models: (group_by(.model) | map({key: .[0].model, value: tally}) | from_entries)}
  + (if all(.[]; .cost != null) then {cost_usd: (map(.cost) | add), cost_source: "claude-transcript"} else {} end)
  end'

cmd_read() {
  local meta=$1 since=$2 harness kind root account wt ids basis files total size f
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
  wt=$(meta_value "$meta" worktree)
  case "$root:$wt" in /*:/*) ;; *) return 0 ;; esac
  ids=$(meta_value "$meta" claude_session_id)
  f=$(meta_value "$meta" claude_prior_session_ids)
  ids=${f:+$f,}$ids
  ids=${ids%,}
  if [ -n "$ids" ]; then
    basis=session-ids
    since=0
  elif [ -n "$since" ]; then
    basis=dispatch-window
  else
    since=$(meta_value "$meta" spawn_gen)
    case "$since" in s[0-9]*.*) since=${since#s}; since=${since%%.*} ;; *) return 0 ;; esac
    case "$since" in *[!0-9]*) return 0 ;; esac
    basis=launch-window
  fi
  files=$(claude_files "$root" "$wt" "$since" "$ids")
  [ -n "$files" ] || return 0
  total=0
  while IFS= read -r f; do
    size=$(wc -c < "$f" 2>/dev/null | tr -d ' ') || return 0
    total=$((total + ${size:-0}))
  done <<< "$files"
  [ "$total" -le "$MAX_BYTES" ] || return 0
  local wtp
  wtp=$(cd "$wt" 2>/dev/null && pwd -P) || wtp=$wt
  while IFS= read -r f; do
    grep -F '"usage"' "$f" 2>/dev/null
  done <<< "$files" | jq -c -n -R --arg a "$wt" --arg b "$wtp" --arg basis "$basis" \
    --argjson since "$since" --argjson window "$([ "$basis" = session-ids ] && echo false || echo true)" \
    "$CLAUDE_JQ" 2>/dev/null || true
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
| [$all | to_entries[] | select(.value.event == "task.dispatched" or .value.event == "task.cleaned_up") | .value + {i: .key}] as $rows
| [$rows[] | select(.event == "task.cleaned_up" and (.ts | type) == "number" and .ts >= $since and .ts < $until)
   | . as $c
   | ([$rows[] | select(.event == "task.dispatched" and .task == $c.task and .i < $c.i)] | last) as $d
   | {task, ts, project: ($d.project // null), harness: ($d.harness // null),
      usage: (if (.usage | type) == "object" then .usage else null end)}] as $tasks
| {since: $since, until: $until,
   tasks: [$tasks[] | {task, ts, project, harness, measured: (.usage != null)}
     + (if .usage != null then (.usage | {basis, sessions, messages} + sum([{usage: .}]) + {cost_usd: (.cost_usd // null)}) else {} end)],
   projects: ($tasks | group_by(.project) | map(
     map(select(.usage != null)) as $m
     | {project: .[0].project, tasks: length, measured: ($m | length), unmeasured: (length - ($m | length))}
       + sum($m) + {cost_usd: (if length == ($m | length) then cost($m) else null end)}))}'

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
    def usd: if . == null then "-" else (. * 100 | round / 100 | tostring) end;
    def row: [.input_tokens, .output_tokens, .cache_write_tokens, .cache_read_tokens] | map(n) | join(",");
    "period: \(.since | d) to \(.until | d) UTC, by cleanup time",
    "tasks[\(.tasks | length)]{task,project,cleaned_up,input,output,cache_write,cache_read,cost_usd}:",
    (.tasks[] | "  \(.task),\(.project | n),\(.ts | d)," + (if .measured then "\(row),\(.cost_usd | usd)" else "unmeasured" end)),
    "projects[\(.projects | length)]{project,tasks,unmeasured,input,output,cache_write,cache_read,cost_usd}:",
    (.projects[] | "  \(.project | n),\(.tasks),\(.unmeasured),\(row),\(.cost_usd | usd)"),
    (if any(.projects[]; .unmeasured > 0) then "note: token totals cover measured tasks only; a project with unmeasured tasks has a lower bound and no cost" else empty end)'
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
  report) shift; cmd_report "$@" ;;
  *) usage >&2; exit 2 ;;
esac
