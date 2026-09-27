#!/usr/bin/env bash
# Behavior tests for bin/fm-intent-check.sh, the check a no-mistakes worker runs
# on its `--intent` string before the run starts, because the pipeline publishes
# that string as the pull request body.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-intent-check)
fm_git_identity fmtest fmtest@example.invalid
CHECK="$ROOT/bin/fm-intent-check.sh"

# A project repository whose own files use the word "pipeline" but none of the
# fleet terms, with a github.com origin.
REPO="$TMP_ROOT/repo"
git init -q "$REPO"
printf 'The build pipeline caches the captain dependency list.\n' > "$REPO/README.md"
git -C "$REPO" add README.md
git -C "$REPO" commit -q -m init
git -C "$REPO" remote add origin https://github.com/acme/widgets.git

write_launch_brief() {  # <dir> <authorized-body>
  mkdir -p "$1"
  {
    printf '# Task\n## Captain'"'"'s intent\nAn older body.\n\n## Firstmate spec\nRefactor the parser module first.\n\n'
    printf '# Current no-mistakes intent contract\nUse everything under the heading below.\n\n'
    printf '## Captain intent authorized for --intent\n%s\n' "$2"
  } > "$1/launch-brief.md"
}

run_check() {  # <source> <intent-text> [args...] -> prints output, returns exit
  local src=$1 text=$2 file
  shift 2
  file=$(mktemp "$TMP_ROOT/intent.XXXXXX")
  printf '%s\n' "$text" > "$file"
  (cd "$REPO" && "$CHECK" check "$src" "$file" "$@" 2>&1)
}

test_clean_intent_passes() {
  local dir="$TMP_ROOT/clean" out
  write_launch_brief "$dir" 'Make the export command write UTF-8. The report must keep its column order.'
  out=$(run_check "$dir" 'Make the export command write UTF-8. The report must keep its column order.') \
    || fail "clean intent was refused: $out"
  out=$(run_check "$dir" 'The report must keep its column order.') \
    || fail "a subset of whole authorized sentences was refused: $out"
  pass "a clean intent and a sentence-level subset pass"
}

test_product_sentences_are_not_refused() {
  local dir="$TMP_ROOT/product" body out
  body='Show the temperature so you can see drift.
[Fan docs](https://example.com/fan) describe the night curve.
- [x] Keep the column order.'
  write_launch_brief "$dir" "$body"
  out=$(run_check "$dir" "$body") || fail "product sentences were refused: $out"
  out=$(run_check "$dir" '[Captain] make exports UTF-8.
You must rebase your branch first.')
  [ $? -eq 1 ] || fail "a bracketed speaker tag and a worker instruction passed"
  assert_contains "$out" 'line 1: speaker label' "a bracketed speaker tag was not refused"
  assert_contains "$out" 'line 2: direct address' "a worker instruction was not refused"
  pass "second-person product wording, links, and task items pass; worker address does not"
}

test_each_forbidden_class_names_the_line() {
  local dir="$TMP_ROOT/classes" out rc
  write_launch_brief "$dir" 'Captain: make exports UTF-8.
Check the encoding yourself before changing it.
The owner approved it with the words "ship it".
Ask the crewmate to keep the column order.
Make exports UTF-8.'
  for pair in \
    'speaker label|Captain: make exports UTF-8.' \
    'direct address|Check the encoding yourself before changing it.' \
    'quote|The owner approved it with the words "ship it".' \
    'fleet vocabulary "crewmate"|Ask the crewmate to keep the column order.' \
    'outside the authorized intent|Also rewrite the parser.'; do
    out=$(run_check "$dir" "Make exports UTF-8.
${pair#*|}")
    rc=$?
    [ "$rc" -eq 1 ] || fail "${pair%%|*}: check exited $rc, want 1: $out"
    assert_contains "$out" "line 2: ${pair%%|*}: ${pair#*|}" "${pair%%|*}: refusal did not name the line"
    assert_not_contains "$out" "line 1:" "${pair%%|*}: the clean line was also refused"
  done
  pass "each forbidden class is refused and names its line"
}

test_a_mentioned_quote_is_not_an_attributed_quote() {
  local dir="$TMP_ROOT/mentioned" body out
  body='Keep a quote and three "the owner" attributions out of the body.
The owner said: "ship it".
"Ship it," said the owner.'
  write_launch_brief "$dir" "$body"
  out=$(run_check "$dir" 'Keep a quote and three "the owner" attributions out of the body.') \
    || fail "a sentence that only mentions quotes was refused: $out"
  out=$(run_check "$dir" 'The owner said: "ship it".') && fail "a said-then-quote passed"
  out=$(run_check "$dir" '"Ship it," said the owner.') && fail "a quote-then-said passed"
  assert_contains "$out" 'quote' "quote-then-said was not refused as a quote"
  pass "only a quote a speech word attributes is refused"
}

test_repository_vocabulary_is_not_fleet_vocabulary() {
  local dir="$TMP_ROOT/vocab" out
  write_launch_brief "$dir" 'Pin the captain dependency list. Keep the supervisor restart logic.'
  out=$(run_check "$dir" 'Pin the captain dependency list.') \
    || fail "a term the repository itself uses was refused: $out"
  out=$(run_check "$dir" 'Keep the supervisor restart logic.') && fail "a foreign fleet term passed"
  assert_contains "$out" 'fleet vocabulary "supervisor"' "foreign fleet term was not named"
  pass "only fleet terms the repository does not use are refused"
}

test_examples_and_inline_code_are_exempt() {
  local dir="$TMP_ROOT/examples" body out
  # shellcheck disable=SC2016 # Backticks are literal Markdown inline code.
  body='Reject a label such as `Captain:` in the parser.
```
Captain: you said "ship it"
```'
  write_launch_brief "$dir" "$body"
  out=$(run_check "$dir" "$body") || fail "literal examples were refused: $out"
  pass "fenced examples and inline code are exempt from the refusal classes"
}

test_issue_reference_is_required_and_never_invented() {
  local dir="$TMP_ROOT/refs" out rc
  write_launch_brief "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.
See https://github.com/other/repo/issues/7 for background.'
  out=$(run_check "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.')
  rc=$?
  [ "$rc" -eq 1 ] || fail "missing Refs was accepted"
  assert_contains "$out" 'missing reference: add "Refs #42"' "missing Refs was not named"
  assert_not_contains "$out" '#7' "an issue of another repository was required"
  out=$(run_check "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Refs #42') || fail "intent with the linked Refs was refused: $out"
  out=$(run_check "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Refs #42, #99')
  rc=$?
  [ "$rc" -eq 1 ] || fail "an invented reference was accepted"
  assert_contains "$out" 'reference not named by the brief: #99' "invented reference was not named"
  out=$(run_check "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Refs #42, #7')
  [ $? -eq 1 ] || fail "another repository's issue number passed as this repository's"
  assert_contains "$out" 'reference not named by the brief: #7' "another repository's number was not refused"
  out=$(run_check "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Refs https://github.com/other/repo/issues/42')
  [ $? -eq 1 ] || fail "another repository's URL satisfied this repository's reference"
  assert_contains "$out" 'reference to another repository' "another repository's URL was not refused"
  assert_contains "$out" 'missing reference: add "Refs #42"' "another repository's URL satisfied #42"
  pass "only this repository's named issues count as references"
}

test_scrub_refuses_instead_of_dropping() {
  local dir="$TMP_ROOT/scrub" out err rc
  write_launch_brief "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8. Confirm that yourself on main first.
The owner authorised this with the words "Yes implement".

Keep the column order.'
  out=$(cd "$REPO" && "$CHECK" scrub "$dir" 2>"$TMP_ROOT/scrub.err")
  rc=$?
  err=$(cat "$TMP_ROOT/scrub.err")
  [ "$rc" -eq 1 ] || fail "scrub exited $rc on refused lines, want 1"
  assert_equals '' "$out" "scrub printed a string despite refused lines"
  assert_contains "$err" 'line 1: direct address: Fix https://github.com/acme/widgets/issues/42' "scrub did not name the address line"
  assert_contains "$err" 'line 2: quote: The owner authorised' "scrub did not name the quote line"
  write_launch_brief "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Keep the column order.'
  out=$(cd "$REPO" && "$CHECK" scrub "$dir") || fail "scrub refused a clean intent"
  assert_equals 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Keep the column order.

Refs #42' "$out" "scrub did not return the words plus Refs"
  printf '%s\n' "$out" > "$TMP_ROOT/scrubbed.txt"
  (cd "$REPO" && "$CHECK" check "$dir" "$TMP_ROOT/scrubbed.txt" >/dev/null 2>&1) \
    || fail "the scrubbed string did not pass the check"
  pass "scrub refuses and names each refused line, and a clean scrub passes the check"
}

test_rewording_the_named_source_clears_a_refusal() {
  local dir="$TMP_ROOT/reword" src out err rc
  write_launch_brief "$dir" 'Make exports UTF-8.
You must keep the column order.'
  src="$dir/launch-brief.md"
  out=$(cd "$REPO" && "$CHECK" scrub "$dir" 2>"$TMP_ROOT/reword.err")
  rc=$?
  err=$(cat "$TMP_ROOT/reword.err")
  [ "$rc" -eq 1 ] || fail "scrub exited $rc on a refused line, want 1"
  assert_contains "$err" "authorized intent read from $src" "scrub did not name the source file it read"
  out=$(run_check "$dir" 'Make exports UTF-8.
Keep the column order.')
  [ $? -eq 1 ] || fail "a reworded sentence passed before the source was reworded"
  assert_contains "$out" "authorized intent read from $src" "check did not name the source file it read"
  sed 's/^You must keep the column order\.$/Keep the column order./' "$src" > "$src.new" && mv "$src.new" "$src"
  out=$(cd "$REPO" && "$CHECK" scrub "$dir") || fail "scrub still refused after the named source was reworded"
  assert_equals 'Make exports UTF-8.
Keep the column order.' "$out" "scrub did not return the reworded words"
  out=$(run_check "$dir" "$out") || fail "check still refused after the named source was reworded: $out"
  pass "a refusal names its source file, and rewording that file clears it"
}

test_scrub_keeps_the_captains_refs_line() {
  local dir="$TMP_ROOT/scrub-refs" out
  write_launch_brief "$dir" 'Make the fan quieter at night.
Refs #43'
  out=$(cd "$REPO" && "$CHECK" scrub "$dir" 2>/dev/null) || fail "scrub failed"
  assert_equals 'Make the fan quieter at night.
Refs #43' "$out" "scrub dropped the captain's Refs line"
  write_launch_brief "$dir" 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Refs #42'
  out=$(cd "$REPO" && "$CHECK" scrub "$dir" 2>/dev/null) || fail "scrub failed"
  assert_equals 'Fix https://github.com/acme/widgets/issues/42 so exports are UTF-8.

Refs #42' "$out" "scrub repeated a reference the captain's Refs line already names"
  pass "scrub keeps a Refs line the brief names without repeating it"
}

test_later_words_and_resolved_substance() {
  local dir="$TMP_ROOT/later" out words resolved
  write_launch_brief "$dir" 'Do items 1 and 2 of the audit report.'
  words="$TMP_ROOT/later-words.txt"
  resolved="$TMP_ROOT/resolved.txt"
  printf 'Also keep the CSV header.\n' > "$words"
  printf 'Item 1 makes exports UTF-8. Item 2 keeps the column order.\n' > "$resolved"
  out=$(run_check "$dir" 'Do items 1 and 2 of the audit report.
Item 1 makes exports UTF-8. Item 2 keeps the column order.
Also keep the CSV header.' --captain-words "$words" --resolved "$resolved") \
    || fail "authorized later words and resolved substance were refused: $out"
  printf 'Item 1 is what you must build first.\n' > "$resolved"
  out=$(run_check "$dir" 'Item 1 is what you must build first.' --resolved "$resolved") \
    && fail "resolved substance skipped the refusal classes"
  assert_contains "$out" 'direct address' "resolved substance with direct address was not refused"
  pass "later captain words and resolved substance are authorized but still checked"
}

test_legacy_marked_task_uses_only_marked_words() {
  local dir="$TMP_ROOT/legacy" out
  mkdir -p "$dir"
  cat > "$dir/brief.md" <<'EOF'
# Task
[captain] Make exports UTF-8.
Refactor the parser module first.

```
[captain] A fenced sample is not intent.
```

# Setup
Work in the isolated copy.
EOF
  out=$(run_check "$dir" 'Make exports UTF-8.') || fail "marked legacy words were refused: $out"
  out=$(run_check "$dir" 'Refactor the parser module first.') && fail "unmarked legacy Task line passed"
  assert_contains "$out" 'outside the authorized intent' "unmarked legacy line was not refused as outside"
  out=$(run_check "$dir" 'A fenced sample is not intent.') && fail "fenced legacy marker passed"
  out=$(cd "$REPO" && "$CHECK" scrub "$dir/brief.md" 2>/dev/null)
  assert_equals 'Make exports UTF-8.' "$out" "legacy scrub did not return only the marked words without the prefix"
  pass "a legacy provenance-marked Task authorizes only its marked words"
}

test_task_dir_prefers_the_launch_overlay() {
  local dir="$TMP_ROOT/resolve" out
  write_launch_brief "$dir" 'Make exports UTF-8.'
  printf '# Task\n## Captain'"'"'s intent\nShip the old ask.\n\n## Firstmate spec\nx\n' > "$dir/ship-instructions.md"
  out=$(run_check "$dir" 'Make exports UTF-8.') || fail "overlay words were refused: $out"
  out=$(run_check "$dir" 'An older body.') && fail "the superseded Captain's intent body passed"
  rm "$dir/launch-brief.md"
  out=$(run_check "$dir" 'Ship the old ask.') || fail "promotion instructions were not used: $out"
  pass "a task directory resolves to the launch overlay, then promotion instructions"
}

test_no_mistakes_brief_names_the_check() {
  local home="$TMP_ROOT/home" id=intent-check-brief-a1 brief
  mkdir -p "$home/data" "$home/state" "$home/config"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" widgets --mode no-mistakes >/dev/null \
    || fail "fm-brief.sh failed"
  brief="$home/data/$id/brief.md"
  assert_grep "fm-intent-check.sh check $home/data/$id <file>" "$brief" "no-mistakes brief does not name the check"
  assert_grep "fm-intent-check.sh scrub $home/data/$id" "$brief" "no-mistakes brief does not name the scrub"
  id=intent-check-brief-b1
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" "$id" widgets --mode direct-PR >/dev/null || fail "fm-brief.sh failed"
  assert_no_grep "fm-intent-check.sh" "$home/data/$id/brief.md" "direct-PR brief names the intent check"
  pass "the no-mistakes brief tells the worker to run the check on the task directory"
}

test_clean_intent_passes
test_product_sentences_are_not_refused
test_each_forbidden_class_names_the_line
test_a_mentioned_quote_is_not_an_attributed_quote
test_repository_vocabulary_is_not_fleet_vocabulary
test_examples_and_inline_code_are_exempt
test_issue_reference_is_required_and_never_invented
test_scrub_refuses_instead_of_dropping
test_rewording_the_named_source_clears_a_refusal
test_scrub_keeps_the_captains_refs_line
test_later_words_and_resolved_substance
test_legacy_marked_task_uses_only_marked_words
test_task_dir_prefers_the_launch_overlay
test_no_mistakes_brief_names_the_check
