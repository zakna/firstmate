---
name: crewmate-brief-authoring
description: Load before writing, amending, or regenerating any ship, scout, or charter brief, to fill the scaffold's intent and spec subsections correctly.
user-invocable: false
metadata:
  internal: true
---

# Crewmate brief authoring

Moved from AGENTS.md section 11 "Crewmate briefs".

`bin/fm-brief.sh` and its help own scaffold syntax, generated variants, and status protocol; `bin/fm-dod-lib.sh` owns delivery-mode definitions of done, and each script's header owns its exact safety mechanics.
Use its scaffold as the contract, then fill `## Captain's intent` (`{TASK}`) with the captain's own ask and any boundary the captain stated, plus the context needed to read it, including the substance of any report, decision, or PR the ask refers to; never widen the ask there into a general goal or an enumerated coverage list, because the reviewer treats that subsection as acceptance criteria.
Fill `## Firstmate spec` (`{FIRSTMATE_SPEC}`) with only the build instructions that ask requires, naming what stays out of scope when the ask is narrow; a generalization, consistency sweep, or extra hardening the captain did not ask for is follow-up work to note, not scope to add.
`bin/fm-dod-lib.sh` owns intent authoring without added speaker labels or direct address, its provenance markers, what a no-mistakes worker may pass as `--intent`, and the string's self-sufficiency rule.
Keep additions task-specific rather than repeating lifecycle instructions, and alter generated sections only when the task genuinely differs from the standard shape.

If a task will drive Herdr lifecycle behavior, scaffold with `--herdr-lab`; if that need appears after an unguarded scaffold, stop and regenerate rather than adding commands by hand.
The generated Herdr contract must use a named non-`default` isolated lab and its guarded helper for every lifecycle action.

Load `secondmate-provisioning` before creating or using a charter brief.

The scaffold is a safety contract, not a suggestion.
