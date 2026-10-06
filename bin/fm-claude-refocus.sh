#!/usr/bin/env bash
# Re-inject a Claude task worker's anchors after a context compaction.
#
# Usage: fm-claude-refocus.sh <brief> <state-dir> <task-id>
#   <brief>      the task's mutable data/<task-id>/brief.md, read at hook time so
#                captain words appended after spawn are re-injected too
#   <state-dir>  the home state directory that holds <task-id>.inbox
#   <task-id>    the task whose steering inbox is read
# Prints one plain-text block on stdout and always exits 0.
#
# bin/fm-spawn.sh registers this as the worker's SessionStart hook with the
# `compact` matcher in the task worktree's .claude/settings.local.json, baking
# in that task's own three arguments, so the hook can only ever read the files
# of the task it was armed for. It never reads the Claude hook payload.
# Claude's PostCompact event is side-effect only and cannot add context, while
# plain stdout from a SessionStart hook whose source is `compact` is added to
# the model's context right after compaction; that is why the refocus rides
# SessionStart.
#
# The block carries, in order: the brief's `## Captain's intent` subsection of
# `# Task` verbatim (or, for an accepted legacy brief without that subsection,
# its whole `# Task` body), its `# Definition of done` section verbatim, and the
# newest unhandled steering-inbox record's body (bin/fm-task-inbox-lib.sh owns
# the inbox layout and record format), or one line saying none is waiting. A
# missing brief or section is named in place of its body rather than failing,
# so a compaction never breaks on this hook.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-brief-heading-lib.sh
. "$SCRIPT_DIR/fm-brief-heading-lib.sh"
# shellcheck source=bin/fm-task-inbox-lib.sh
. "$SCRIPT_DIR/fm-task-inbox-lib.sh"

if [ "$#" -ne 3 ]; then
  echo "usage: fm-claude-refocus.sh <brief> <state-dir> <task-id>" >&2
  exit 0
fi
brief=$1
state=$2
id=$3

printf '%s\n' "Firstmate refocus after context compaction for task $id."
printf '%s\n' "Your task brief at $brief stays authoritative; these are its anchors and your newest steering message."
printf '\n'

section() {  # <title> <body-or-empty> <missing-line>
  printf '%s\n' "$1"
  if [ -n "$(printf '%s' "$2" | tr -d '[:space:]')" ]; then
    printf '%s\n' "$2"
  else
    printf '%s\n' "$3"
  fi
  printf '\n'
}

if [ -f "$brief" ]; then
  dod=$(fm_brief_heading_body "$brief" "# Definition of done")
  if fm_brief_task_heading_present "$brief" "## Captain's intent"; then
    intent=$(fm_brief_task_heading_body "$brief" "## Captain's intent")
    section "## Captain's intent" "$intent" "(The brief's ## Captain's intent subsection is empty.)"
  else
    # A legacy brief carries its accepted task in a single # Task body
    # (fm_brief_task_content_valid in bin/fm-dod-lib.sh).
    task=$(fm_brief_heading_body "$brief" "# Task")
    section "# Task" "$task" "(The brief has neither a ## Captain's intent subsection nor a # Task body.)"
  fi
  section "# Definition of done" "$dod" "(The brief has no # Definition of done section.)"
else
  printf '%s\n\n' "(The brief is not readable at $brief; reread it before you continue.)"
fi

printf '%s\n' "# Newest unhandled steering message"
inbox=$(fm_task_inbox_dir "$state" "$id")
if record=$(fm_task_inbox_newest_unhandled "$state" "$id"); then
  printf '%s\n' "From $record:"
  if body=$(fm_task_inbox_body "$record"); then
    printf '%s\n' "$body"
  else
    printf '%s\n' "(The record has no readable body.)"
  fi
  printf '%s\n' "Handle every message in $inbox in numeric order and acknowledge each one as your brief says."
else
  printf '%s\n' "No unhandled steering message is waiting in $inbox."
fi
exit 0
