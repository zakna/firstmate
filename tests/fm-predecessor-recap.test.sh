#!/usr/bin/env bash
# tests/fm-predecessor-recap.test.sh - the predecessor recap a relaunched
# worker reads (bin/fm-predecessor-recap.sh), run against fixture Claude
# transcripts and terminal captures.
#   1. A transcript present: the newest messages render oldest first, while the
#      launch brief, thinking, sidechain, and meta entries are left out.
#   2. A transcript absent: no transcript, one older than the previous worker,
#      or one recording another cwd each gives one `No recap:` line.
#   3. A transcript truncated: long items are cut, --count keeps the newest,
#      and --max-bytes drops the oldest until the body fits.
#   4. Secrets: credential-shaped strings are redacted and a call touching a
#      .env file has its input and result omitted.
#   5. Scrollback: a harness without a read transcript falls back to the
#      terminal capture with control sequences stripped.
#   6. Provenance: only the root of the previous worker's recorded account is
#      read, and no transcript is read when its start time is unknown.
#   7. A byte bound below the safe minimum still terminates.
#   8. Only a bounded tail of a large transcript is read, and a result whose
#      call lies before that tail is omitted.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-timeout-lib.sh"

RECAP="$ROOT/bin/fm-predecessor-recap.sh"
TMP_ROOT=$(fm_test_tmproot fm-predecessor-recap)
mkdir -p "$TMP_ROOT"
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)

# A worktree and its Claude project directory under <dir>/claude.
new_case() {  # <name> -> prints the case dir
  local dir=$TMP_ROOT/$1
  mkdir -p "$dir/wt" "$dir/claude/projects/$(printf '%s' "$dir/wt" | sed 's/[^A-Za-z0-9]/-/g')"
  printf '%s\n' "$dir"
}

transcript_path() {  # <dir> <session>
  printf '%s/claude/projects/%s/%s.jsonl\n' "$1" "$(printf '%s' "$1/wt" | sed 's/[^A-Za-z0-9]/-/g')" "$2"
}

# One JSONL line per call; <content> is raw JSON for message.content.
entry() {  # <type> <cwd> <content> [extra-json-fields]
  printf '{"type":"%s","cwd":"%s","isSidechain":false%s,"message":{"role":"%s","content":%s}}\n' \
    "$1" "$2" "${4:+,$4}" "$1" "$3"
}

# Every fixture transcript is written after epoch 1, so --since 1 proves it is
# the previous worker's unless a case passes its own --since.
run_recap() {  # <dir> [extra args...]
  local dir=$1
  shift
  "$RECAP" --harness claude --worktree "$dir/wt" --claude-root "$dir/claude" --since 1 "$@" </dev/null
}

test_transcript_present_renders_newest_messages() {
  local dir t out
  dir=$(new_case present)
  t=$(transcript_path "$dir" s1)
  {
    entry user "$dir/wt" '"FIRSTMATE_OP: v1 launch-brief: # Task\nBRIEF BODY"'
    entry assistant "$dir/wt" '[{"type":"thinking","thinking":"PRIVATE THOUGHT"}]'
    entry assistant "$dir/wt" '[{"type":"text","text":"Reading the spawn script."}]'
    entry assistant "$dir/wt" '[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"grep -n relaunch bin/fm-spawn.sh"}}]'
    entry user "$dir/wt" '[{"type":"tool_result","tool_use_id":"t1","content":"47: --relaunch"}]'
    entry assistant "$dir/wt" '[{"type":"text","text":"SIDECHAIN TEXT"}]' '"isSidechain":true'
    entry user "$dir/wt" '[{"type":"text","text":"META TEXT"}]' '"isMeta":true'
    printf 'not json\n'
    entry user "$dir/wt" '"please also update the skill"'
  } >"$t"
  out=$(run_recap "$dir")
  expect_code 0 $? "a present transcript must exit 0"
  assert_contains "$out" "# Predecessor recap" "the section heading is missing"
  assert_contains "$out" "last 4 messages" "the count should name the rendered messages"
  assert_contains "$out" "- assistant: Reading the spawn script." "the assistant reply is missing"
  assert_contains "$out" "- tool call Bash: grep -n relaunch bin/fm-spawn.sh" "the tool call is missing"
  assert_contains "$out" "- tool result: 47: --relaunch" "the tool result is missing"
  assert_contains "$out" "- user: please also update the skill" "the user prompt is missing"
  case "$out" in *"BRIEF BODY"* | *"PRIVATE THOUGHT"* | *"SIDECHAIN TEXT"* | *"META TEXT"*) fail "the recap carried an excluded entry: $out" ;; esac
  case "$out" in *"Reading the spawn script."*"tool call Bash"*"please also update"*) ;; *) fail "the messages are not oldest first: $out" ;; esac
  pass "recap: a present transcript renders its newest messages oldest first"
}

test_newest_eligible_transcript_wins() {
  local dir old new out
  dir=$(new_case newest)
  old=$(transcript_path "$dir" a)
  new=$(transcript_path "$dir" b)
  entry user "$dir/wt" '"OLDER SESSION"' >"$old"
  entry user "$dir/wt" '"NEWER SESSION"' >"$new"
  touch -t 202601010000 "$old"
  out=$(run_recap "$dir")
  assert_contains "$out" "NEWER SESSION" "the newest transcript should be read"
  case "$out" in *"OLDER SESSION"*) fail "an older transcript leaked into the recap: $out" ;; esac
  pass "recap: the newest transcript for the worktree is the one read"
}

test_transcript_absent_gives_one_reason_line() {
  local dir out t
  dir=$(new_case absent)
  out=$(run_recap "$dir")
  expect_code 0 $? "an absent transcript must exit 0"
  assert_contains "$out" "No recap: no Claude session transcript for this worktree was written after the previous worker started" "absent transcript reason"
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] || fail "an absent recap should be the heading plus one line: $out"

  t=$(transcript_path "$dir" stale)
  entry user "$dir/wt" '"EARLIER TASK IN THIS SLOT"' >"$t"
  touch -t 202601010000 "$t"
  out=$(run_recap "$dir" --since "$(date +%s)")
  assert_contains "$out" "No recap: no Claude session transcript" "a transcript older than the previous worker must not be read"
  case "$out" in *"EARLIER TASK"*) fail "an earlier task's transcript leaked: $out" ;; esac

  entry user "/somewhere/else" '"OTHER CWD"' >"$t"
  out=$(run_recap "$dir")
  assert_contains "$out" "No recap: no Claude session transcript" "a transcript for another cwd must not be read"

  entry user "$dir/wt" '"FIRSTMATE_OP: v1 launch-brief: only the brief"' >"$t"
  out=$(run_recap "$dir")
  assert_contains "$out" "No recap: the previous worker's Claude session transcript holds no messages after its launch instructions" "empty transcript reason"
  pass "recap: an absent, stale, foreign, or empty transcript gives one reason line"
}

test_transcript_truncated_and_bounded() {
  local dir t out long i body
  dir=$(new_case truncated)
  t=$(transcript_path "$dir" s1)
  long=$(printf 'x%.0s' $(seq 1 2000))
  {
    for i in $(seq 1 30); do
      entry assistant "$dir/wt" "[{\"type\":\"text\",\"text\":\"step $i\"}]"
    done
    entry assistant "$dir/wt" '[{"type":"tool_use","id":"big","name":"Bash","input":{"command":"cat big.log"}}]'
    entry user "$dir/wt" "[{\"type\":\"tool_result\",\"tool_use_id\":\"big\",\"content\":\"$long\"}]"
  } >"$t"
  out=$(run_recap "$dir" --count 5)
  assert_contains "$out" "last 5 messages" "--count should bound the messages"
  assert_contains "$out" "- assistant: step 28" "the newest messages should be kept"
  case "$out" in *"step 27"*) fail "--count kept an older message: $out" ;; esac
  assert_contains "$out" "[truncated]" "a long tool result should be cut"
  printf '%s\n' "$out" | awk 'length > 360 { bad = 1 } END { exit !bad }' && fail "a tool result exceeded its cut"

  out=$(run_recap "$dir" --count 30 --max-bytes 200)
  body=$(printf '%s\n' "$out" | grep '^- ')
  [ "$(printf '%s\n' "$body" | wc -c | tr -d ' ')" -le 200 ] || fail "the body exceeded --max-bytes: $body"
  assert_contains "$body" "- tool result: xxx" "the byte bound should keep the newest item, cut to fit"
  case "$body" in *"step 1"*) fail "the byte bound kept the oldest item: $body" ;; esac
  out=$(FM_PREDECESSOR_RECAP_COUNT=2 run_recap "$dir")
  assert_contains "$out" "last 2 messages" "FM_PREDECESSOR_RECAP_COUNT should set the default count"
  pass "recap: long items are cut and the recap is bounded by count and bytes"
}

test_secrets_are_redacted_and_dotenv_omitted() {
  local dir t out
  dir=$(new_case secrets)
  t=$(transcript_path "$dir" s1)
  {
    entry assistant "$dir/wt" '[{"type":"text","text":"key sk-ant-abcdefghijklmnopqrstuvwx and ghp_abcdefghijklmnopqrstuvwxyz0123 and API_TOKEN=hunter2secret and https://bob:pa55word@example.com/x"}]'
    entry assistant "$dir/wt" '[{"type":"text","text":"PASSWORD=\"correct horse battery staple\" then client_secret: '"'"'two quoted words'"'"' done"}]'
    entry assistant "$dir/wt" '[{"type":"text","text":"curl -H \"Authorization: Basic dXNlcjpwYXNzd29yZA==\" -H \"Proxy-Authorization: basic cHJveHk6c2VjcmV0\" url"}]'
    entry assistant "$dir/wt" '[{"type":"tool_use","id":"f1","name":"Bash","input":{"command":"deploy --password flagpass1 --token flagtok22 --api-key \"flag key words\" && mysql -u root -p dbpass333"}}]'
    entry user "$dir/wt" '[{"type":"tool_result","tool_use_id":"f1","content":"ok"}]'
    entry assistant "$dir/wt" '[{"type":"tool_use","id":"e1","name":"Bash","input":{"command":"cat .env"}}]'
    entry user "$dir/wt" '[{"type":"tool_result","tool_use_id":"e1","content":"DATABASE_URL=dotenv-value-here"}]'
    entry assistant "$dir/wt" '[{"type":"tool_use","id":"e2","name":"Read","input":{"file_path":"/repo/.env.local"}}]'
    entry user "$dir/wt" '[{"type":"tool_result","tool_use_id":"e2","content":[{"type":"text","text":"SECOND_DOTENV_VALUE"}]}]'
  } >"$t"
  out=$(run_recap "$dir")
  case "$out" in *sk-ant-abc* | *ghp_abc* | *hunter2secret* | *pa55word* | *dotenv-value-here* | *SECOND_DOTENV_VALUE* | *horse* | *battery* | *staple* | *quoted\ words* | *dXNlcjpwYXNzd29yZA* | *cHJveHk6c2VjcmV0* | *flagpass1* | *flagtok22* | *flag\ key\ words* | *dbpass333*) fail "a secret reached the recap: $out" ;; esac
  assert_contains "$out" "PASSWORD=[redacted] then client_secret: [redacted] done" "a quoted value with spaces should be redacted whole"
  assert_contains "$out" "Authorization: Basic [redacted]\" -H \"Proxy-Authorization: basic [redacted]\"" "Basic authorization values should be redacted"
  assert_contains "$out" "deploy --password [redacted] --token [redacted] --api-key [redacted] && mysql -u root -p [redacted]" "a space-separated credential flag's value should be redacted"
  assert_contains "$out" "API_TOKEN=[redacted]" "an assignment value should be redacted"
  assert_contains "$out" "- tool call Bash: [omitted: touches a .env file]" "a .env call's input should be omitted"
  assert_contains "$out" "- tool result: [omitted: output of a call that touches a .env file]" "a .env call's result should be omitted"
  pass "recap: credential-shaped strings are redacted and .env contents omitted"
}

test_scrollback_fallback_for_other_harnesses() {
  local dir out esc
  dir=$(new_case scrollback)
  esc=$(printf '\033')
  printf '%s\n' "line one" "" "${esc}[31mred line${esc}[0m" "token: abcdefghijkl" >"$dir/capture"
  out=$("$RECAP" --harness codex --worktree "$dir/wt" --scrollback "$dir/capture" </dev/null)
  assert_contains "$out" "transcript is not available (firstmate reads no codex session transcript)" "the fallback should say why"
  assert_contains "$out" "> line one" "the capture should be quoted"
  assert_contains "$out" "> red line" "control sequences should be stripped"
  case "$out" in *"$esc"*) fail "an escape sequence reached the recap" ;; esac
  case "$out" in *abcdefghijkl*) fail "a token in the capture reached the recap: $out" ;; esac

  : >"$dir/empty"
  out=$("$RECAP" --harness codex --worktree "$dir/wt" --scrollback "$dir/empty" </dev/null)
  assert_contains "$out" "No recap: firstmate reads no codex session transcript, and the previous worker's terminal held no readable text." "an empty capture gives one line"
  out=$("$RECAP" --harness codex --worktree "$dir/wt" </dev/null)
  assert_contains "$out" "No recap: firstmate reads no codex session transcript, and the previous worker's terminal could not be read." "no capture gives one line"
  pass "recap: other harnesses fall back to the terminal capture, or say why there is none"
}

test_only_the_predecessor_account_root_is_read() {
  local dir t decoy out
  dir=$(new_case account)
  mkdir -p "$dir/pinned/projects" "$dir/home/.claude/projects"
  mv "$dir/claude/projects/"* "$dir/pinned/projects/"
  t="$dir/pinned/projects/$(printf '%s' "$dir/wt" | sed 's/[^A-Za-z0-9]/-/g')/s1.jsonl"
  entry user "$dir/wt" '"FROM THE PINNED ROOT"' >"$t"
  decoy="$dir/claude/projects/$(printf '%s' "$dir/wt" | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$decoy"
  entry user "$dir/wt" '"FROM ANOTHER ACCOUNT"' >"$decoy/s2.jsonl"
  out=$(run_recap "$dir" --claude-account "$dir/pinned")
  assert_contains "$out" "FROM THE PINNED ROOT" "the recorded account root should be read"
  case "$out" in *"FROM ANOTHER ACCOUNT"*) fail "another account's transcript leaked: $out" ;; esac

  mkdir -p "$dir/home/.claude/projects/$(printf '%s' "$dir/wt" | sed 's/[^A-Za-z0-9]/-/g')"
  entry user "$dir/wt" '"FROM THE ORDINARY ROOT"' >"$dir/home/.claude/projects/$(printf '%s' "$dir/wt" | sed 's/[^A-Za-z0-9]/-/g')/s3.jsonl"
  out=$(HOME="$dir/home" run_recap "$dir" --claude-account ordinary)
  assert_contains "$out" "FROM THE ORDINARY ROOT" "an ordinary account should read \$HOME/.claude"
  case "$out" in *"FROM ANOTHER ACCOUNT"* | *"FROM THE PINNED ROOT"*) fail "a non-ordinary root leaked: $out" ;; esac
  pass "recap: only the previous worker's recorded account root is read"
}

test_unknown_start_reads_no_transcript() {
  local dir t out
  dir=$(new_case unknown-start)
  t=$(transcript_path "$dir" s1)
  entry user "$dir/wt" '"POSSIBLY AN EARLIER TASK"' >"$t"
  out=$("$RECAP" --harness claude --worktree "$dir/wt" --claude-root "$dir/claude" </dev/null)
  assert_contains "$out" "No recap: the previous worker's start time is not recorded" "an unknown start should skip the transcript"
  case "$out" in *"POSSIBLY AN EARLIER TASK"*) fail "a transcript was read without a proven start: $out" ;; esac
  printf 'last terminal line\n' >"$dir/capture"
  out=$("$RECAP" --harness claude --worktree "$dir/wt" --claude-root "$dir/claude" --scrollback "$dir/capture" </dev/null)
  assert_contains "$out" "> last terminal line" "an unknown start should fall back to the terminal"
  case "$out" in *"POSSIBLY AN EARLIER TASK"*) fail "a transcript was read without a proven start: $out" ;; esac
  pass "recap: no transcript is read when the previous worker's start is unknown"
}

test_same_second_transcript_is_not_read() {
  local dir t out m
  dir=$(new_case same-second)
  t=$(transcript_path "$dir" s1)
  entry user "$dir/wt" '"WRITTEN IN THE START SECOND"' >"$t"
  if [ "$(uname)" = Darwin ]; then m=$(/usr/bin/stat -f %m "$t"); else m=$(stat -c %Y "$t"); fi
  out=$(run_recap "$dir" --since "$m")
  assert_contains "$out" "No recap: no Claude session transcript" "a transcript from the start second itself is ambiguous"
  case "$out" in *"WRITTEN IN THE START SECOND"*) fail "a same-second transcript was read: $out" ;; esac
  out=$(run_recap "$dir" --since "$((m - 1))")
  assert_contains "$out" "WRITTEN IN THE START SECOND" "a transcript written after the start second should be read"
  pass "recap: a transcript written in the start second is not read"
}

test_no_recorded_root_reads_no_transcript() {
  local dir t out
  dir=$(new_case no-root)
  t=$(transcript_path "$dir" s1)
  entry user "$dir/wt" '"SOME ROOT TRANSCRIPT"' >"$t"
  out=$(HOME="$dir" "$RECAP" --harness claude --worktree "$dir/wt" --since 1 </dev/null)
  assert_contains "$out" "No recap: the previous worker's Claude configuration folder is not recorded" "no recorded root should skip the transcript"
  case "$out" in *"SOME ROOT TRANSCRIPT"*) fail "a transcript was read without a recorded root: $out" ;; esac
  pass "recap: no transcript is read without a recorded Claude root"
}

test_large_transcript_reads_only_a_bounded_tail() {
  local dir t out i
  dir=$(new_case tail)
  t=$(transcript_path "$dir" s1)
  {
    entry assistant "$dir/wt" '[{"type":"text","text":"EARLY MARKER BEFORE THE TAIL"}]'
    entry assistant "$dir/wt" '[{"type":"tool_use","id":"cut","name":"Bash","input":{"command":"cat secrets.txt"}}]'
    for i in $(seq 1 40); do
      entry assistant "$dir/wt" "[{\"type\":\"text\",\"text\":\"padding $i padding padding padding padding\"}]"
    done
    entry user "$dir/wt" '[{"type":"tool_result","tool_use_id":"cut","content":"OUTPUT OF A CUT CALL"}]'
    entry assistant "$dir/wt" '[{"type":"text","text":"NEWEST REPLY"}]'
  } >"$t"
  out=$(FM_PREDECESSOR_RECAP_TAIL_BYTES=2000 run_recap "$dir" --count 3)
  assert_contains "$out" "- assistant: NEWEST REPLY" "the newest message should be in the tail"
  assert_contains "$out" "- tool result: [omitted: its call is outside the part of the transcript read]" "a result whose call was cut should be omitted"
  case "$out" in *"EARLY MARKER"* | *"OUTPUT OF A CUT CALL"*) fail "content before the tail, or a blind result, reached the recap: $out" ;; esac
  out=$(run_recap "$dir" --count 3)
  assert_contains "$out" "- tool result: OUTPUT OF A CUT CALL" "with the whole file read the call is known"
  pass "recap: only a bounded tail of a large transcript is read"
}

test_tiny_byte_bound_terminates() {
  local dir t out rc n body
  dir=$(new_case tiny)
  t=$(transcript_path "$dir" s1)
  entry assistant "$dir/wt" '[{"type":"text","text":"a reply long enough to need cutting under any tiny bound at all, well past sixty-four bytes"}]' >"$t"
  for n in 1 2 3; do
    out=$(fm_run_timed 20 "$RECAP" --harness claude --worktree "$dir/wt" --claude-root "$dir/claude" --since 1 --max-bytes "$n" </dev/null); rc=$?
    expect_code 0 "$rc" "--max-bytes $n must terminate"
    body=$(printf '%s\n' "$out" | grep '^- ')
    [ -n "$body" ] && [ "$(printf '%s\n' "$body" | wc -c | tr -d ' ')" -le 64 ] || fail "--max-bytes $n should be raised to the 64-byte minimum: $body"
  done
  pass "recap: a byte bound under the minimum is raised and terminates"
}

test_usage_errors_exit_2() {
  "$RECAP" --harness claude </dev/null >/dev/null 2>&1
  expect_code 2 $? "a missing --worktree is a usage error"
  "$RECAP" --harness claude --worktree /tmp --count x </dev/null >/dev/null 2>&1
  expect_code 2 $? "a non-numeric --count is a usage error"
  pass "recap: usage errors exit 2"
}

test_transcript_present_renders_newest_messages
test_newest_eligible_transcript_wins
test_transcript_absent_gives_one_reason_line
test_transcript_truncated_and_bounded
test_secrets_are_redacted_and_dotenv_omitted
test_scrollback_fallback_for_other_harnesses
test_only_the_predecessor_account_root_is_read
test_unknown_start_reads_no_transcript
test_tiny_byte_bound_terminates
test_same_second_transcript_is_not_read
test_no_recorded_root_reads_no_transcript
test_large_transcript_reads_only_a_bounded_tail
test_usage_errors_exit_2

echo "all fm-predecessor-recap tests passed"
