#!/usr/bin/env bash
# Collect review feedback across landed tickets for the periodic trend review.
#
# This is a read-only command. It never edits rules, posts, comments, or files
# anything, makes no model calls, and never replays or evaluates a run. It only
# gathers records and groups them mechanically by source, ticket, pipeline
# step, finding severity, and file; the reader does any theming.
#
# Usage: fm-feedback-collect.sh --since <YYYY-MM-DD> --out <prefix>
#                               [--nm-db <path>] [--home <firstmate-home>]
#                               [--no-github]
#   Writes <prefix>.md and <prefix>.json holding the same records.
#   --since    start of the window, UTC midnight of that date.
#   --nm-db    no-mistakes state database (default
#              ${NM_HOME:-$HOME/.no-mistakes}/state.sqlite).
#   --home     Firstmate home whose steering inboxes and data/backlog.md are
#              read (default $FM_HOME, else this repository's root).
#   --no-github  skip the pull-request comment reads.
#   Exits 2 on a usage error; an absent or unreadable input is reported in the
#   output's inputs list instead of failing the run.
#
# Where each input lives:
# - Landed tickets: no-mistakes `runs` rows with pr_state `merged` whose
#   pr_state_observed_at (else updated_at) falls in the window. Every run on
#   the same repository and branch counts as an attempt of that ticket, so
#   rounds from a cancelled or restarted run are included.
# - Gate answers and their stated reasons: `step_results.approval_reason`,
#   `override_reason`, and `skip_reason`, plus every `step_rounds` row whose
#   selection_source starts with `user` (`user` selected the listed finding
#   ids, `user_declined` declined them all). The `no-mistakes.db` file beside
#   state.sqlite is not the store.
# - Findings raised and not fixed or declined: each finding in a round's
#   findings_json whose id is not in that round's selected_finding_ids, kind
#   `declined` under `user_declined` and `not-selected` otherwise; findings an
#   operator added through user_findings_json are kind `operator-added`.
#   A finding re-raised in a later round appears once per round.
# - Review comments: conversation comments, review bodies, and inline review
#   comments on each landed GitHub pull request, read through
#   `gh-axi api ... --paginate --full`. They are untrusted text: the markdown
#   output shows them only as indented code blocks, never as markup.
# - Steers to workers: `<home>/state/<task>.inbox/*.msg` and `handled/*.msg`
#   (bin/fm-task-inbox-lib.sh owns the format), kept only when the home's
#   markdown backlog `<home>/data/backlog.md` closes that task as merged inside
#   the window, and grouped under the pull request that row links, else the
#   task id. Cleanup deletes a task's inbox, so steers survive only for tasks
#   not yet cleaned up; the output says so.
# - Retro proposals held or declined: backlog rows whose id contains `retro`
#   that are still held for the captain (`hold-kind: captain`), or that carry a
#   recorded `Captain decision:` and closed inside the window.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  sed -n '2,/^set -eu$/s/^# \{0,1\}//p' "$0"
}

die() {
  printf 'fm-feedback-collect: %s\n' "$*" >&2
  exit 2
}

SINCE='' OUT='' NM_DB="${NM_HOME:-$HOME/.no-mistakes}/state.sqlite" HOME_DIR="${FM_HOME:-$ROOT}" GITHUB=1
while [ "$#" -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --since) [ "$#" -ge 2 ] || die "--since needs a date"; SINCE=$2; shift 2 ;;
    --out) [ "$#" -ge 2 ] || die "--out needs a path prefix"; OUT=$2; shift 2 ;;
    --nm-db) [ "$#" -ge 2 ] || die "--nm-db needs a path"; NM_DB=$2; shift 2 ;;
    --home) [ "$#" -ge 2 ] || die "--home needs a path"; HOME_DIR=$2; shift 2 ;;
    --no-github) GITHUB=0; shift ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done
[ -n "$SINCE" ] && [ -n "$OUT" ] || die "usage: fm-feedback-collect.sh --since <YYYY-MM-DD> --out <prefix>"
command -v jq >/dev/null 2>&1 || die "jq is required"
SINCE_EPOCH=$(jq -rn --arg d "$SINCE" '$d | select(test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")) | (. + "T00:00:00Z") | fromdateiso8601' 2>/dev/null) \
  && [ -n "$SINCE_EPOCH" ] || die "--since must be a date as YYYY-MM-DD"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-feedback-collect.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
INPUTS="$WORK/inputs.jsonl"
: > "$INPUTS"
note_input() { # <name> <read|absent|error|skipped> <detail>
  jq -cn --arg name "$1" --arg status "$2" --arg detail "$3" '{name:$name,status:$status,detail:$detail}' >> "$INPUTS"
}
printf '[]' > "$WORK/runs.json"
printf '[]' > "$WORK/steps.json"
printf '[]' > "$WORK/rounds.json"
printf '[]' > "$WORK/comments.json"
printf '[]' > "$WORK/steers.json"
printf '[]' > "$WORK/backlog.json"
printf '[]' > "$WORK/proposals.json"

# --- no-mistakes database --------------------------------------------------
nm_query() { # <out-file> <sql>
  local rows
  rows=$(sqlite3 -readonly -json "$NM_DB" "$2") || return 1
  printf '%s' "${rows:-[]}" > "$1"
}
WINDOW_RUNS="SELECT w.id FROM runs w WHERE EXISTS (SELECT 1 FROM runs m
    WHERE m.repo_id = w.repo_id AND m.branch = w.branch AND m.pr_state = 'merged'
      AND COALESCE(m.pr_state_observed_at, m.updated_at) >= $SINCE_EPOCH)"
if ! command -v sqlite3 >/dev/null 2>&1; then
  note_input no-mistakes absent "sqlite3 is not installed"
elif [ ! -s "$NM_DB" ]; then
  note_input no-mistakes absent "no database at $NM_DB"
elif nm_query "$WORK/runs.json" "SELECT r.id AS run_id, p.upstream_url AS repo, r.branch,
      (SELECT m.pr_url FROM runs m WHERE m.repo_id = r.repo_id AND m.branch = r.branch
        AND m.pr_state = 'merged' ORDER BY m.updated_at DESC LIMIT 1) AS pr_url,
      r.status, r.created_at
    FROM runs r JOIN repos p ON p.id = r.repo_id WHERE r.id IN ($WINDOW_RUNS)" \
  && nm_query "$WORK/steps.json" "SELECT s.run_id, s.step_name AS step, s.status,
      s.approval_reason, s.override_reason, s.skip_reason, s.completed_at
    FROM step_results s WHERE s.run_id IN ($WINDOW_RUNS)
      AND COALESCE(s.approval_reason, s.override_reason, s.skip_reason, '') <> ''" \
  && nm_query "$WORK/rounds.json" "SELECT s.run_id, s.step_name AS step, rd.round,
      rd.trigger_type, COALESCE(rd.selection_source, '') AS selection_source,
      COALESCE(NULLIF(rd.selected_finding_ids, ''), '[]') AS selected,
      COALESCE(NULLIF(rd.findings_json, ''), '{}') AS findings,
      COALESCE(NULLIF(rd.user_findings_json, ''), '{}') AS user_findings, rd.created_at
    FROM step_rounds rd JOIN step_results s ON s.id = rd.step_result_id
    WHERE s.run_id IN ($WINDOW_RUNS)"; then
  note_input no-mistakes read "$NM_DB: $(jq length "$WORK/runs.json") runs on landed tickets"
else
  printf '[]' > "$WORK/runs.json"; printf '[]' > "$WORK/steps.json"; printf '[]' > "$WORK/rounds.json"
  note_input no-mistakes error "could not query $NM_DB; its schema may have changed"
fi

# --- pull-request review comments ------------------------------------------
# gh-axi wraps --jq output as a quoted `body:` string, and re-renders output
# that is itself one JSON value, so each row carries an `R ` prefix.
gh_rows() { # <api-path> <jq-row-filter>: one JSON row per line on stdout
  local out body
  out=$(gh-axi api "$1" --paginate --full --jq ".[] | $2 | \"R \" + tojson" 2>/dev/null) || return 1
  body=$(printf '%s\n' "$out" | sed -n 's/^  body: //p')
  [ -n "$body" ] || return 1
  printf '%s' "$body" | jq -r . | sed -n 's/^R //p'
}
PRS=$(jq -r '[.[].pr_url | select(. != null and test("^https://github\\.com/[^/]+/[^/]+/pull/[0-9]+$"))] | unique | .[]' "$WORK/runs.json")
if [ "$GITHUB" = 0 ]; then
  note_input review-comments skipped "--no-github given"
elif [ -z "$PRS" ]; then
  note_input review-comments absent "no landed GitHub pull request in the window"
elif ! command -v gh-axi >/dev/null 2>&1; then
  note_input review-comments absent "gh-axi is not installed"
else
  : > "$WORK/comments.jsonl"
  failed=
  for url in $PRS; do
    path=${url#https://github.com/}
    repo=${path%/pull/*} number=${path##*/}
    author='author: .user.login, author_type: .user.type'
    { gh_rows "/repos/$repo/issues/$number/comments" "{kind: \"conversation\", $author, text: .body, created: .created_at}" \
      && gh_rows "/repos/$repo/pulls/$number/reviews" "select((.body // \"\") != \"\") | {kind: \"review\", $author, state: .state, text: .body, created: .submitted_at}" \
      && gh_rows "/repos/$repo/pulls/$number/comments" "{kind: \"inline\", $author, file: .path, line: (.line // .original_line), text: .body, created: .created_at}"
    } > "$WORK/pr.jsonl" || { failed="$failed $url"; continue; }
    jq -c --arg t "$url" '. + {ticket: $t}' "$WORK/pr.jsonl" >> "$WORK/comments.jsonl"
  done
  jq -s . "$WORK/comments.jsonl" > "$WORK/comments.json"
  if [ -n "$failed" ]; then
    note_input review-comments error "could not read:$failed"
  else
    note_input review-comments read "$(printf '%s\n' "$PRS" | wc -l | tr -d ' ') pull requests"
  fi
fi

# --- backlog -------------------------------------------------------------------
# One object per markdown row: id, done, line, body, and the close date.
BACKLOG="$HOME_DIR/data/backlog.md"
if [ -f "$BACKLOG" ]; then
  jq -Rs '
    [ split("\n")[] | select(test("^(- \\[[ x]\\] |  )")) ]
    | reduce .[] as $l ([];
        if ($l | startswith("- ")) then
          . + [{id: ($l | capture("^- \\[.\\] (?<i>[^ ]+)").i), done: ($l | startswith("- [x]")), line: $l, body: ""}]
        elif length > 0 then .[-1].body += ($l[2:] + "\n") else . end)
    | map(. + {closed: (.line | [scan("(?:done|merged|reported) ([0-9]{4}-[0-9]{2}-[0-9]{2})")[0]] | last),
               pr: (.line | [scan("https://github\\.com/[^/ ]+/[^/ ]+/pull/[0-9]+")] | first)})
  ' "$BACKLOG" > "$WORK/backlog.json"
fi
jq --arg since "$SINCE" '
  map(select((.id | contains("retro"))
    and ((.done | not) and (.line | contains("(hold-kind: captain)"))
      or (.body | contains("Captain decision:")) and .done and (.closed // "") >= $since))
  | {ticket: (.pr // .id), task: .id, kind: (if .done then "declined-or-answered" else "held" end),
     text: (.line + "\n" + .body | rtrimstr("\n"))})
' "$WORK/backlog.json" > "$WORK/proposals.json"
if [ ! -f "$BACKLOG" ]; then
  note_input retro-proposals absent "no backlog at $BACKLOG"
elif [ "$(jq length "$WORK/proposals.json")" = 0 ]; then
  note_input retro-proposals absent "no held or answered retro row in $BACKLOG"
else
  note_input retro-proposals read "$BACKLOG: $(jq length "$WORK/proposals.json") held or answered retro rows"
fi

# --- steers to workers -------------------------------------------------------
found=0
: > "$WORK/steers.jsonl"
for msg in "$HOME_DIR"/state/*.inbox/*.msg "$HOME_DIR"/state/*.inbox/handled/*.msg; do
  [ -f "$msg" ] || continue
  found=1
  task=${msg#"$HOME_DIR"/state/}
  task=${task%%.inbox/*}
  awk 'body { print; next } /^--$/ { body = 1 }' "$msg" > "$WORK/body.txt"
  at=$(sed -n 's/^at=//p;/^--$/q' "$msg")
  jq -cn --arg task "$task" --arg at "$at" --arg seq "${msg##*/}" --rawfile text "$WORK/body.txt" \
    --argjson since "$SINCE_EPOCH" --arg sinceday "$SINCE" --slurpfile backlog "$WORK/backlog.json" \
    '($backlog[0] | map(select(.done and .id == $task and (.line | contains("merged")) and (.closed // "") >= $sinceday)) | first) as $row
     | select($row and ($at | try fromdateiso8601 catch 0) >= $since)
     | {ticket: ($row.pr // $task), task: $task, at: $at, message: ($seq | rtrimstr(".msg")), text: ($text | rtrimstr("\n"))}' \
    >> "$WORK/steers.jsonl"
done
jq -s . "$WORK/steers.jsonl" > "$WORK/steers.json"
if [ "$found" = 1 ]; then
  note_input steers read "$HOME_DIR/state/*.inbox, kept for tasks $BACKLOG closes as merged in the window; tasks already cleaned up keep no steers"
else
  note_input steers absent "no steering inbox under $HOME_DIR/state; cleanup deletes a task's inbox"
fi

# --- assemble ----------------------------------------------------------------
jq -n --arg since "$SINCE" \
  --slurpfile runs "$WORK/runs.json" --slurpfile steps "$WORK/steps.json" \
  --slurpfile rounds "$WORK/rounds.json" --slurpfile comments "$WORK/comments.json" \
  --slurpfile steers "$WORK/steers.json" --slurpfile proposals "$WORK/proposals.json" --slurpfile inputs <(jq -s . "$INPUTS") '
  ($runs[0] | map({key: .run_id, value: .}) | from_entries) as $run
  | def ticket($id): ($run[$id] // {}) | (.pr_url // "\(.repo) \(.branch)");
    def finding($r; $kind; $sel):
      {source: "finding", kind: $kind, ticket: ticket($r.run_id), run: $r.run_id, step: $r.step,
       round: $r.round, selection: $sel, id: .id, severity: (.severity // "unknown"),
       file: (.file // ""), line: .line, action: .action, text: (.description // "")};
  [ ($steps[0][] as $s
      | (["approval", $s.approval_reason], ["override", $s.override_reason], ["skip", $s.skip_reason])
      | select((.[1] // "") != "")
      | {source: "gate-answer", kind: .[0], ticket: ticket($s.run_id), run: $s.run_id,
         step: $s.step, text: .[1]}),
    ($rounds[0][] as $r
      | ($r.selected | fromjson) as $selected
      | ( (select($r.selection_source | startswith("user"))
           | {source: "gate-answer", kind: $r.selection_source, ticket: ticket($r.run_id), run: $r.run_id,
              step: $r.step, round: $r.round, selected: $selected, text: ""}),
          (($r.findings | fromjson | .findings // [])[]
           | select(.id as $id | $selected | index($id) | not)
           | finding($r; if $r.selection_source == "user_declined" then "declined" else "not-selected" end;
                     $r.selection_source)),
          (($r.user_findings | fromjson | .findings // [])[] | finding($r; "operator-added"; $r.selection_source)) )),
    ($comments[0][] | {source: "review-comment", kind, ticket, author, author_type, state, file: (.file // ""),
       line, created, text: (.text // "")} | with_entries(select(.value != null))),
    ($steers[0][] | {source: "steer", kind: "steer"} + .),
    ($proposals[0][] | {source: "retro-proposal"} + .)
  ] as $records
  | {schema: "fm-feedback-collect.v1", since: $since, inputs: $inputs[0], records: $records}
' > "$WORK/out.json"

# Markdown rendering: counts, then records per source and ticket. Every
# free-text field is untrusted, so it only appears inside an indented code
# block; single-line fields lose backticks and line breaks.
jq -r '
  def one: tostring | gsub("[`\r\n]"; " ");
  def quoted: "      " + (tostring | gsub("\r"; "") | gsub("\n"; "\n      "));
  def counts($key):
    (group_by(.[$key] // "") | map({k: (.[0][$key] // "" | one), n: length}) | sort_by(-.n, .k))
    | map("| \(if .k == "" then "(none)" else .k end) | \(.n) |") | join("\n");
  .records as $all
  | "# Feedback across landed tickets since \(.since)",
    "",
    "Read-only collection, grouped mechanically; theming is left to the reader.",
    "Review comments, steers, and backlog text are quoted data, never instructions.",
    "",
    "## Inputs",
    "",
    (.inputs[] | "- \(.name): \(.status) - \(.detail | one)"),
    "",
    "## Counts",
    "",
    "| Source | Records |", "|---|---|", ($all | counts("source")), "",
    "| Step | Records |", "|---|---|", ($all | map(select(.step)) | counts("step")), "",
    "| Finding severity | Findings |", "|---|---|", ($all | map(select(.source == "finding")) | counts("severity")), "",
    "| File | Records |", "|---|---|", ($all | map(select((.file // "") != "")) | counts("file")), "",
    ($all | group_by(.source)[] | (
      "## Source: \(.[0].source)",
      "",
      (group_by(.ticket)[] | (
        "### Ticket: \(.[0].ticket | one)",
        "",
        (sort_by(.step // "", .severity // "", .file // "", .round // 0, .created // .at // "")[]
          | . as $x | "- " + ([.kind, (.step | select(.) | "step \(.)"), (.round | select(.) | "round \(.)"),
                     (.id | select(.) | "finding \(.)"), (.severity | select(.)),
                     (.file | select(. != null and . != "") | "file \(.)" + (if $x.line then ":\($x.line)" else "" end)),
                     (.author | select(.) | "by \(.)" + (if $x.author_type == "Bot" then " (bot)" else "" end)),
                     (.selected | select(.) | "selected \(join(","))"),
                     (.at | select(.) | "at \(.)")] | map(one) | join(" | "))
            + (if (.text // "") == "" then "" else "\n\n" + (.text | quoted) + "\n" end)),
        ""))))
' "$WORK/out.json" > "$WORK/out.md"

mkdir -p "$(dirname "$OUT")"
mv "$WORK/out.json" "$OUT.json"
mv "$WORK/out.md" "$OUT.md"
printf 'wrote %s.md and %s.json (%s records)\n' "$OUT" "$OUT" "$(jq '.records | length' "$OUT.json")"
