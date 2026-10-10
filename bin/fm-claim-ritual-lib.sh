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
# AGENTS.md or CLAUDE.md that qualifies a claim as abandoned, stale,
# superseding, or recovered (the qualifier within two words before "claim"). It fails when the project declares none.
#
# fm_claim_ritual_brief_missing prints the lines a brief's `# Task` body still
# lacks and fails when it carries both: a `Claim recovery:` line naming the
# project's recovery procedure and a `Claim model:` line naming the model the
# ritual requires (or stating that none is required). bin/fm-spawn.sh refuses a
# first launch of a ship task whose project declares a ritual and whose brief
# lacks either line. This file is the single owner of both line labels.
# No side effects on source. set -u / set -e safe.

# shellcheck source=bin/fm-brief-heading-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fm-brief-heading-lib.sh"

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
    if grep -Eiq '(abandon|stale|supersed|recover)[a-z]*( [^ .]+){0,2} claim' "$f"; then
      printf '%s\n' "$f"
      return 0
    fi
  done
  return 1
}

fm_claim_ritual_brief_missing() {  # <brief-file>
  local task missing=
  task=$(fm_brief_heading_body "$1" "# Task")
  printf '%s\n' "$task" | grep -Eiq '^[[:space:]>*-]*claim recovery:[[:space:]]*[^[:space:]]' \
    || missing="Claim recovery: <the project's recovery procedure for an abandoned claim>"
  printf '%s\n' "$task" | grep -Eiq '^[[:space:]>*-]*claim model:[[:space:]]*[^[:space:]]' \
    || missing="${missing:+$missing; }Claim model: <the exact model the ritual requires, or none required>"
  [ -z "$missing" ] && return 1
  printf '%s\n' "$missing"
}
