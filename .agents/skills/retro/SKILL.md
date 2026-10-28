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
Feedback across several tickets merged through no-mistakes pipeline runs, for the periodic trend review, comes from `bin/fm-feedback-collect.sh` instead.

This skill has two readers.
The supervisor that receives `/retro <ticket>` follows "Dispatch".
The worker that writes the retro follows everything from "Worker procedure" on.

## Dispatch

1. Resolve `<ticket>` to one landed delivery: a task id in this home's backlog, a project issue, or a pull request.
   A landed delivery is a merged pull request, a submitted Gerrit change on a project registered with `forge=gerrit`, or an approved local-only landing.
   If the ticket has not landed, or more than one delivery matches, say so and stop; a retro on work still under way measures nothing.
2. Dispatch a scout on the ticket's project through the ordinary scout intake.
   The retro always runs in a fresh worker, never the one that delivered the ticket, because the delivering worker cannot see its own blind spots and the supervisor's own errors are in scope.
   Give the scout a task id that contains `retro`, so later retros can find this one.
3. In the scout instructions, name the project, the ticket id, its pull request or landing commit, the delivering task's id, and the absolute path of this file, and tell the worker to follow "Worker procedure".
   Add nothing that this file already states.
   The scout reads this home's defect-class register at `${FM_HOME:?}/data/retro-defect-classes.md` through "Worker procedure", so the instructions do not restate it.
4. When the scout reports, handle it as any finished investigation.
   Filing the debt items, recording the proposals for the captain, and any approved change all stay with the supervisor; the report authorizes none of them.
   The supervisor also adds each new defect class the report proposes to the register, keeping the earliest meaning on a letter and never reusing one.
   A debt item that names a concrete structure-only tidy in a code area gets the tidy slot that `ship-landing` owns.
   An automated-check proposal that passed the four gates and that the captain approves gets the guard slot that `ship-landing` owns; a candidate under "Considered and not proposed" never does.
   The supervisor records each open workflow-level follow-up and each approved Process change in `${FM_HOME:?}/data/retro-workflow-followups.md`, and removes an entry once a retro verifies it done.

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
- The task's status log and steering messages: under `state/` while the task runs, and after cleanup as `status-log.txt` and `steering/` under `data/<task-id>/`.
- The backlog item and its notes.
- The pull request, or on a Gerrit project the submitted change: description, review comments from people and bots, checks or label votes, patch sets, merge or submit time, and the merged diff.
- The pipeline database, `${NM_HOME:-$HOME/.no-mistakes}/state.sqlite`, for every run on the ticket's branch or pull request in the ticket's own repository, matched by its project clone, the `project=` path in the delivering task's metadata described below.
- The earlier retro reports of the same project in this home: the reports whose first line starts with `# Retro: ` and whose second line is exactly `Project: <project>`.
  `P='<project>'; export P; if [ -d "${FM_HOME:?}/data" ]; then find "${FM_HOME:?}/data" -mindepth 2 -maxdepth 2 -type f -name report.md -exec awk 'FNR == 1 { retro = substr($0, 1, 9) == "# Retro: " } FNR == 2 && retro && $0 == "Project: " ENVIRON["P"] { print FILENAME }' {} +; fi`
  A home may hold several projects, and another project's follow-ups are not evidence about this one.
- The earlier retro reports with no `Project:` line anywhere, which were written before this skill: keep each one whose body links into the project's repository, and name every report found this way in your list of sources.
  `if [ -d "${FM_HOME:?}/data" ]; then find "${FM_HOME:?}/data" -mindepth 2 -maxdepth 2 -type f -name report.md -exec awk 'FNR == 1 && substr($0, 1, 9) == "# Retro: " { print FILENAME }' {} +; fi | while IFS= read -r f; do grep -q '^Project:' "$f" || grep -lE '(^|[^[:alnum:]_.-])<repository address>([^[:alnum:]_-]|$)' "$f"; done`, where `<repository address>` is the repository's web address without its scheme, such as `github.com/<owner>/<repo>`; for Gerrit, use `gerrit.example.com/(c/)?<project>` so both the repository root and canonical change URLs match.
- This home's defect-class register, `${FM_HOME:?}/data/retro-defect-classes.md`: the lettered classes that name recurring defect shapes across retros.
  It is captain-private, so cite classes by letter and name and never copy its text into a tracked file; when the file is absent, name defect shapes in plain words and propose the first register entries in the report.
- The landing notes, `${FM_HOME:?}/data/<task-id>/landing-note.md`, of this project's tasks that landed since the previous retro.
  A task's `project=` record names its project clone by the absolute resolved path `bin/fm-spawn.sh` wrote, in `${FM_HOME:?}/state/<task-id>.meta` before cleanup and in `${FM_HOME:?}/data/<task-id>/meta.txt` after it.
  The query reads that path from the delivering task's own metadata, so a project name or a relative path never reaches the match; it stops with an error when that metadata names no project.
  `T='<delivering task-id>'; M="${FM_HOME:?}/state/$T.meta"; [ -f "$M" ] || M="${FM_HOME:?}/data/$T/meta.txt"; C=$(sed -n 's/^project=//p' "$M" 2>/dev/null | tail -n 1); if [ -z "$C" ]; then echo "no project= record for $T" >&2; elif [ -d "${FM_HOME:?}/data" ]; then for n in "${FM_HOME:?}"/data/*/landing-note.md; do [ -f "$n" ] || continue; id=$(basename "$(dirname "$n")"); m="${FM_HOME:?}/state/$id.meta"; [ -f "$m" ] || m="${FM_HOME:?}/data/$id/meta.txt"; [ -f "$m" ] && grep -qxF "project=$C" "$m" && printf '%s\n' "$n"; done; fi`
  Keep a listed note only when its task's landing evidence shows it landed after the delivery studied by the newest earlier retro of this project found above landed, read by resolving its `# Retro:` ticket to its landed delivery as Dispatch step 1 does and taking that pull request's or change's merge time, or that delivering task's landing evidence below, or at any time when there is none; always keep the note of the delivery under study, because retros finish in a different order than their tickets merge.
  Landing evidence is the merge time of the pull request or change that `pr=` in that same metadata file names or, with no `pr=`, of the merged one whose head branch is `branch=`, or else, for a local-only task, the date of the entry `merge <branch=>: Fast-forward` in `git -C <project clone> reflog --date=iso <default branch>`; a task with no such evidence did not land, and its note is skipped.
  Each answer (c) names a fact the instructions or the project's `AGENTS.md` did not give the worker, and each answer (b) names the tidy that worker proposed.
- This home's workflow follow-ups, `${FM_HOME:?}/data/retro-workflow-followups.md`: follow-ups about the instructions template, the review configuration, or the supervising practice, which belong to no single project.
  Every retro re-verifies them, whatever its project; when the file is absent, treat it as empty.

Label every statement OBSERVED, naming the record it was read from, or INFERRED.
List the sources you actually read at the top of the report, and name every expected source that was missing.

### 2. Previous follow-ups first

Before looking for anything new, take the open follow-ups and proposals of the earlier retros and of the workflow follow-ups in `${FM_HOME:?}/data/retro-workflow-followups.md`.
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
| M2 | Active pipeline time, excluding the `ci` step | pipeline database, and on GitHub the pull request head's check runs for time to checks ready | number |
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
  Report time to checks ready as the latest `completed_at` of the pull request head's check runs (`gh api --paginate "repos/<owner>/<repo>/commits/<head>/check-runs?per_page=100" --jq '.check_runs[]|[.name,.conclusion,.completed_at]|@tsv'`) minus the run's start.
  Report `ci_ready_at` beside it only when the two differ; it is re-set when the base branch advances.
  On GitLab and Gerrit, which have no GitHub check runs, report `ci_ready_at` instead and say so.
  Report the merge wait after it separately.
- Use the database's round numbering and say so.
  A gate escalation's findings file starts with its `round=` and `head=` line, so match files to rounds by it.
  A file without that first line, or with an empty or `unknown` round, predates it or could not read the round: match it by its run id and the round's head in `step_rounds`, and say so in the report.
  Rounds that the automatic repair budget absorbed never reach a person, so a worker's saved files count fewer.

For M10, "found none" never means "none exist"; state how much of the merged change you read.
A ticket delivered without the pipeline has no run; report M2 to M6 as not applicable, not as zero effort.

These queries extract M2 to M6 and the M8 worklist.
They read another tool's storage, so if one fails the schema has changed: report the metric under "Could not establish" and do not guess.
A delivery whose validation was cancelled, failed, or restarted has several runs; every attempt is part of the process under study.
In the first query, `<project clone>` is that exact `project=` path, the primary clone the database registers as `working_path`; a query returning no run for a ticket you know was validated means the path is wrong, not that the pipeline was skipped.
Run the per-run queries for each run the first query returns, report M2 to M6 per attempt, and add the attempts up for the block, keeping the attempts distinguishable.

```sh
DB="${NM_HOME:-$HOME/.no-mistakes}/state.sqlite"

# every attempt: all runs on the delivery's branch or pull request in the delivery's own repository
sqlite3 -readonly "$DB" "SELECT r.id, p.working_path, r.status, r.pr_url, r.created_at, r.ci_ready_at, r.updated_at, r.parked_ms
  FROM runs r JOIN repos p ON p.id = r.repo_id
  WHERE p.working_path = '<project clone>' AND (r.branch = '<branch>' OR r.pr_url = '<pull request url>')
  ORDER BY r.created_at;"

# M2, and per-step durations
sqlite3 -readonly "$DB" "SELECT step_name, status, duration_ms FROM step_results
  WHERE run_id = '<run id>' ORDER BY step_order;"

# M3, M4, M6: one row per round with its findings count and who answered it
sqlite3 -readonly "$DB" "SELECT sr.step_name, rd.round, rd.selection_source,
    json_array_length(json_extract(rd.findings_json, '\$.findings')), rd.duration_ms
  FROM step_results sr JOIN step_rounds rd ON rd.step_result_id = sr.id
  WHERE sr.run_id = '<run id>' ORDER BY rd.created_at;"

# M8 worklist: every finding raised, with whether a fix round selected it
sqlite3 -readonly "$DB" "SELECT sr.step_name, rd.round, json_extract(f.value, '\$.id'),
    json_extract(f.value, '\$.severity'), json_extract(f.value, '\$.action'),
    EXISTS (SELECT 1 FROM json_each(COALESCE(NULLIF(rd.selected_finding_ids, ''), '[]')) s
      WHERE s.value = json_extract(f.value, '\$.id')) AS selected,
    json_extract(f.value, '\$.file'), json_extract(f.value, '\$.description')
  FROM step_results sr JOIN step_rounds rd ON rd.step_result_id = sr.id,
    json_each(json_extract(rd.findings_json, '\$.findings')) f
  WHERE sr.run_id = '<run id>'
  ORDER BY rd.created_at;"
```

Selection records an intent to repair, not proof that the fix worked or survived to the merge, and a finding restated under a new identifier in a later round appears twice.
So reconcile every row, selected or not, against the merged tree before counting it for M8.

### 4. What cost time

Ask first of each cost item: could a check (test, lint, type, or script) have caught this?
A yes makes it an automated-check candidate for step 7, which still has to pass the four gates there.
List at most ten cost items, ordered by cost, each with its cause: supervisor, instructions, pipeline, review configuration, or worker.
Label each cost item with its class from the register when one fits.
When a defect fits no class, describe it plainly and propose a new class, with its one-line definition and the retros it appears in, for the supervisor to add; you do not edit the register yourself.
Look in particular for these shapes when the register is absent or does not cover them.

- A review comment, from a person or a bot, that an earlier ticket or an earlier round already received.
- A defect a later round found that was present in the first round.
- A finding created by an earlier fix.
- A finding caused by the supervisor's own instruction.
- A gate that asked a person a question whose answer was already written in the run's intent.
- A long search for a file or fact the worker needed.
- An expensive or repeated tool call.
- A fact the worker needed and could not reach.

A merge made outside the fleet's merge command is never a finding or a cost item: record only the merge method and the resulting commit from the task's external-merge note, reading the method from its parent count (two parents is a merge commit, one is a squash or rebase merge, `unknown` stays unknown).
Also state what went well and what was not a cost, so a later reader does not reopen a settled point.

### 5. Debt inventory

This part is uncapped.
Ask the same check question first of each debt item, with the same consequence for a yes.
List every finding or review comment the delivery left unfixed, declined, or deferred, verified against the default branch after the merge.
An item already fixed gets one line and no issue.
Write each remaining item ready to file, with:

- where it is on the default branch, file and line;
- the defect, quoting the code or text;
- the consequence, in the terms of the person who uses the project;
- a suggested direction, not a mandate; when it names a command or a pass condition, run it against a reproduction that carries the target's recorded environment facts and cite the command, or mark it `unrun:` and list each outcome the operator can see and what each outcome means;
- the project's own required labels;
- a link to the parent ticket and a statement that it is not a duplicate of it; when the delivery has no external ticket, such as an approved local-only landing, the delivering task's backlog id, or the explicit marker `no parent ticket`, in place of the link.

Keep supervisor vocabulary, quoted instructions, and direct address out of the issue text; it is published in the project.
Whoever files an item first saves its body to a file `B` and refuses to file when this check prints any line, because a body sliced past its item's end publishes the rest of the report.
`P='^#{1,3} [0-9]+\.|captain|brief-include|(^|[^/[:alnum:]_.-])data/[a-z0-9-]+/(report|brief|launch-brief|landing-note|handoff)\.md'; [ "$FIRSTMATE_TARGET" = 1 ] || P="$P|firstmate"; grep -n -i -E "$P" "$B" || grep -n -E '(^|[^[:alnum:]_./-]|file://)/(Users|home)/[^/[:space:]]+/|[A-Za-z]:\\Users\\' "$B" || grep -n -F "${FM_HOME:?}" "$B"`
Set `FIRSTMATE_TARGET=1` only when the retro's target repository is the firstmate repository itself, so its own links and paths are not refused.
It refuses a report heading such as `## 3. Debt inventory`, `captain`, `brief-include`, `/Users/ana/`, `/home/ana/`, `C:\Users\ana\`, `data/fix-login-a1/report.md`, and any path under this home.
It passes project paths and routes such as `tests/data/fixtures/`, `src/data/models/report.md`, `docs/data/brief.md`, `src/users/models/user.py`, `app/users/views/`, `GET /api/users/42/orders`, and `frontend/home/components/Header.tsx`.

### 6. Steering-file growth

Steering files are loaded into every session of a project or every worker of this home, so each added line taxes every later ticket.
Report one table.

| File | Lines at the previous retro | Lines now | Added by this ticket | Growth that is not navigation |
|---|---|---|---|---|

- The project's `AGENTS.md`, and `CLAUDE.md` when it holds its own text: "Added by this ticket" is the count at the landing commit minus the count at the ticket's base commit, "Lines now" is the count on the default branch now, and the earlier count comes from the previous retro's table.
- This home's `config/brief-include.md`: it has no history, so copy it beside your report as `brief-include.md`, count its lines, and diff it against the copy the previous retro saved; without an earlier copy report "no baseline".

A navigation line tells a reader where something is or which file owns a subject.
Any other added line - a rule, a lesson, a warning, a procedure - is growth that is not navigation; quote it and route it with the test in step 7.
Flag a steering file that grew since the previous retro with no line removed.
Also look for lines that no longer change behaviour, and propose their removal.

### 7. Proposals, at most five

A proposal changes the environment of the next ticket.
Order candidates by the cost they would have removed and keep at most five; point at an existing open row instead of repeating it.

Apply one routing test to every proposal and name the routing class in the report; it is a different axis from the defect classes of the register.
When a check could have caught it, propose that check as an automated check, in preference to any new rule or prose text.

| Routing class | When | Where it goes |
|---|---|---|
| Automated check | The violation is mechanical: a fixed pattern, a banned call, a file-location rule, a missing declaration | A deterministic check in the project's own lint, test, hook, or CI, whichever is cheapest there; read what the project already runs first, because a check that exists and is unwired is the finding |
| Reviewer path rule | The violation is a judgement no check can make | A review rule scoped to the affected paths in the project's `.no-mistakes.yaml` |
| Navigation line | The worker could not find a file, an owner, or a command | One pointer line in the project's `AGENTS.md` or the brief include |
| Process change | The cost came from the shared pipeline configuration, the supervisor's own workflow, or this retro procedure, not from the project | The owner file of that process, named in the proposal, with a note that it needs its own approval |

The reason for the order: the implementing worker carries the most context pressure, and the reviewer reads only a diff.
So standards belong to a check or to the reviewer, and a lesson never goes into the implementer's instructions or `AGENTS.md` unless it is navigation.

Each proposal must pass all four gates, which exist to stop overfitting to one ticket.

1. Recurrence or severity: it appears in at least two independent tickets, the same review comment was written in two review rounds of this ticket, or its one occurrence shipped something wrong, dropped a stated requirement, or lost work.
2. Stated as a behaviour: you can name a future situation it fires on that is not this incident.
3. Small ongoing cost: minutes or one command per future ticket, and small against what it prevents.
4. Checkable and retirable: it names one metric from the block, the number of tickets after which it is judged, and the condition under which it is dropped.

For each proposal, write: the routing class, the cue - the future situation from gate 2 - the evidence with its record, the owner file or configuration it would change, the drafted text or check, the four gate answers, its confidence, and its cost stated honestly.
For a drafted check, list each failure symptom the evidence records and say whether the draft catches it; where it is cheap, run the draft against a reproduction of that symptom and cite the command.
Confidence is high when independent tickets or the mechanism read in the artefact confirm the cause, and medium when one occurrence directly confirms the observed fact or has a named cause.
A candidate that fails a gate goes in one line under "Considered and not proposed", with the gate it failed.
A candidate whose evidence is mixed, confounded, or a single occurrence with neither a named cause nor direct confirmation, such as one run that might have passed by luck, is not proposed: record it there as `no entry` with what would settle it.

### 8. Could not establish

This section is mandatory and uncapped.
Name every question the records could not answer, and the record or command that would settle it.

### 9. The practice itself

End with one short paragraph on this retro procedure: what it could not measure, which step produced nothing, and what would make the next retro cheaper or sharper.
A change to this file is a proposal like any other and counts toward the five.

## Report shape

Write the report to the path your instructions name, with `# Retro: <ticket>` as its first line and `Project: <project>` as its second, so later retros of the same project can find it.
Keep the sections in this order: sources read, previous follow-ups, metrics block, what cost time, debt inventory, steering-file growth, proposals, could not establish, the practice itself.

A retro must cost less than the ticket it studies.
If it is heading past that, stop and say which part you dropped; never drop the metrics block, the debt inventory, or "Could not establish".
