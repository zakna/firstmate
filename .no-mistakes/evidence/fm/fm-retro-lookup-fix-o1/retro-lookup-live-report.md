# Retro: landing-live-lookup
Project: github.com/zakna/firstmate

This retro was written by a fresh worker that did not deliver the ticket.
Ticket: landing-live-lookup, approved local-only landing at commit a62a04745766b9a1c4025967b90cbb60604a6f8b (disposable validation fixture).

## Sources read

- OBSERVED `data/backlog.md`: item `landing-live-lookup` in Done, "approved local-only landing for retro validation".
- OBSERVED `data/landing-live-lookup/landing.md`: project, landing commit, status "approved local-only landing".
- OBSERVED landing commit a62a0474 (`git show --stat`): "no-mistakes(review): Rooted retro data paths; restored original metrics query", `.agents/skills/retro/SKILL.md`, +7/-13.
- OBSERVED earlier retros for this project, by `Project:` line: `data/retro-project-tagged/report.md`.
- OBSERVED legacy retros with no `Project:` line linking into github.com/zakna/firstmate: `data/retro-legacy-repository/report.md`.
- Excluded, OBSERVED: `data/retro-wrong-project/report.md` (Project: github.com/other/project, so not a legacy fallback despite its link); `data/retro-unrelated/report.md` (no Project line, links only to github.com/other/project).
- OBSERVED `data/retro-workflow-followups.md`.
- Missing: delivering task instructions, saved review findings, status log, steering messages (no `state/` records), pull request (local-only landing, no forge contact by instruction), delivering task id beyond the backlog id, `config/brief-include.md`.

## Previous follow-ups

| Follow-up | Origin | Status | Evidence |
|---|---|---|---|
| tagged-earlier-follow-up | retro-project-tagged | not shipped (cannot verify) | OBSERVED: the report names it with no content; no artefact to check against. |
| legacy-earlier-follow-up | retro-legacy-repository | not shipped (cannot verify) | OBSERVED: same; no artefact named. |
| workflow-live-follow-up: supervisor records Process changes in the ledger | retro-workflow-followups.md | shipped and not measured | OBSERVED: the ledger exists and holds this entry; INFERRED: no Process change was approved in this ticket, so no new recording event to measure. |

## Metrics block

| # | Metric | Value |
|---|---|---|
| M1 | Elapsed time, dispatch to merge | Could not establish: no dispatch record; landing commit time 2026-10-02 14:49:45 +0200 only. |
| M2 | Active pipeline time excl. `ci` | Not applicable: local-only landing; no run attributed to this ticket's branch was identified (branch unnamed in records). |
| M3 | Review rounds | Not applicable (as M2). |
| M4 | Findings, total and per round | Not applicable (as M2). |
| M5 | Time parked on human gates | Not applicable (as M2). |
| M6 | Human gate answers | Not applicable (as M2). |
| M7 | Cost attribution | Judgement: negligible; fixture ticket, single 20-line skill-file commit. |
| M8 | Findings never fixed | Not applicable: no findings record. |
| M9 | Findings created by an earlier fix | Not applicable. |
| M10 | Defects found on default branch | 0, after reading the commit stat only, not the full diff. |

## What cost time

Nothing measurable; the records hold no timing, steering, or review data.
Not a cost: the landing was approved and recorded consistently in backlog and landing record.

## Debt inventory

None recorded; no findings or review comments exist for this ticket.

## Steering-file growth

| File | Lines at previous retro | Lines now | Added by this ticket | Growth that is not navigation |
|---|---|---|---|---|
| AGENTS.md | no baseline (previous retro has no table) | 426 | 0 (426 at a62a0474^ and at a62a0474) | none |
| config/brief-include.md | no baseline | absent | n/a | none |

## Proposals

None. Considered and not proposed: requiring the landing record to name the delivering branch so M2 to M6 can be looked up, fails gate 1 (single fixture occurrence, nothing shipped wrong).

## Could not establish

- M1 dispatch time: needs the spawn record or `state/<task-id>.status` for landing-live-lookup.
- Whether any pipeline run belongs to this ticket: needs the delivering branch name for the runs query.
- Content of the two earlier open follow-ups: their reports name them without describing a checkable change.
- Full-diff review for M10: `git show a62a0474` was not read in full.

## The practice itself

On a local-only fixture with no task records, steps 3 to 5 produced nothing; source discovery and follow-up re-verification were the only productive steps, and the project/legacy filters behaved as specified.
A landing record that names the branch would make the next local-only retro sharper.
