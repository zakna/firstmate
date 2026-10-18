#!/usr/bin/env bash
# tests/fm-seat-memory.test.sh - opt-in seat memory (bin/fm-seat-lib.sh):
#   1. Seat indexing: a path maps to its longest defined prefix, else its first
#      component, else `root`; a decision record is indexed under the seats its
#      `Seats:` line names, even an empty one, else the brief's `Task seats:`,
#      joined for a ship with the seats of the paths its branch changed (both
#      sides of a rename, never what it only took in from its base, also after
#      a fast-forward landing), once per seat however often teardown runs; a
#      project name with a space is encoded, not refused.
#   2. Brief feed bounds: newest first, one entry per task, at most the
#      configured record count, line count, and bytes, with every record line
#      indented so it cannot forge a machine-read brief line.
#   3. Briefs: with config/seat-memory a ship and a scout brief carry the feed
#      and the decisions clause; without it --seat and --path change nothing.
#   4. Spawn: with the flag a Claude launch carries --session-id and the task
#      record names the same id; without it neither appears.
#   5. Spawn feed: a brief naming no seat gets the feed at launch for the seats
#      its filled task text names, offered as likely areas, never `root` or
#      a heading word, else the newest records across all seats;
#      a brief scaffolded with --seat or --path keeps its own seats, with
#      the section rebuilt from the index at launch.
# bin/fm-teardown.sh's archiving is covered in tests/fm-teardown.test.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-seat-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-brief-heading-lib.sh"
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
  write_record "$data" t-union "launcher bin" "Tagged ship"
  out=$(fm_seat_archive "$data" proj t-union ship "$wt" main)
  for s in launcher bin newtool docs; do
    printf '%s\n' "$out" | grep -qx "$s" || fail "a tagged ship must be indexed under its named and changed-path seats; missing $s: $out"
  done
  write_record "$data" t-scout "bin" "Tagged scout"
  out=$(fm_seat_archive "$data" proj t-scout scout)
  [ "$out" = bin ] || fail "a scout must be indexed under its named seats only (got '$out')"
  pass "a ship's record joins its named seats with its changed-path seats, and a scout's keeps its named seats"
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

  mkdir -p "$data/t-long"
  for n in $(seq 1 20); do printf 'line %s\n' "$n"; done > "$data/t-long/decisions.md"
  index_line "$data" proj 1000000010 long t-long
  out=$(CONFIG=$home/config fm_seat_feed_block "$data" proj long)
  [ "$(printf '%s\n' "$out" | grep -c '^  ')" = 13 ] || fail "a record must keep only 12 lines plus the cut note: $out"
  assert_contains "$out" "[cut; the full record is at the path above]" "a cut record must say so"

  write_record "$data" t-big big "$(printf 'x%.0s' $(seq 1 5000))"
  index_line "$data" proj 1000000009 big t-big
  out=$(CONFIG=$home/config fm_seat_feed_block "$data" proj big)
  n=$(printf '%s\n' "$out" | sed -n '/^- /,$p' | grep -v 'not shown; the index is' | LC_ALL=C wc -c | tr -d ' ')
  [ "$n" -le 4000 ] || fail "the feed's record entries must stay within the byte bound (got $n bytes)"
  assert_contains "$out" "\`t-big\`" "an oversized newest record must still be shown, cut"
  assert_contains "$out" "[cut to fit" "an oversized record must say it was cut"

  out=$(CONFIG=$TMP_ROOT/no-config fm_seat_feed_block "$data" proj bin)
  [ -z "$out" ] || fail "the feed must be empty with the flag off: $out"
  out=$(CONFIG=$home/config fm_seat_feed_block "$data" proj)
  assert_contains "$out" "across all its seats" "with no seat named the feed must span all seats"
  ! printf '%s\n' "$out" | grep -q '^Task seats:' || fail "a feed naming no seat must not write a Task seats line: $out"
  out=$(CONFIG=$home/config fm_seat_feed_block "$data" no-such-proj)
  [ -z "$out" ] || fail "the feed must be empty with no seat named and no record: $out"
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
  assert_contains "$out" "that your work actually touched, or left empty; cleanup adds the seats of the files your branch changed" "the ship definition of done must leave changed areas to cleanup"
  [ "$(grep -c '^# Task$' "$home/data/on-ship/brief.md")" = 1 ] || fail "the feed must not add a # Task heading"
  FM_HOME=$home "$BRIEF" on-scout proj --scout --path bin/x.sh >/dev/null 2>&1 || fail "flag-on scout brief failed"
  out=$(cat "$home/data/on-scout/brief.md")
  assert_contains "$out" "Task seats: bin" "a --path must resolve to its seat"
  assert_contains "$out" "$home/data/on-scout/decisions.md" "the scout definition of done must ask for the decisions file"
  assert_contains "$out" "that you investigated, else the top-level directory of each area you investigated" "the scout definition of done must name the areas it investigated"
  case "$out" in *"cleanup adds the seats"*) fail "a scout changes no product files, so cleanup adds no seats: $out" ;; esac
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

run_spawn_case() {  # <name> <on|off> [<intent>] [<extra-brief-text>] [<setup-fn>] -> prints meta|launchlog
  local name=$1 home proj wt fakebin log id=$1-z1 intent=${3:-} extra=${4:-}
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
  [ -n "$intent" ] || intent="Record the session of $id."
  printf '%s\n' '# Task' "## Captain's intent" "$intent" '' '## Firstmate spec' 'Check the launch.' > "$home/data/$id/brief.md"
  [ -z "$extra" ] || printf '\n%s\n' "$extra" >> "$home/data/$id/brief.md"
  [ -z "${5:-}" ] || "$5" "$home/data" "$name-proj"
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

seed_spawn_seats() {  # <data> <project-key>
  mkdir -p "$1/seats/$2"
  printf '%s\n' 'launcher bin/fm-spawn.sh' > "$1/seats/$2/seats.txt"
  write_record "$1" t-launch launcher "Launch decision"
  index_line "$1" "$2" 1000000001 launcher t-launch
  write_record "$1" t-teardown teardown "Teardown decision"
  index_line "$1" "$2" 1000000002 teardown t-teardown
  write_record "$1" t-docs docs "Docs decision"
  index_line "$1" "$2" 1000000003 docs t-docs
}

test_spawn_infers_the_feed_from_the_filled_brief() {
  local rec meta lb out
  rec=$(run_spawn_case infer-name on "Make Teardown faster." "" seed_spawn_seats)
  meta=${rec%%|*}
  lb=${meta%/state/*}/data/infer-name-z1/launch-brief.md
  out=$(cat "$lb")
  assert_contains "$out" $'# Seat decisions\nLikely areas of this project, matched from this task\'s text: teardown' "a known seat named in the task must be inferred"
  assert_contains "$out" "  ## Teardown decision" "the inferred seat's record must be fed"
  case "$out" in *"Launch decision"* | *"Docs decision"*) fail "other seats' records must be left out: $out" ;; esac
  ! printf '%s\n' "$out" | grep -q '^Task seats:' || fail "inferred seats must not become the task's seats: $out"
  write_record "${meta%/state/*}/data" infer-name-z1 "" "Untagged"
  out=$(fm_seat_archive "${meta%/state/*}/data" infer-name-proj infer-name-z1 ship)
  [ "$out" != teardown ] || fail "an untagged record must not be indexed under an inferred seat"

  rec=$(run_spawn_case infer-path on "Fix the flag parsing in \`bin/fm-spawn.sh\`." "" seed_spawn_seats)
  meta=${rec%%|*}
  out=$(cat "${meta%/state/*}/data/infer-path-z1/launch-brief.md")
  assert_contains "$out" "matched from this task's text: launcher" "a path in the task must map through its seat definition"
  assert_contains "$out" "  ## Launch decision" "the path's seat record must be fed"
  pass "a spawn infers the task's seats from its filled brief by seat name and defined path"
}

seed_spawn_generic_seats() {  # <data> <project-key>
  seed_spawn_seats "$@"
  write_record "$1" t-root root "Root decision"
  index_line "$1" "$2" 1000000004 root t-root
  write_record "$1" t-intent intent "Intent decision"
  index_line "$1" "$2" 1000000005 intent t-intent
}

test_spawn_falls_back_to_the_newest_records_across_seats() {
  local rec meta out
  rec=$(run_spawn_case infer-generic on "Find the root cause of the greeting bug." "" seed_spawn_generic_seats)
  meta=${rec%%|*}
  out=$(cat "${meta%/state/*}/data/infer-generic-z1/launch-brief.md")
  assert_contains "$out" "across all its seats" "neither root nor a heading word may be inferred as a seat: $out"
  rec=$(run_spawn_case infer-none on "Improve the wording of the greeting." "" seed_spawn_seats)
  meta=${rec%%|*}
  out=$(cat "${meta%/state/*}/data/infer-none-z1/launch-brief.md")
  assert_contains "$out" "across all its seats" "an unmatched task must get the all-seat feed"
  ! printf '%s\n' "$out" | grep -q '^Task seats:' || fail "an unmatched task must name no seat: $out"
  for d in Launch Teardown Docs; do
    assert_contains "$out" "  ## $d decision" "the all-seat feed must carry the $d record"
  done
  [ "$(printf '%s\n' "$out" | grep '^- ' | head -1 | grep -c t-docs)" = 1 ] || fail "the all-seat feed must be newest first: $out"
  rec=$(run_spawn_case infer-off off "Make Teardown faster." "" seed_spawn_seats)
  meta=${rec%%|*}
  ! grep -q 'Seat decisions' "${meta%/state/*}/data/infer-off-z1/launch-brief.md" || fail "a flag-off launch must carry no feed"
  pass "an unmatched task gets the project's newest records across all seats, and a flag-off launch none"
}

test_spawn_rebuilds_an_explicit_seat_section() {
  local rec meta out
  rec=$(run_spawn_case infer-override on "Make Teardown faster." $'# Seat decisions\nTask seats: docs\nNo earlier task left a decision record for these seats.\n\n# Setup\nKeep this line.' seed_spawn_seats)
  meta=${rec%%|*}
  out=$(cat "${meta%/state/*}/data/infer-override-z1/launch-brief.md")
  [ "$(printf '%s\n' "$out" | grep -c '^# Seat decisions')" = 1 ] || fail "an explicit seat section must not gain an inferred one: $out"
  case "$out" in *"Teardown decision"*) fail "an explicit seat must override inference: $out" ;; esac
  assert_contains "$out" "  ## Docs decision" "a record indexed after scaffolding must reach the launch: $out"
  case "$out" in *"No earlier task left"*) fail "the scaffold-time section must be replaced: $out" ;; esac
  assert_contains "$out" $'\n\n# Setup\nKeep this line.' "the brief after the section must stay as it was: $out"
  pass "a brief scaffolded with --seat or --path keeps its named seats, rebuilt from the index at launch"
}

test_archive_honours_an_explicit_empty_seats_line() {
  local home data proj wt out
  home=$(new_home archive-empty-line on)
  data=$home/data
  proj=$TMP_ROOT/empty-line-proj
  wt=$TMP_ROOT/empty-line-wt
  fm_git_worktree "$proj" "$wt" fm/t-empty-line
  mkdir -p "$wt/bin"
  printf 'x\n' > "$wt/bin/tool.sh"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m change
  for id in t-empty-line t-empty-scout; do
    mkdir -p "$data/$id"
    printf '%s\n' 'Seats:' '' '## Kept it small' 'Reason: r' > "$data/$id/decisions.md"
    printf '%s\n' '# Seat decisions' 'Task seats: docs' > "$data/$id/brief.md"
  done
  out=$(fm_seat_archive "$data" proj t-empty-line ship "$wt" main)
  [ "$out" = bin ] || fail "an empty Seats: line must leave only the changed-path seats (got '$out')"
  out=$(fm_seat_archive "$data" proj t-empty-scout scout)
  [ -z "$out" ] || fail "a scout with an empty Seats: line must not be indexed (got '$out')"
  pass "an explicit empty Seats: line names no seat instead of falling back to the brief"
}

test_archive_treats_a_none_seat_as_no_seat() {
  local home data out
  home=$(new_home archive-none on)
  data=$home/data
  write_record "$data" t-none-scout 'None' 'Looked around'
  printf '%s\n' '# Seat decisions' 'Task seats: docs' > "$data/t-none-scout/brief.md"
  out=$(fm_seat_archive "$data" proj t-none-scout scout)
  [ -z "$out" ] || fail "a Seats: none line must not be indexed (got '$out')"
  write_record "$data" t-none-mixed 'none spawn' 'Kept spawn'
  out=$(fm_seat_archive "$data" proj t-none-mixed scout)
  [ "$out" = spawn ] || fail "a none token must be dropped beside real seats (got '$out')"
  if grep -q "$(printf '\t')[Nn]one$(printf '\t')" "$data/seats/proj/index.tsv" 2>/dev/null; then
    fail "the index must never hold a none seat"
  fi
  pass "a none token on the Seats: line names no seat"
}

test_changed_paths_leave_out_what_the_branch_took_from_its_base() {
  local proj wt out up rebased
  proj=$TMP_ROOT/rebase-proj
  wt=$TMP_ROOT/rebase-wt
  fm_git_worktree "$proj" "$wt" fm/t-rebase
  mkdir -p "$wt/tools" "$proj/docs"
  printf 'x\n' > "$wt/tools/a.sh"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m task
  printf 'y\n' > "$proj/docs/upstream.md"
  git -C "$proj" add -A
  git -C "$proj" commit -q -m upstream
  git -C "$wt" rebase -q main
  git -C "$proj" merge -q --ff-only fm/t-rebase
  out=$(fm_seat_changed_path_seats "$TMP_ROOT/none.txt" "$wt" main | sort -u | tr '\n' ' ')
  [ "$out" = "tools " ] || fail "a rebased branch landed by fast-forward must keep only its own seats (got '$out')"

  wt=$TMP_ROOT/reset-wt
  git -C "$proj" worktree add --quiet -b fm/t-reset "$wt" main
  mkdir -p "$wt/lib" "$proj/other"
  printf 'z\n' > "$wt/lib/b.sh"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m task2
  printf 'w\n' > "$proj/other/up.md"
  git -C "$proj" add -A
  git -C "$proj" commit -q -m upstream2
  up=$(git -C "$proj" rev-parse HEAD)
  git -C "$wt" checkout -q --detach
  git -C "$wt" rebase -q "$up"
  rebased=$(git -C "$wt" rev-parse HEAD)
  git -C "$wt" checkout -q fm/t-reset
  git -C "$wt" reset -q --hard "$rebased"
  git -C "$proj" merge -q --ff-only fm/t-reset
  out=$(fm_seat_changed_path_seats "$TMP_ROOT/none.txt" "$wt" main | sort -u | tr '\n' ' ')
  [ "$out" = "lib " ] || fail "a branch synced by reset and landed by fast-forward must keep only its own seats (got '$out')"
  pass "changed-path seats leave out what a branch only took from its base, after a rebase or a reset"
}

test_changed_paths_count_both_sides_of_a_rename() {
  local proj wt out
  proj=$TMP_ROOT/rename-proj
  wt=$TMP_ROOT/rename-wt
  fm_git_worktree "$proj" "$wt" fm/t-rename
  mkdir -p "$wt/docs"
  seq 1 40 > "$wt/docs/guide.md"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m add
  git -C "$proj" merge -q --ff-only fm/t-rename
  git -C "$wt" checkout -q -b fm/t-rename2
  mkdir -p "$wt/manual"
  git -C "$wt" mv docs/guide.md manual/guide.md
  git -C "$wt" commit -q -m move
  git -C "$proj" config diff.renames true
  out=$(fm_seat_changed_path_seats "$TMP_ROOT/none.txt" "$wt" main | sort -u | tr '\n' ' ')
  [ "$out" = "docs manual " ] || fail "a rename must count under the seats of both paths (got '$out')"
  pass "a renamed file counts under the seats of its old and its new path"
}

test_project_name_with_a_space_is_encoded() {
  local home key out
  home=$(new_home project-space on)
  key=$(fm_seat_project_key "$TMP_ROOT/projects/my app/")
  [ "$key" = "my%20app" ] || fail "a space must be encoded (got '$key')"
  [ "$(fm_seat_project_key proj)" = proj ] || fail "a valid name must stay as is"
  [ "$(fm_seat_project_key .hidden)" = "%2Ehidden" ] || fail "a leading dot must be encoded"
  write_record "$home/data" t-space docs "Spaced project"
  out=$(fm_seat_archive "$home/data" "$key" t-space ship)
  [ "$out" = docs ] || fail "a project with a space must still be indexed (got '$out')"
  [ -f "$home/data/seats/my%20app/index.tsv" ] || fail "the index must live under the encoded key"
  FM_HOME=$home "$BRIEF" sp-ship "my app" --mode direct-PR --seat docs >/dev/null 2>&1 || fail "a brief for a project with a space failed"
  out=$(cat "$home/data/sp-ship/brief.md")
  assert_contains "$out" "  ## Spaced project" "a project with a space must still get its feed"
  pass "a project name that is no seat name is encoded instead of turning seat memory off"
}

test_feed_without_matching_records_has_no_lead_in() {
  local home out
  home=$(new_home feed-empty on)
  write_record "$home/data" t-other docs "Other"
  index_line "$home/data" proj 1000000001 docs t-other
  out=$(CONFIG=$home/config fm_seat_feed_block "$home/data" proj spawn)
  assert_contains "$out" "No earlier task left a decision record for these seats." "a seat with no record must say so"
  case "$out" in *"Below are"*) fail "a feed with no entries must not carry the lead-in: $out" ;; esac
  pass "a feed whose seats have no record says so instead of a dangling lead-in"
}

test_path_maps_to_longest_defined_prefix_else_first_component
test_archive_indexes_named_seats_once
test_archive_falls_back_to_brief_then_changed_paths
test_feed_is_newest_first_deduplicated_and_bounded
test_flag_off_brief_is_unchanged_by_seat_options
test_flag_on_briefs_carry_feed_and_decisions_clause
test_spawn_records_the_claude_session_id_only_with_the_flag
test_spawn_infers_the_feed_from_the_filled_brief
test_spawn_falls_back_to_the_newest_records_across_seats
test_spawn_rebuilds_an_explicit_seat_section
test_archive_honours_an_explicit_empty_seats_line
test_archive_treats_a_none_seat_as_no_seat
test_changed_paths_leave_out_what_the_branch_took_from_its_base
test_changed_paths_count_both_sides_of_a_rename
test_project_name_with_a_space_is_encoded
test_feed_without_matching_records_has_no_lead_in

echo "# all fm-seat-memory tests passed"
