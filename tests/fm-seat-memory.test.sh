#!/usr/bin/env bash
# tests/fm-seat-memory.test.sh - opt-in seat memory (bin/fm-seat-lib.sh):
#   1. Seat indexing: a path maps to its longest defined prefix, else its first
#      component, else `root`; a decision record is indexed under the seats its
#      `Seats:` line names, else the brief's `Task seats:`, else the paths its
#      branch changed, once per seat however often teardown runs.
#   2. Brief feed bounds: newest first, one entry per task, at most the
#      configured record count, line count, and bytes, with every record line
#      indented so it cannot forge a machine-read brief line.
#   3. Briefs: with config/seat-memory a ship and a scout brief carry the feed
#      and the decisions clause; without it --seat and --path change nothing.
#   4. Spawn: with the flag a Claude launch carries --session-id and the task
#      record names the same id; without it neither appears.
# bin/fm-teardown.sh's archiving is covered in tests/fm-teardown.test.sh and
# the recap's use of the id in tests/fm-predecessor-recap.test.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-seat-lib.sh"
fm_git_identity fmtest fmtest@example.invalid

BRIEF="$ROOT/bin/fm-brief.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-seat-memory)
mkdir -p "$TMP_ROOT"
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)

new_home() {  # <name> [on] -> prints the home
  local home=$TMP_ROOT/$1
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects"
  [ "${2:-}" != on ] || : > "$home/config/seat-memory"
  printf '%s\n' "$home"
}

write_record() {  # <data> <task-id> <seats-line-or-empty> <headline>
  mkdir -p "$1/$2"
  {
    [ -z "$3" ] || printf 'Seats: %s\n\n' "$3"
    printf '## %s\nReason: because %s\nRejected: the other way\nUNVERIFIED: none\n' "$4" "$2"
  } > "$1/$2/decisions.md"
}

index_line() {  # <data> <project> <epoch> <seat> <task-id>
  mkdir -p "$1/seats/$2"
  printf '%s\t%s\t%s\tship\n' "$3" "$4" "$5" >> "$1/seats/$2/index.tsv"
}

test_path_maps_to_longest_defined_prefix_else_first_component() {
  local home defs
  home=$(new_home seat-for-path)
  defs="$home/data/seats/proj/seats.txt"
  mkdir -p "${defs%/*}"
  printf '%s\n' '# seat definitions' 'tooling bin' 'spawn bin/fm-spawn.sh bin/backends/' > "$defs"
  [ "$(fm_seat_for_path "$defs" bin/fm-spawn.sh)" = spawn ] || fail "a file prefix should beat its directory"
  [ "$(fm_seat_for_path "$defs" bin/backends/herdr.sh)" = spawn ] || fail "a directory prefix should cover what is below it"
  [ "$(fm_seat_for_path "$defs" bin/fm-brief.sh)" = tooling ] || fail "a shorter prefix should still match"
  [ "$(fm_seat_for_path "$defs" bin/fm-spawn.sh.bak)" = tooling ] || fail "a prefix must match whole path components"
  [ "$(fm_seat_for_path "$defs" docs/configuration.md)" = docs ] || fail "an undefined path should fall back to its first component"
  [ "$(fm_seat_for_path "$defs" README.md)" = root ] || fail "a top-level file should fall back to root"
  [ "$(fm_seat_for_path "$home/none.txt" ./skills/x/SKILL.md)" = skills ] || fail "no definitions should still give the first component"
  pass "a path maps to its longest defined prefix, else its first component, else root"
}

test_archive_indexes_named_seats_once() {
  local home data out lines
  home=$(new_home archive-named on)
  data=$home/data
  write_record "$data" t-named "bin, docs" "Use awk"
  out=$(fm_seat_archive "$data" proj t-named ship)
  assert_contains "$out" "bin" "archive should report the bin seat"
  assert_contains "$out" "docs" "archive should report the docs seat"
  fm_seat_archive "$data" proj t-named ship >/dev/null
  lines=$(wc -l < "$data/seats/proj/index.tsv" | tr -d ' ')
  [ "$lines" = 2 ] || fail "a repeated archive must not add index lines (got $lines)"
  awk -F'\t' '$2 == "bin" && $3 == "t-named" && $4 == "ship" && $1 ~ /^[0-9]+$/ { f = 1 } END { exit !f }' "$data/seats/proj/index.tsv" \
    || fail "index line shape is wrong: $(cat "$data/seats/proj/index.tsv")"
  mkdir -p "$data/t-empty"
  : > "$data/t-empty/decisions.md"
  fm_seat_archive "$data" proj t-empty ship >/dev/null
  fm_seat_archive "$data" proj t-missing ship >/dev/null
  ! grep -q 't-empty\|t-missing' "$data/seats/proj/index.tsv" || fail "an empty or missing record must index nothing"
  pass "a record is indexed once per named seat, and an empty or missing one not at all"
}

test_archive_falls_back_to_brief_then_changed_paths() {
  local home data proj wt out
  home=$(new_home archive-fallback on)
  data=$home/data
  write_record "$data" t-brief "" "From brief"
  printf '%s\n' '# Seat decisions' 'Task seats: spawn' > "$data/t-brief/brief.md"
  out=$(fm_seat_archive "$data" proj t-brief ship)
  [ "$out" = spawn ] || fail "an untagged record should take the brief's seats (got '$out')"

  proj=$TMP_ROOT/fallback-proj
  wt=$TMP_ROOT/fallback-wt
  fm_git_worktree "$proj" "$wt" fm/t-paths
  mkdir -p "$wt/bin" "$wt/docs"
  printf 'x\n' > "$wt/bin/fm-new.sh"
  printf 'y\n' > "$wt/docs/new.md"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m change
  mkdir -p "$data/seats/proj"
  printf '%s\n' 'newtool bin/fm-new.sh' > "$data/seats/proj/seats.txt"
  write_record "$data" t-paths "" "From paths"
  out=$(fm_seat_archive "$data" proj t-paths ship "$wt" main)
  assert_contains "$out" "newtool" "a changed file should map through its seat definition"
  assert_contains "$out" "docs" "an undefined changed file should map to its first component"
  git -C "$proj" merge -q --ff-only fm/t-paths
  write_record "$data" t-landed "" "After landing"
  out=$(fm_seat_archive "$data" proj t-landed ship "$wt" main)
  assert_contains "$out" "newtool" "a branch already fast-forwarded into its base should still map its changes"
  pass "an untagged record falls back to the brief's seats, then to the paths its branch changed"
}

test_feed_is_newest_first_deduplicated_and_bounded() {
  local home data out n
  home=$(new_home feed-bounds on)
  data=$home/data
  for n in 1 2 3 4 5 6 7; do
    write_record "$data" "t$n" "bin" "Decision $n"
    index_line "$data" proj "100000000$n" bin "t$n"
  done
  index_line "$data" proj 1000000007 docs t7
  index_line "$data" proj 1000000008 bin t-gone
  out=$(CONFIG=$home/config fm_seat_feed_block "$data" proj bin docs)
  assert_contains "$out" "Task seats: bin docs" "the feed must name the task's seats"
  case "$out" in "# Seat decisions"*) ;; *) fail "the feed must open with its heading: $out" ;; esac
  [ "$(printf '%s\n' "$out" | grep -c '^- ')" = 5 ] || fail "the feed must keep at most 5 records: $out"
  [ "$(printf '%s\n' "$out" | grep -c "\`t7\`")" = 1 ] || fail "a task under two seats must appear once: $out"
  printf '%s\n' "$out" | grep "\`t7\`" | grep 'bin' | grep -q 'docs' || fail "a task under two seats must name both: $out"
  [ "$(printf '%s\n' "$out" | grep '^- ' | head -1 | grep -c "\`t7\`")" = 1 ] || fail "the newest record must come first: $out"
  case "$out" in *"\`t2\`"* | *"\`t1\`"* | *t-gone*) fail "older or missing records must be left out: $out" ;; esac
  assert_contains "$out" "2 older or larger record(s) not shown" "the cut must be named"
  assert_contains "$out" "$data/t7/decisions.md" "each record must link its full file"
  printf '%s\n' "$out" | grep -q '^## \|^# Task\|^Seats:' && fail "record lines must be indented: $out"

  out=$(CONFIG=$home/config FM_SEAT_FEED_COUNT=1 FM_SEAT_FEED_LINES=2 fm_seat_feed_block "$data" proj bin)
  [ "$(printf '%s\n' "$out" | grep -c '^  ')" = 3 ] || fail "a record must keep only the configured lines plus the cut note: $out"
  assert_contains "$out" "[cut; the full record is at the path above]" "a cut record must say so"

  write_record "$data" t-big bin "$(printf 'x%.0s' $(seq 1 900))"
  index_line "$data" proj 1000000009 bin t-big
  out=$(CONFIG=$home/config FM_SEAT_FEED_MAX_BYTES=600 fm_seat_feed_block "$data" proj bin)
  n=$(printf '%s\n' "$out" | sed -n '/^- /,$p' | grep -v 'not shown; the index is' | LC_ALL=C wc -c | tr -d ' ')
  [ "$n" -le 600 ] || fail "the feed's record entries must stay within the byte bound (got $n bytes)"
  assert_contains "$out" "\`t-big\`" "an oversized newest record must still be shown, cut"
  assert_contains "$out" "[cut to fit" "an oversized record must say it was cut"

  out=$(CONFIG=$TMP_ROOT/no-config fm_seat_feed_block "$data" proj bin)
  [ -z "$out" ] || fail "the feed must be empty with the flag off: $out"
  out=$(CONFIG=$home/config fm_seat_feed_block "$data" proj)
  [ -z "$out" ] || fail "the feed must be empty with no seat named: $out"
  pass "the feed is newest first, one entry per task, bounded by count, lines, and bytes, and off without the flag"
}

test_flag_off_brief_is_unchanged_by_seat_options() {
  local home a b
  home=$(new_home brief-off)
  FM_HOME=$home "$BRIEF" off-a proj --mode no-mistakes >/dev/null 2>&1 || fail "plain ship brief failed"
  FM_HOME=$home "$BRIEF" off-b proj --mode no-mistakes --seat bin --path docs/x.md >/dev/null 2>&1 || fail "seat ship brief failed"
  a=$(sed 's/off-a/ID/g' "$home/data/off-a/brief.md")
  b=$(sed 's/off-b/ID/g' "$home/data/off-b/brief.md")
  [ "$a" = "$b" ] || fail "with the flag off, --seat and --path must not change the ship brief"
  FM_HOME=$home "$BRIEF" off-c proj --scout >/dev/null 2>&1 || fail "plain scout brief failed"
  FM_HOME=$home "$BRIEF" off-d proj --scout --seat bin >/dev/null 2>&1 || fail "seat scout brief failed"
  a=$(sed 's/off-c/ID/g' "$home/data/off-c/brief.md")
  b=$(sed 's/off-d/ID/g' "$home/data/off-d/brief.md")
  [ "$a" = "$b" ] || fail "with the flag off, --seat must not change the scout brief"
  ! grep -q 'decisions.md\|Seat decisions' "$home/data/off-a/brief.md" "$home/data/off-c/brief.md" \
    || fail "a flag-off brief must not mention the decision record"
  pass "with the flag off, --seat and --path leave ship and scout briefs byte-identical"
}

test_flag_on_briefs_carry_feed_and_decisions_clause() {
  local home out
  home=$(new_home brief-on on)
  write_record "$home/data" t-old bin "Keep the lib small"
  index_line "$home/data" proj 1000000001 bin t-old
  FM_HOME=$home "$BRIEF" on-ship proj --mode direct-PR --seat bin >/dev/null 2>&1 || fail "flag-on ship brief failed"
  out=$(cat "$home/data/on-ship/brief.md")
  assert_contains "$out" $'# Seat decisions\nTask seats: bin' "the ship brief must carry the feed"
  assert_contains "$out" "  ## Keep the lib small" "the feed must carry the earlier record"
  assert_contains "$out" "$home/data/on-ship/decisions.md" "the ship definition of done must ask for the decisions file"
  [ "$(grep -c '^# Task$' "$home/data/on-ship/brief.md")" = 1 ] || fail "the feed must not add a # Task heading"
  FM_HOME=$home "$BRIEF" on-scout proj --scout --path bin/x.sh >/dev/null 2>&1 || fail "flag-on scout brief failed"
  out=$(cat "$home/data/on-scout/brief.md")
  assert_contains "$out" "Task seats: bin" "a --path must resolve to its seat"
  assert_contains "$out" "$home/data/on-scout/decisions.md" "the scout definition of done must ask for the decisions file"
  FM_HOME=$home "$BRIEF" on-none proj --mode direct-PR >/dev/null 2>&1 || fail "flag-on brief without seats failed"
  ! grep -q '^# Seat decisions' "$home/data/on-none/brief.md" || fail "a brief naming no seat must carry no feed"
  grep -q 'decisions.md' "$home/data/on-none/brief.md" || fail "a brief naming no seat must still ask for the decisions file"
  out=$(FM_HOME=$home "$BRIEF" bad proj --mode direct-PR --seat '../x' 2>&1) && fail "an invalid seat must be refused"
  assert_contains "$out" "--seat must match" "the refusal must name the rule"
  pass "with the flag on, ship and scout briefs carry the feed and ask for the decisions file"
}

# Fake tmux for a launch: answers the pane-path query and logs every sent text.
make_spawn_fakebin() {
  local fakebin
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  send-keys)
    for a in "$@"; do
      case "$a" in
        ". '"*"'") staged=${a#". '"}; staged=${staged%"'"}; [ ! -f "$staged" ] || a=$(cat "$staged") ;;
      esac
      printf '%s\n' "$a" >> "$FM_FAKE_LAUNCH_LOG"
    done ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse
  printf '%s\n' "$fakebin"
}

run_spawn_case() {  # <name> <on|off> -> prints home|launchlog
  local name=$1 home proj wt fakebin log id=$1-z1
  home=$(new_home "$name" "$2")
  proj=$TMP_ROOT/$name-proj
  wt=$TMP_ROOT/$name-wt
  log=$TMP_ROOT/$name-launch.log
  : > "$log"
  fakebin=$(make_spawn_fakebin "$TMP_ROOT/$name-fake")
  printf 'claude\n' > "$home/config/crew-harness"
  printf '%s\n' "$$" > "$home/state/.lock"
  touch "$home/state/.last-watcher-beat"
  fm_git_worktree "$proj" "$wt" "wt-$name"
  mkdir -p "$home/data/$id" "$home/user-home"
  printf '%s\n' '# Task' "## Captain's intent" "Record the session of $id." '' '## Firstmate spec' 'Check the launch.' > "$home/data/$id/brief.md"
  env -u FM_TRACE_CONTEXT FM_ROOT_OVERRIDE='' FM_HOME="$home" HOME="$home/user-home" CLAUDE_CONFIG_DIR='' \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$wt" TMUX="fake,1,0" \
    FM_FAKE_LAUNCH_LOG="$log" PATH="$fakebin:$PATH" \
    "$SPAWN" "$id" "$proj" --mode no-mistakes --yolo off > "$TMP_ROOT/$name-spawn.out" 2>&1 \
    || fail "$name: spawn failed: $(cat "$TMP_ROOT/$name-spawn.out")"
  printf '%s|%s\n' "$home/state/$id.meta" "$log"
}

test_spawn_records_the_claude_session_id_only_with_the_flag() {
  local rec meta log sid
  rec=$(run_spawn_case spawn-on on)
  meta=${rec%%|*}
  log=${rec#*|}
  sid=$(sed -n 's/^claude_session_id=//p' "$meta")
  case "$sid" in
    ????????-????-????-????-????????????) ;;
    *) fail "a flag-on Claude spawn must record a session uuid (got '$sid')" ;;
  esac
  grep -qF -- "--session-id $sid " "$log" || fail "the Claude launch must carry the recorded session id: $(cat "$log")"
  ! grep -q '^claude_prior_session_ids=' "$meta" || fail "a fresh spawn has no earlier session"

  rec=$(run_spawn_case spawn-off off)
  meta=${rec%%|*}
  log=${rec#*|}
  ! grep -q '^claude_session_id=\|^claude_prior_session_ids=' "$meta" || fail "a flag-off spawn must record no session id"
  grep -q 'claude' "$log" || fail "the flag-off spawn must still launch"
  ! grep -q -- '--session-id' "$log" || fail "a flag-off launch must carry no --session-id"
  pass "a Claude spawn records and launches with one session id with the flag, and neither without it"
}

test_path_maps_to_longest_defined_prefix_else_first_component
test_archive_indexes_named_seats_once
test_archive_falls_back_to_brief_then_changed_paths
test_feed_is_newest_first_deduplicated_and_bounded
test_flag_off_brief_is_unchanged_by_seat_options
test_flag_on_briefs_carry_feed_and_decisions_clause
test_spawn_records_the_claude_session_id_only_with_the_flag

echo "# all fm-seat-memory tests passed"
