# shellcheck shell=bash
# Gate-delegation wording check.
# Usage: . bin/fm-gate-delegation-lib.sh
#
# ask-user-authority is the single owner of ask-user finding decisions, and a
# task worker escalates every ask-user finding to firstmate (bin/fm-dod-lib.sh
# renders that rule into every no-mistakes brief). No delegation exception
# exists, so free text firstmate writes to a worker must not hand the worker
# its own gate responses: a later "you own each gate response" in a spec or
# steer silently outranks the brief's rule in the worker's reading, and the
# worker then decides captain-owned findings itself.
#
# This file is the single owner of the delegation phrase list and its matcher.
# bin/fm-spawn.sh checks a ship or scout brief's `## Firstmate spec` (or a
# legacy `# Task` body) before launch, bin/fm-promote.sh checks the scout brief
# before it becomes the promoted brief, and bin/fm-send.sh checks the text of
# every steer to a task worker; each refuses and prints the matched phrase with
# FM_GATE_DELEGATION_RULE.
#
# A match is skipped when it only mentions or forbids the wording rather than
# granting it: the phrase opens right after a quote or backtick, an immediately
# preceding negation ("never", "do not", "don't") inverts it, or firstmate, the
# captain, "I", or "we" is its subject, directly or through a modal ("to",
# "can", "will then"). That keeps the rendered scaffold's own
# rule and a decision message answering a named finding through the gate from
# tripping it. Matching is case-insensitive and on whole words, over the whole
# text with every run of whitespace folded to one space, so a phrase wrapped
# across lines still matches.
# No side effects on source. set -u / set -e safe.

# shellcheck source=bin/fm-brief-heading-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fm-brief-heading-lib.sh"

# shellcheck disable=SC2034 # Read by the sourcing refusal sites.
FM_GATE_DELEGATION_RULE="ask-user-authority is the single owner of ask-user finding decisions: a worker escalates every ask-user finding to firstmate and never answers one itself, so a spec or steer must not hand gate responses to the worker; decide each finding under ask-user-authority and send the worker that decision for the named finding instead"

# One extended regular expression per line, matched against lower-cased text.
# Seeded from the phrases observed in a run where a spec and steer suspended
# the brief's escalation rule, plus their close variants.
fm_gate_delegation_patterns() {
  cat <<'EOF'
you (now )?own (each|every|all|any|the|your) ((no-mistakes|pipeline|ask-user) )?gates?( (response|responses|decision|decisions|answer|answers|call|calls))?
you (now )?own (each|every|all|any|the|your) ask-user (finding|findings|decision|decisions|question|questions)
(drive|handle|answer|decide|resolve|make|own) (each|every|all|any|the|your) ((no-mistakes|pipeline) )?gate (response|responses|decision|decisions|answer|answers|call|calls) (yourself|on your own|without escalating)
(answer|decide|resolve|handle|respond to) (each|every|all|any|the|your)? ?(of the )?ask-user (finding|findings|gate|gates|question|questions|decision|decisions) (yourself|on your own|without escalating)
decide (each|every|all|any|the|your) (of the )?ask-user (finding|findings)
(do not|don't|no need to|you need not|you don't need to) escalate (the |any |each |your )?ask-user
EOF
}

# Print the first delegating phrase in <text> with its whitespace folded; fail
# when the text contains none.
fm_gate_delegation_match() {  # <text>
  local patterns
  patterns=$(fm_gate_delegation_patterns)
  printf '%s\n' "$1" | LC_ALL=C FM_GATE_DELEGATION_PATTERNS=$patterns awk '
    { text = text (NR > 1 ? " " : "") $0 }
    END {
      gsub(/[[:space:]]+/, " ", text)
      gsub(/\342\200\231/, "'\''", text)
      lower = tolower(text)
      n = split(ENVIRON["FM_GATE_DELEGATION_PATTERNS"], pats, "\n")
      for (i = 1; i <= n; i++) {
        if (pats[i] == "") continue
        offset = 0
        rest = lower
        while (match(rest, pats[i])) {
          start = offset + RSTART
          len = RLENGTH
          prefix = substr(lower, 1, start - 1)
          prev = substr(prefix, length(prefix), 1)
          skip = 0
          if (prev ~ /[a-z0-9]/) skip = 1
          if (substr(lower, start + len, 1) ~ /[a-z0-9]/) skip = 1
          if (prev ~ /["`'\''\342\200\234]/) skip = 1
          if (prefix ~ /(^|[^a-z])(never|not|cannot|no longer)( ever)? $/) skip = 1
          if (prefix ~ /n'\''t $/) skip = 1
          if (prefix ~ /(^|[^a-z])(firstmate|the captain|captain|i|we)(('\''ll| will| shall| alone| itself| myself| to| can| should| must| may)( then)?)? $/) skip = 1
          if (!skip) {
            print substr(text, start, len)
            exit 0
          }
          offset = start
          rest = substr(lower, start + 1)
        }
      }
      exit 1
    }
  '
}

# Print the first delegating phrase in the brief text firstmate authors: the
# `## Firstmate spec` body, or the `# Task` body of a legacy brief without the
# two-subsection contract. The scaffold's own sections are never scanned.
fm_gate_delegation_brief_match() {  # <file>
  local file=$1 body
  [ -f "$file" ] || return 1
  if fm_brief_task_heading_present "$file" "## Firstmate spec"; then
    body=$(fm_brief_task_heading_body "$file" "## Firstmate spec")
  else
    body=$(fm_brief_heading_body "$file" "# Task")
  fi
  fm_gate_delegation_match "$body"
}
