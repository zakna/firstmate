#!/usr/bin/env bash
# Cleanup precondition for a merged ship PR: every GitHub issue the task's brief
# names must be closed, or carry a comment written after the merge, before the
# task is cleaned up. A PR that says `Refs` instead of a closing keyword leaves
# its issues open, and a resolution comment that nobody remembers to post leaves
# them open with no record of what landed; this makes that readback a refusal
# instead of a memory.
# The issues are read from the brief's `# Task` section (the whole brief when it
# has none), so the scaffold's generic text names nothing. Four forms count:
# a full https://github.com/<owner>/<repo>/issues/<n> URL, <owner>/<repo>#<n>,
# a bare #<n>, and words such as "issue 213" or "issues 213, 214 and 215"; the
# last two resolve to the PR's own repository. A number that
# GitHub reports as a pull request, and the PR's own number, are not issues.
# Exit 0 when every named issue passes, when the brief names none, when there
# is no brief, when the PR is not a GitHub PR, or when the PR is not merged
# (nothing has landed to read back). Exit 1 lists each failing issue on stderr;
# a lookup that cannot be read is a failure too, because an unread issue is not
# a proven readback. bin/fm-teardown.sh runs this for a ship task with a
# recorded PR unless `--no-readback <reason>` waives it.
# Usage: fm-issue-readback.sh <brief> <pr-url>
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-pr-lib.sh
. "$SCRIPT_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-brief-heading-lib.sh
. "$SCRIPT_DIR/fm-brief-heading-lib.sh"

if [ "$#" -ne 2 ]; then
  echo "usage: fm-issue-readback.sh <brief> <pr-url>" >&2
  exit 2
fi
BRIEF=$1
PR_URL=$2

[ -f "$BRIEF" ] || exit 0
fm_pr_url_parse "$PR_URL" && [ "$FM_PR_PROVIDER" = github ] || exit 0
PR_REPO=$FM_PR_PATH
PR_NUMBER=$FM_PR_NUMBER

if fm_brief_heading_present "$BRIEF" "# Task"; then
  TEXT=$(fm_brief_heading_body "$BRIEF" "# Task")
else
  TEXT=$(cat "$BRIEF")
fi

# One <owner>/<repo> <number> pair per line, first mention order, no repeats.
ISSUES=$(printf '%s\n' "$TEXT" | awk -v repo="$PR_REPO" -v own="$PR_NUMBER" '
  function add(r, n) {
    if (r == repo && n == own) return
    key = r " " n
    if (!(key in seen)) { seen[key] = 1; print key }
  }
  {
    line = $0
    while (match(line, /https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/[0-9]+/)) {
      ref = substr(line, RSTART + 19, RLENGTH - 19)
      split(ref, p, "/")
      add(p[1] "/" p[2], p[4])
      line = substr(line, 1, RSTART - 1) " " substr(line, RSTART + RLENGTH)
    }
    while (match(line, /[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+#[0-9]+/)) {
      ref = substr(line, RSTART, RLENGTH)
      split(ref, p, "#")
      add(p[1], p[2])
      line = substr(line, 1, RSTART - 1) " " substr(line, RSTART + RLENGTH)
    }
    words = line
    while (match(words, /(^|[^A-Za-z0-9_])[Ii]ssues? [0-9]+((, | and |, and )[0-9]+)*/)) {
      ref = substr(words, RSTART, RLENGTH)
      words = substr(words, RSTART + RLENGTH)
      sub(/^[^0-9]*/, "", ref)
      k = split(ref, nums, /[^0-9]+/)
      for (i = 1; i <= k; i++) if (nums[i] != "") add(repo, nums[i])
    }
    line = " " line
    while (match(line, /[^A-Za-z0-9_&\/]#[A-Za-z0-9_]+/)) {
      tok = substr(line, RSTART + 2, RLENGTH - 2)
      # A reference ends at a word boundary and is not a 6-digit hex colour.
      if (tok ~ /^[0-9]+$/ && tok !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) add(repo, tok)
      line = substr(line, RSTART + RLENGTH)
    }
  }')
[ -n "$ISSUES" ] || exit 0

if ! command -v gh >/dev/null 2>&1; then
  echo "issue readback: gh is not on PATH, so the issues the brief names cannot be read" >&2
  exit 1
fi
MERGE=$(gh pr view "$PR_URL" --json state,mergedAt -q '.state + " " + (.mergedAt // "")' 2>/dev/null) || {
  echo "issue readback: could not read the merge state of $PR_URL" >&2
  exit 1
}
case "$MERGE" in
  "MERGED "*) MERGED_AT=${MERGE#MERGED } ;;
  *) exit 0 ;;
esac
case "$MERGED_AT" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
  *)
    echo "issue readback: $PR_URL reports no readable merge time" >&2
    exit 1 ;;
esac

FAILED=0
while read -r repo number; do
  url="https://github.com/$repo/issues/$number"
  if ! info=$(gh api "repos/$repo/issues/$number" --jq '.state + " " + (if .pull_request then "pr" else "issue" end)' 2>/dev/null); then
    echo "issue readback: could not read $url" >&2
    FAILED=1
    continue
  fi
  case "$info" in
    *" pr") continue ;;
    "closed "*) continue ;;
    "open issue") ;;
    *)
      echo "issue readback: $url reports an unreadable state" >&2
      FAILED=1
      continue ;;
  esac
  if ! newer=$(gh api "repos/$repo/issues/$number/comments?since=$MERGED_AT&per_page=100" \
    --jq "[.[] | select(.created_at > \"$MERGED_AT\")] | length" 2>/dev/null); then
    echo "issue readback: could not read the comments on $url" >&2
    FAILED=1
    continue
  fi
  case "$newer" in
    ''|*[!0-9]*)
      echo "issue readback: $url returned an unreadable comment count" >&2
      FAILED=1 ;;
    0)
      echo "issue readback: $url is open with no comment since the merge at $MERGED_AT" >&2
      FAILED=1 ;;
  esac
done <<EOF
$ISSUES
EOF
exit "$FAILED"
