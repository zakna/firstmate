# shellcheck shell=bash
# Project claim-ritual intake check.
# Usage: . bin/fm-claim-ritual-lib.sh
#
# Some projects run their own claim ritual: work is owned through claim
# comments or labels, an abandoned claim is recovered by a project-defined
# procedure, and the recovering session must be a named model. A brief that
# points a worker at the project's handoff without carrying that procedure and
# model lets the worker resume an abandoned claim directly, which the ritual
# forbids.
#
# fm_claim_ritual_detect reads the project clone only (never writes) and prints
# the project file that declares a ritual: a root RITUAL.md, or a root
# AGENTS.md or CLAUDE.md that describes a contributor-ownership claim (an
# owner, reviewer, ticket, issue, task, session, agent, worker, contributor,
# assignee, work, pr, or handoff claim) as abandoned, stale, superseded, or
# recovered, across line breaks, or that names a superseding claim, or that
# puts the word claim in the same sentence as a contributor action (comment,
# take over, abandon, supersede). Product wording such as recovering stale
# lease claims is not a ritual. It fails when the project declares none.
#
# fm_claim_ritual_brief_missing prints the lines the given brief text still
# lacks and fails when it carries both: a `Claim recovery:` line naming the
# project's recovery procedure and a `Claim model:` line naming the model the
# ritual requires (or stating that none is required). bin/fm-spawn.sh refuses a
# first launch of a ship task whose project declares a ritual and whose brief
# `# Task` lacks either line. bin/fm-promote.sh refuses promotion of such a
# scout when the ship-time text it delivers, the `## Captain's intent`, lacks
# either line; the scout-time spec is only context for the promoted worker.
# This file is the single owner of both line labels.
# No side effects on source. set -u / set -e safe.

fm_claim_ritual_detect() {  # <project-dir>
  local dir=$1 f
  for f in "$dir"/RITUAL.md "$dir"/ritual.md; do
    if [ -f "$f" ]; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  for f in "$dir"/AGENTS.md "$dir"/CLAUDE.md; do
    [ -f "$f" ] || continue
    if tr -s '[:space:]' ' ' < "$f" \
      | grep -Ei '(supersed[a-z]* claim|(abandon|stale|supersed|recover)[a-z]*( [^ .]+){0,2} ([a-z]+-)?(owner|reviewer|review|ticket|issue|task|session|agent|worker|contributor|assignee|work|pr|handoff) claim)' >/dev/null; then
      printf '%s\n' "$f"
      return 0
    fi
    if tr -s '[:space:]' ' ' < "$f" | tr '[:upper:]' '[:lower:]' \
      | awk '{ gsub(/[.!?] /, "&\n"); print }' \
      | awk '/(^|[^a-z])claims?([^a-z]|$)/ && /(^|[^a-z])(comment(s|ed|ing)?|(take|takes|taken|taking|took) over|abandon(s|ed|ing)?|supersed(e|es|ed|ing))([^a-z]|$)/ { found = 1 } END { exit !found }'; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

fm_claim_ritual_brief_missing() {  # <brief-text>
  local task=$1 missing=
  printf '%s\n' "$task" | grep -Eiq '^[[:space:]>*-]*claim recovery:[[:space:]]*[^[:space:]]' \
    || missing="Claim recovery: <the project's recovery procedure for an abandoned claim>"
  printf '%s\n' "$task" | grep -Eiq '^[[:space:]>*-]*claim model:[[:space:]]*[^[:space:]]' \
    || missing="${missing:+$missing; }Claim model: <the exact model the ritual requires, or none required>"
  [ -z "$missing" ] && return 1
  printf '%s\n' "$missing"
}
