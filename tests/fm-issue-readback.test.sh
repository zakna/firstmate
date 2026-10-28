#!/usr/bin/env bash
# Behavior tests for bin/fm-issue-readback.sh, the cleanup precondition that an
# issue a ship brief names is closed or carries a comment written after the
# task's PR merged, and for bin/fm-teardown.sh's --no-readback waiver.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-issue-readback)
READBACK="$ROOT/bin/fm-issue-readback.sh"
PR=https://github.com/acme/widgets/pull/50
MERGED_AT=2026-10-20T10:00:00Z

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is not installed"; exit 0; }

# A fake gh that answers from files under $FM_TEST_GH_DIR and applies the
# caller's own --jq or -q filter with the real jq, so the filters are exercised:
#   pr.json                         the `gh pr view` answer
#   issue-<owner>_<repo>_<n>.json   an issue, absent means a lookup error
#   comments-<owner>_<repo>_<n>.json its comments, absent means []
#   repo-<owner>_<repo>.json        a repository (lowercase name), absent means HTTP 404
#   repo-<owner>_<repo>.err         a failed repository lookup, with this stderr
# Every call is logged to $FM_TEST_GH_DIR/calls.
make_fake_gh() {  # <case-dir>
  local fakebin
  fakebin=$(fm_fakebin "$1")
  cat > "$fakebin/gh" <<'SH'
#!/usr/bin/env bash
dir=$FM_TEST_GH_DIR
printf '%s\n' "$*" >> "$dir/calls"
filter=.
prev=
for arg in "$@"; do
  case "$prev" in --jq|-q) filter=$arg ;; esac
  prev=$arg
done
case "$1 $2" in
  "pr view") file=$dir/pr.json ;;
  "api "*)
    path=${2%%\?*}
    rest=${path#repos/}
    owner=${rest%%/*}; rest=${rest#*/}
    repo=${rest%%/*}; rest=${rest#*/issues/}
    case "$path" in
      "repos/$owner/$repo") repo=$(printf '%s' "$repo" | tr '[:upper:]' '[:lower:]')
        file=$dir/repo-${owner}_${repo}.json
        [ -f "$dir/repo-${owner}_${repo}.err" ] && { cat "$dir/repo-${owner}_${repo}.err" >&2; exit 1; }
        [ -f "$file" ] || { echo 'gh: Not Found (HTTP 404)' >&2; exit 1; } ;;
      *)
    case "$rest" in
      */comments) file=$dir/comments-${owner}_${repo}_${rest%/comments}.json
        [ -f "$file" ] || { printf '[]' | jq -r "$filter"; exit; } ;;
      *) file=$dir/issue-${owner}_${repo}_${rest}.json ;;
    esac ;;
    esac ;;
  *) exit 1 ;;
esac
[ -f "$file" ] || exit 1
jq -r "$filter" "$file"
SH
  chmod +x "$fakebin/gh"
}

make_case() {  # <name> <task-section-text>
  local dir="$TMP_ROOT/$1"
  mkdir -p "$dir/gh"
  make_fake_gh "$dir"
  {
    printf '# Task\n## Captain'"'"'s intent\n%s\n\n## Firstmate spec\nKeep it small.\n\n' "$2"
    printf '# Definition of done\nEnd the pull request body with Refs #<n> when asked; see #999 in the template.\n'
  } > "$dir/brief.md"
  printf '{"state":"MERGED","mergedAt":"%s"}\n' "$MERGED_AT" > "$dir/gh/pr.json"
  printf '%s\n' "$dir"
}

issue() {  # <dir> <owner_repo_n> <open|closed> [pr]
  if [ "${4:-}" = pr ]; then
    printf '{"state":"%s","pull_request":{"url":"x"}}\n' "$3" > "$1/gh/issue-$2.json"
  else
    printf '{"state":"%s"}\n' "$3" > "$1/gh/issue-$2.json"
  fi
}

comment() {  # <dir> <owner_repo_n> <created_at>
  printf '[{"created_at":"%s"}]\n' "$3" > "$1/gh/comments-$2.json"
}

run_readback() {  # <dir> -> stderr on stdout, exit status kept
  FM_TEST_GH_DIR="$1/gh" PATH="$1/fakebin:$PATH" "$READBACK" "$1/brief.md" "$PR" 2>&1
}

test_open_issue_without_a_comment_since_merge_refuses() {
  local dir out
  dir=$(make_case open-silent "Fix #12 and close https://github.com/acme/widgets/issues/13; see acme/gadgets#4.")
  issue "$dir" acme_widgets_12 open
  comment "$dir" acme_widgets_12 2026-10-19T09:00:00Z
  issue "$dir" acme_widgets_13 closed
  issue "$dir" acme_gadgets_4 open
  comment "$dir" acme_gadgets_4 2026-10-20T11:00:00Z
  out=$(run_readback "$dir") && fail "an open issue with only a pre-merge comment passed: $out"
  printf '%s\n' "$out" | grep -qF "https://github.com/acme/widgets/issues/12 is open with no comment since the merge at $MERGED_AT" \
    || fail "the refusal did not name the silent issue: $out"
  printf '%s\n' "$out" | grep -qF 'issues/13' && fail "a closed issue was reported: $out"
  printf '%s\n' "$out" | grep -qF 'gadgets' && fail "an issue commented after the merge was reported: $out"
  grep -qF 'issues/999' "$dir/gh/calls" && fail "a number outside the Task section was read"
  pass "an open issue with no comment since the merge refuses, closed and commented ones pass"
}

test_commented_closed_and_pr_numbers_pass() {
  local dir out
  dir=$(make_case all-pass "Fix #12, follow up on #13, and see #50 and #7.")
  issue "$dir" acme_widgets_12 closed
  issue "$dir" acme_widgets_13 open
  comment "$dir" acme_widgets_13 2026-10-20T10:30:00Z
  issue "$dir" acme_widgets_7 open pr
  out=$(run_readback "$dir") || fail "every named issue was read back but the check refused: $out"
  grep -qF 'issues/50' "$dir/gh/calls" && fail "the PR's own number was read as an issue"
  pass "closed issues, issues commented after the merge, and pull request numbers pass"
}

# Briefs often name issues in words, so "issue 21" and "issues 22, 23 and 24"
# name issues of the PR's repository just as #21 does.
test_issues_named_in_words_are_read_back() {
  local dir out n
  dir=$(make_case words "Fix issue 21, then Issues 22, 23 and 24; tissue 99 is not one.")
  issue "$dir" acme_widgets_21 open
  for n in 22 23 24; do issue "$dir" "acme_widgets_$n" closed; done
  out=$(run_readback "$dir") && fail "an open issue named in words passed: $out"
  printf '%s\n' "$out" | grep -qF "https://github.com/acme/widgets/issues/21 is open with no comment since the merge at $MERGED_AT" \
    || fail "the refusal did not name the issue named in words: $out"
  for n in 22 23 24; do
    grep -qF "issues/$n" "$dir/gh/calls" || fail "issue $n in a word list was not read"
  done
  grep -qF 'issues/99' "$dir/gh/calls" && fail "a number after a word ending in 'issue' was read"
  pass "issues named in words are read back"
}

test_hex_colours_and_non_boundary_hashes_are_not_issues() {
  local dir out got
  dir=$(make_case not-issues "Keep the colour #000000 and #1a2b3c, tag #12abc, and fix #12.")
  issue "$dir" acme_widgets_12 closed
  out=$(run_readback "$dir") || fail "text that names no issue refused the readback: $out"
  got=$(grep -o 'issues/[0-9A-Za-z]*' "$dir/gh/calls" | sort -u | tr '\n' ' ')
  [ "$got" = 'issues/12 ' ] || fail "only issue 12 should be read, got: $got"
  pass "hex colours and hashes without a word boundary are not issues"
}

# "fm-tooling #49" names issue 49 of the owner's fm-tooling repository, not
# issue 49 of the PR's repository; a bare #n after any other word stays local.
test_bare_hash_after_a_sibling_repository_name_reads_that_repository() {
  local dir out
  dir=$(make_case sibling-repo "File it upstream through the fm-tooling route, like fm-tooling #49. Fix #12; see Fm-Tooling #49.")
  printf '{"full_name":"acme/fm-tooling"}\n' > "$dir/gh/repo-acme_fm-tooling.json"
  issue "$dir" acme_fm-tooling_49 open
  issue "$dir" acme_widgets_12 closed
  issue "$dir" acme_widgets_49 closed
  out=$(run_readback "$dir") && fail "an open issue of the named repository passed: $out"
  printf '%s\n' "$out" | grep -qF "https://github.com/acme/fm-tooling/issues/49 is open with no comment since the merge at $MERGED_AT" \
    || fail "the refusal did not name the issue of the named repository: $out"
  grep -qF 'repos/acme/widgets/issues/49' "$dir/gh/calls" && fail "#49 was read from the PR's repository"
  printf '%s\n' "$out" | grep -qF 'Fm-Tooling' && fail "the brief's spelling of the repository was used: $out"
  [ "$(grep -c '^api repos/acme/fm-tooling/issues/49 ' "$dir/gh/calls")" = 1 ] || fail "issue 49 of fm-tooling was not read exactly once"
  grep -qF 'repos/acme/widgets/issues/12' "$dir/gh/calls" || fail "#12 after an ordinary word was not read from the PR's repository"
  pass "a bare #n after a repository name of the same owner reads that repository"
}

test_unresolvable_repository_name_refuses() {
  local dir out
  dir=$(make_case sibling-repo-error "Like fm-tooling #49.")
  printf 'gh: Server Error (HTTP 502)\n' > "$dir/gh/repo-acme_fm-tooling.err"
  issue "$dir" acme_widgets_49 closed
  out=$(run_readback "$dir") && fail "a repository name that could not be resolved passed: $out"
  printf '%s\n' "$out" | grep -qF 'could not resolve fm-tooling #49' \
    || fail "the refusal did not name the unresolved reference: $out"
  grep -qF 'repos/acme/widgets/issues/49' "$dir/gh/calls" && fail "#49 fell back to the PR's repository"
  pass "a repository name that cannot be resolved refuses instead of falling back"
}

test_unreadable_issue_refuses_and_no_issue_reads_nothing() {
  local dir out
  dir=$(make_case unreadable "Fix #12.")
  out=$(run_readback "$dir") && fail "an unreadable issue passed: $out"
  printf '%s\n' "$out" | grep -qF 'could not read https://github.com/acme/widgets/issues/12' \
    || fail "the refusal did not name the unreadable issue: $out"

  dir=$(make_case none "Rename the config key.")
  out=$(run_readback "$dir") || fail "a brief that names no issue refused: $out"
  [ ! -e "$dir/gh/calls" ] || fail "a brief that names no issue still called gh"
  pass "an unreadable issue refuses, and a brief naming no issue reads nothing"
}

test_unmerged_pr_is_not_read_back() {
  local dir out
  dir=$(make_case unmerged "Fix #12.")
  printf '{"state":"OPEN","mergedAt":null}\n' > "$dir/gh/pr.json"
  issue "$dir" acme_widgets_12 open
  out=$(run_readback "$dir") || fail "an unmerged PR was read back: $out"
  pass "an unmerged PR has nothing to read back"
}

test_teardown_rejects_an_empty_waiver() {
  local home="$TMP_ROOT/home" out rc
  mkdir -p "$home/state" "$home/data" "$home/config"
  out=$(FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$ROOT/bin/fm-teardown.sh" task-x1 --no-readback 2>&1); rc=$?
  [ "$rc" = 2 ] || fail "teardown accepted --no-readback without a reason (rc=$rc): $out"
  out=$(FM_ROOT_OVERRIDE="$ROOT" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$ROOT/bin/fm-teardown.sh" task-x1 --no-readback '' 2>&1); rc=$?
  [ "$rc" = 2 ] || fail "teardown accepted an empty --no-readback reason (rc=$rc): $out"
  pass "teardown refuses a readback waiver that names no reason"
}

test_open_issue_without_a_comment_since_merge_refuses
test_commented_closed_and_pr_numbers_pass
test_issues_named_in_words_are_read_back
test_hex_colours_and_non_boundary_hashes_are_not_issues
test_bare_hash_after_a_sibling_repository_name_reads_that_repository
test_unresolvable_repository_name_refuses
test_unreadable_issue_refuses_and_no_issue_reads_nothing
test_unmerged_pr_is_not_read_back
test_teardown_rejects_an_empty_waiver
