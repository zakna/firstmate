---
name: retro
description: Run a retro on one landed ticket when the captain invokes /retro <ticket> or asks for a retro on a delivered ticket. The retro reviews the process that produced the change, not only the code, so the same review comment is never written twice. It produces one report with a fixed metrics block, the status of earlier retro follow-ups, a steering-file growth check, and at most five routed proposals; it proposes and never edits review rules, pipeline configuration, AGENTS.md, or brief includes.
user-invocable: true
metadata:
  internal: true
---

<!-- Credit: the routing test and the candidate categories are adapted from the `retro` skill in mattpocock/skills, https://github.com/mattpocock/skills/blob/d81f3a183412e71a5b1e84ca21bc1a35eea03a60/skills/engineering/retro/SKILL.md, MIT License, Copyright (c) 2026 Matt Pocock. -->

# retro

A retro studies one landed ticket and asks what in the process let each defect, delay, or repeated comment happen.
Its product is a small number of changes to the environment of the next ticket, each placed where it costs the least.
It is knowledge only: no branch, no push, no pull request, and no configuration change.

This skill has two readers.
The supervisor that receives `/retro <ticket>` follows "Dispatch".
The worker that writes the retro follows everything from "Worker procedure" on.

## Dispatch

1. Resolve `<ticket>` to one landed delivery: a task id in this home's backlog, a project issue, or a pull request.
   A landed delivery is a merged pull request or an approved local-only landing.
   If the ticket has not landed, or more than one delivery matches, say so and stop; a retro on work still under way measures nothing.
2. Dispatch a scout on the ticket's project through the ordinary scout intake.
   The retro always runs in a fresh worker, never the one that delivered the ticket, because the delivering worker cannot see its own blind spots and the supervisor's own errors are in scope.
   Give the scout a task id that contains `retro`, so later retros can find this one.
3. In the scout instructions, name the ticket id, its pull request or landing commit, the delivering task's id, and the absolute path of this file, and tell the worker to follow "Worker procedure".
   Add nothing that this file already states.
4. When the scout reports, handle it as any finished investigation.
   Filing the debt items, recording the proposals for the captain, and any approved change all stay with the supervisor; the report authorizes none of them.

## Worker procedure

You have the ticket id, its pull request or landing commit, and the records of this home.
You did not deliver the ticket; say so in the report's first lines.

### Boundary

Read everything; change nothing outside your report.
Never edit the shared pipeline configuration, a project's `.no-mistakes.yaml`, a project's `AGENTS.md` or `CLAUDE.md`, or `config/brief-include.md`.
The shared pipeline configuration serves every home on the machine, so a change to it is a separate approved action, never a retro side effect.
Do not file issues; write each one ready to file.
Open the pipeline database read-only.

### 1. Read the sources

- The delivering task's records under `data/<task-id>/`: its instructions, any saved review findings, and any review-comment inventory.
- The task's status log and steering messages, when cleanup has not yet removed them.
- The backlog item and its notes.
- The pull request: description, review comments from people and bots, checks, merge time, and the merged diff.
- The pipeline database, `${NM_HOME:-$HOME/.no-mistakes}/state.sqlite`, for the run on the ticket's branch.
- The earlier retro reports in this home: `grep -l '^# Retro: ' data/*/report.md`.

Label every statement OBSERVED, naming the record it was read from, or INFERRED.
List the sources you actually read at the top of the report, and name every expected source that was missing.

### 2. Previous follow-ups first

Before looking for anything new, take the open follow-ups and proposals of the earlier retros.
Re-verify each one in the artefact - the merged tree, the current instructions template, the current review rules - not in the backlog.
Give each a status: shipped and measured, shipped and not measured, not shipped, or retired.
Record passes as well as failures: a pattern an earlier retro named that demonstrably did not fire on this ticket is evidence.
When this ticket repeats an open follow-up, extend that row with the new evidence and do not file it again.
A shipped change whose named metric has not moved after its stated ticket count is proposed for retirement or re-scoping, not renewed.

### 3. The metrics block

Every retro carries this table, always in this form, so retros can be compared.
A metric that cannot be extracted is reported as such with the reason, never estimated.

| # | Metric | Source | Kind |
|---|---|---|---|
| M1 | Elapsed time, dispatch to merge | task records and the forge | number |
| M2 | Active pipeline time, excluding the `ci` step | pipeline database | number |
| M3 | Review rounds | pipeline database | number |
| M4 | Findings, total and the per-round sequence | pipeline database | number and sequence |
| M5 | Time parked on human gates, and its share of the run excluding the `ci` step | pipeline database | number |
| M6 | Human gate answers | pipeline database | number |
| M7 | Cost attribution: supervisor, instructions, pipeline, worker | your own cost analysis | judgement |
| M8 | Findings raised and never fixed, reconciled against the merged tree, and how many were recorded | pipeline database, then verification | number |
| M9 | Findings created by an earlier fix round, as a share of findings | your own classification | judgement |
| M10 | Defects this retro found on the default branch that the run missed | your own work | number |

Two conventions keep the numbers honest.

- Never read the `ci` step's duration as pipeline cost; it is mostly a wait for a merge.
  Report time to checks ready (`ci_ready_at` minus the run's start) and the merge wait after it separately.
- Use the database's round numbering and say so; rounds that the automatic repair budget absorbed never reach a person, so a worker's saved files count fewer.

For M10, "found none" never means "none exist"; state how much of the merged change you read.
A ticket delivered without the pipeline has no run; report M2 to M6 as not applicable, not as zero effort.

These queries extract M2 to M6 and the M8 worklist.
They read another tool's storage, so if one fails the schema has changed: report the metric under "Could not establish" and do not guess.

```sh
DB="${NM_HOME:-$HOME/.no-mistakes}/state.sqlite"

# the run: find it by branch, then use its id below
sqlite3 -readonly "$DB" "SELECT id, status, pr_url, created_at, ci_ready_at, updated_at, parked_ms
  FROM runs WHERE branch = '<branch>' ORDER BY created_at;"

# M2, and per-step durations
sqlite3 -readonly "$DB" "SELECT step_name, status, duration_ms FROM step_results
  WHERE run_id = '<run id>' ORDER BY step_order;"

# M3, M4, M6: one row per round with its findings count and who answered it
sqlite3 -readonly "$DB" "SELECT sr.step_name, rd.round, rd.selection_source,
    json_array_length(json_extract(rd.findings_json, '\$.findings')), rd.duration_ms
  FROM step_results sr JOIN step_rounds rd ON rd.step_result_id = sr.id
  WHERE sr.run_id = '<run id>' ORDER BY rd.created_at;"

# M8 worklist: findings raised and never selected for fixing
sqlite3 -readonly "$DB" "SELECT sr.step_name, rd.round, json_extract(f.value, '\$.id'),
    json_extract(f.value, '\$.severity'), json_extract(f.value, '\$.action'),
    json_extract(f.value, '\$.file'), json_extract(f.value, '\$.description')
  FROM step_results sr JOIN step_rounds rd ON rd.step_result_id = sr.id,
    json_each(json_extract(rd.findings_json, '\$.findings')) f
  WHERE sr.run_id = '<run id>'
    AND instr(COALESCE(rd.selected_finding_ids, ''), json_extract(f.value, '\$.id')) = 0
  ORDER BY rd.created_at;"
```

The M8 query is an upper bound, because a finding restated under a new identifier in a later round and fixed there still appears.
Reconcile every row against the merged tree before counting it.

### 4. What cost time

List at most ten cost items, ordered by cost, each with its cause: supervisor, instructions, pipeline, review configuration, or worker.
Look in particular for these shapes.

- A review comment, from a person or a bot, that an earlier ticket or an earlier round already received.
- A defect a later round found that was present in the first round.
- A finding created by an earlier fix.
- A finding caused by the supervisor's own instruction.
- A gate that asked a person a question whose answer was already written in the run's intent.
- A long search for a file or fact the worker needed.
- An expensive or repeated tool call.
- A fact the worker needed and could not reach.

Also state what went well and what was not a cost, so a later reader does not reopen a settled point.

### 5. Debt inventory

This part is uncapped.
List every finding or review comment the delivery left unfixed, declined, or deferred, verified against the default branch after the merge.
An item already fixed gets one line and no issue.
Write each remaining item ready to file, with:

- where it is on the default branch, file and line;
- the defect, quoting the code or text;
- the consequence, in the terms of the person who uses the project;
- a suggested direction, not a mandate;
- the project's own required labels;
- a link to the parent ticket and a statement that it is not a duplicate of it.

Keep supervisor vocabulary, quoted instructions, and direct address out of the issue text; it is published in the project.

### 6. Steering-file growth

Steering files are loaded into every session of a project or every worker of this home, so each added line taxes every later ticket.
Report one table.

| File | Lines at the previous retro | Lines now | Added by this ticket | Growth that is not navigation |
|---|---|---|---|---|

- The project's `AGENTS.md`, and `CLAUDE.md` when it holds its own text: count lines on the default branch now and at the ticket's base commit, and take the earlier count from the previous retro's table.
- This home's `config/brief-include.md`: count lines now and compare with the previous retro's table; it has no history, so without an earlier table report "no baseline".

A navigation line tells a reader where something is or which file owns a subject.
Any other added line - a rule, a lesson, a warning, a procedure - is growth that is not navigation; quote it and route it with the test in step 7.
Flag a steering file that grew since the previous retro with no line removed.
Also look for lines that no longer change behaviour, and propose their removal.

### 7. Proposals, at most five

A proposal changes the environment of the next ticket.
Order candidates by the cost they would have removed and keep at most five; point at an existing open row instead of repeating it.

Apply one routing test to every proposal and name the class in the report.

| Class | When | Where it goes |
|---|---|---|
| Automated check | The violation is mechanical: a fixed pattern, a banned call, a file-location rule, a missing declaration | A deterministic check in the project's own lint, test, hook, or CI, whichever is cheapest there; read what the project already runs first, because a check that exists and is unwired is the finding |
| Reviewer path rule | The violation is a judgement no check can make | A review rule scoped to the affected paths in the project's `.no-mistakes.yaml` |
| Navigation line | The worker could not find a file, an owner, or a command | One pointer line in the project's `AGENTS.md` or the brief include |

The reason for the order: the implementing worker carries the most context pressure, and the reviewer reads only a diff.
So standards belong to a check or to the reviewer, and a lesson never goes into the implementer's instructions or `AGENTS.md` unless it is navigation.
A change to the shared pipeline configuration, to the supervisor's own workflow, or to this retro procedure is also a valid proposal; name its owner file and say that it needs its own approval.

Each proposal must pass all four gates, which exist to stop overfitting to one ticket.

1. Recurrence or severity: it appears in at least two independent tickets, or its one occurrence shipped something wrong, dropped a stated requirement, or lost work.
2. Stated as a behaviour: you can name a future situation it fires on that is not this incident.
3. Small ongoing cost: minutes or one command per future ticket, and small against what it prevents.
4. Checkable and retirable: it names one metric from the block, the number of tickets after which it is judged, and the condition under which it is dropped.

For each proposal, write: the routing class, the evidence with its record, the owner file or configuration it would change, the drafted text or check, the four gate answers, and its cost stated honestly.
A candidate that fails a gate goes in one line under "Considered and not proposed", with the gate it failed.

### 8. Could not establish

This section is mandatory and uncapped.
Name every question the records could not answer, and the record or command that would settle it.

### 9. The practice itself

End with one short paragraph on this retro procedure: what it could not measure, which step produced nothing, and what would make the next retro cheaper or sharper.
A change to this file is a proposal like any other and counts toward the five.

## Report shape

Write the report to the path your instructions name, with `# Retro: <ticket>` as its first line.
Keep the sections in this order: sources read, previous follow-ups, metrics block, what cost time, debt inventory, steering-file growth, proposals, could not establish, the practice itself.

A retro must cost less than the ticket it studies.
If it is heading past that, stop and say which part you dropped; never drop the metrics block, the debt inventory, or "Could not establish".
