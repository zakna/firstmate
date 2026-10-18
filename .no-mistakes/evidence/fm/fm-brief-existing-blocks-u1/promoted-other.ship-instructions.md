Delivery: this task is finished only when the /no-mistakes run you start has opened a PR; run /no-mistakes yourself as soon as your implementation is committed, because a `done:` line without that PR's https:// URL is refused.

Your scout task has been promoted to a ship task, mode=no-mistakes. Your window, worktree, and context stay as they are; only the contract below changes.

# Task
## Captain's intent
Ship the change.

## Firstmate spec
If these promotion steps were already completed before a relaunch, preserve the existing `fm/pr-other` branch and continue from its current state; do not repeat them destructively.
1. **Verify isolation before anything else.** Run `pwd -P` and `git rev-parse --show-toplevel`; both must resolve to the disposable task worktree you were launched in, such as a treehouse pool path or an Orca-managed worktree, not the primary checkout firstmate operates from. If either does not resolve to the worktree you were launched in, stop and escalate to firstmate.
2. Inventory this worktree's scratch state with `git status` and `git log` before changing anything.
3. Return to a clean default-branch base, then create your branch: `git checkout -b fm/pr-other --`.
4. Carry over only the intended fix changes. Leave scratch commits, debug edits, and experiment files behind.
5. If you reproduced a bug, turn that reproduction into a regression test.
6. Treat the scout-time Firstmate spec and any unmarked legacy `# Task` text as investigation context, not captain intent or current ship-time instructions.
7. Everything else in your original instructions carries over unchanged: the status protocol; the instruction inbox and its acknowledgement; the escalation rules, including ask-user; and every safety rule, except where the current delivery contract below explicitly replaces scout-only delivery rules.


# Scope allowance
However narrowly the task above states its scope, the smallest downstream changes needed to keep already accepted behavior correct, add behavioral tests where an executable contract exists, or keep documentation accurate stay within this task even in files it does not name; Firstmate's `/Users/olivier/.no-mistakes/worktrees/0b1ab7dd6182/01M5732N4Y38BT5W4XYPF4ZVE0/.agents/skills/validation-supervision/SKILL.md` owns this allowance.

# Current delivery mode contract
This task is now kind=ship with mode=no-mistakes.
This section supersedes every earlier brief instruction about delivery mode.
These current ship instructions supersede the scout delivery rules and report-based Definition of done.
Any earlier "Never push" or scout-only delivery language in this file is superseded.
This replaces the scout rule limiting outside-worktree writes to the report and status file.
Keep project edits inside this worktree; keep proof and scratch output outside it, under `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.CpqNHB/data/pr-other/` or a temporary directory.
Outside the worktree, write only that task material and the status and steering-inbox records authorized below.
Leave the worktree clean before reporting done.
The mode-specific Definition of done below is the current delivery contract.

# Current ship safety rule
1. Never push to the default branch. Never merge a PR.

The no-mistakes ask-user escalation below supersedes the scout rule 6 escalation shape.
   For a no-mistakes ask-user gate specifically, escalate all ask-user findings as one event plus one snapshot file, using that same shape even when the gate holds only a single ask-user finding: write only the ask-user findings, verbatim and unparaphrased (id, severity, file, line, description, authority), to `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.CpqNHB/data/pr-other/nm-<run>-findings.txt`, then report the gate with
   `needs-decision [at=<epoch>] [key=nm-<run>-<step>]: ask-user findings=<id1>,<id2>,... file=/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.CpqNHB/data/pr-other/nm-<run>-findings.txt`
   naming every ask-user finding id from that gate. The status line only points at the file; it never restates or summarizes a finding's content.

# Definition of done
Delivery contract: mode=no-mistakes
Ship branch: fm/pr-other
The task is complete only when the /no-mistakes run you start has opened a PR for your branch and reached the return point below.
As soon as your implementation is committed on your branch, run /no-mistakes yourself to validate it and ship a PR; do not append `done:` first and do not wait for firstmate to tell you.
A `done:` line that names no PR URL is refused and read as blocked, not finished.
The pipeline owns the push; never push from this copy.

You drive no-mistakes by responding to its gates, not by implementing fixes.
Follow the guidance no-mistakes itself provides for the mechanics: it loads when you invoke /no-mistakes, and `no-mistakes axi run --help` plus the `help` lines in each `axi` response are authoritative and version-matched to the installed binary.
When starting no-mistakes, pass `--intent` as only this brief's `## Captain's intent` subsection body, not its heading, plus any later words the captain actually said.
Preserve the actual words without adding speaker labels or direct address; the subsection heading supplies provenance outside the pipeline input.
For a legacy brief with no such subsection, include only words on lines marked `[captain] `, excluding that metadata prefix; never copy its mixed `# Task` wholesale.
If it has no provenance-marked captain words, stop and ask firstmate instead of starting no-mistakes.
Do not include `## Firstmate spec`, later Firstmate build constraints, or your own decisions and tradeoffs.
The `--intent` string you pass must be self-sufficient: that string plus the codebase must let a reader reconstruct roughly the same specification, without depending on a separate report, a PR, or context that lives only in this conversation.
When the captain's intent refers to a report, decision, or PR ("do items 1, 2, 3, and 7 of the report"), write the substance of the referenced items into `--intent` in the captain's terms, not only the pointer; that substance is the captain's ask by reference, while Firstmate's build instructions and your own decisions still stay out.
This replaces the no-mistakes skill's advice to enrich `--intent` with decisions and tradeoffs; that advice does not apply to Firstmate-dispatched work.
The pipeline publishes the `--intent` string as the pull request body, so check it before the run starts.
From this repository, run `/Users/olivier/.no-mistakes/worktrees/0b1ab7dd6182/01M5732N4Y38BT5W4XYPF4ZVE0/bin/fm-intent-check.sh scrub /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.CpqNHB/data/pr-other` to print the authorized words with a `Refs #<n>` last line for each issue of this repository the brief links and the words do not already reference; never add a reference the brief does not name.
Scrub never removes or rewords a sentence: when it refuses a line it prints nothing, names each refused line, and exits non-zero.
Write the exact string you will pass to a file, run `/Users/olivier/.no-mistakes/worktrees/0b1ab7dd6182/01M5732N4Y38BT5W4XYPF4ZVE0/bin/fm-intent-check.sh check /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.CpqNHB/data/pr-other <file>`, and pass that file's content unchanged only when the check passes.
The check refuses speaker labels, direct address, attributed quotes, these fleet terms where this repository's own files do not use them (captain, firstmate, first mate, crewmate, secondmate, second mate, supervisor, fleet, no-mistakes, the brief, this brief, firstmate spec, status file, the worker, the user), and any sentence outside the authorized words; name later captain words with `--captain-words <file>` and the resolved substance of a referenced report, decision, or PR with `--resolved <file>`, which still pass every other rule.
When scrub or the check refuses a line, never drop or reword it yourself: ask firstmate to reword the authorized intent in the source file the refusal names, and in `brief.md`'s `## Captain's intent` so a relaunch agrees, then rerun the check, or stop; never start the run with a refused string.
Do not hand-edit, commit, or fix findings yourself while a run is active - the pipeline applies every fix.

One drive call blocks until the next gate or outcome, which routinely outlives what your harness lets a single command run: Claude Code kills a command at ten minutes maximum, while one fix round is capped around thirty minutes and up to three rounds chain.
So background the drive call instead of sitting in one blocking hold your harness will kill, and read its return when it finishes.
Declare that wait using the brief's status-reporting rule before waiting on the backgrounded drive call.
Where a harness's own command limit is not established, assume it bounds commands and use that same backgrounded shape.
Only a drive call's return reports the green PR: `no-mistakes axi status` shows progress but never reports `checks-passed` while the ci step is still monitoring the PR for merge, so never wait on a status poll for the next gate or outcome.
Whenever a drive call returns without a gate or an outcome - its own wait elapsed, or it was killed or timed out - reattach at once by re-running `no-mistakes axi run` without flags, backgrounded the same way; once checks are green it returns `checks-passed` immediately, and if it refuses because no run is active, read the finished outcome from `no-mistakes axi status`.
A killed or timed-out call is never evidence the daemon died: the daemon accepts your response immediately and runs the round in the background, so the call was only ever waiting for a read while the run kept working.
Reattach and keep going rather than reporting the pipeline blocked; rule 7 owns the checks that decide when a pipeline block is real.

Two firstmate-specific rules layer on top of that guidance:
- ask-user findings are never yours to answer: escalate to firstmate using rule 6's ask-user format and stop.
  Firstmate applies `ask-user-authority` and obtains any required captain decision.
  When the decision comes back, feed it to the gate with `no-mistakes axi respond` and let the pipeline apply it - do not route the question to "the user" or implement the fix yourself.
- NEVER pass `--yes` (or `-y`) to `no-mistakes axi run` or `no-mistakes axi respond`. It is banned fleet-wide.
  It auto-resolves every gate including ask-user findings with no escalation, and answering your own ask-user finding is a hard rule violation.

Your ready return point and ready line depend on whether this repository declares no CI.
Read that from the default branch's `.no-mistakes.yaml` (`git show origin/<default branch>:.no-mistakes.yaml`), because the pipeline honors `no_ci: true` only from that copy; never decide it from your branch's copy or from the project's name.
- With CI (no `no_ci: true`): the return point is /no-mistakes reporting CI green (the CI-ready return point - do not wait for it to keep monitoring in the background until merge).
- With no CI (`no_ci: true`): no check runs, so do not wait for the drive call to report CI green, which can arrive hours later.
  The return point is the ci step's log (`no-mistakes axi logs --step ci`) showing that the repository declares no CI and is treating that as all checks passed, which the ci step logs at its first poll; read that log while the drive call runs in the background.
At the return point, read the PR back from the forge and confirm it is not a draft (`gh-axi pr view <number> --repo <owner>/<repo>` must print `draft: no`, where <number> and <owner>/<repo> come from your PR URL, because a bare number can resolve to a different repository); if it is a draft, mark it ready with `gh-axi pr ready <number> --repo <owner>/<repo>`.
A draft cannot be merged, so a done report on one leaves the merge unasked.
Then append the one ready line that names the real evidence, and stop. You are finished.
- With CI: `done [at=<epoch>]: PR {url} checks green: {name of each check that ran}; read changed files: {yes|no|unknown}`.
  Write `yes` only when at least one of those checks reads a file this PR changes, `no` when none does (a change to one markdown file under only typecheck and workflow lint is `no`), and `unknown` when you cannot tell from the check definitions and logs.
- With no CI: `done [at=<epoch>]: PR {url} no CI: test step {n}/{m} scenarios live; untested: {each scenario the test step could not drive, or none}`, taken from the pipeline test step's evidence (`no-mistakes axi logs --step test`).
  Name every untested scenario, especially one that is the premise of the change.
If you hold back any part of the ready claim - a review, check, or verification still required on this final head, or anything else the merge authority must know before merging - end that ready line with `; held: {one line}`; never leave that disclosure only in a PR comment or description, where the merge authority does not read it.
Keep the whole ready line on one line, with the URL as the first word after `PR` and one space after it.
That CI-ready `done:` is accepted only when this copy's HEAD - your latest commit - is one the /no-mistakes run pushed, so commit nothing after the run; the check tests that commit, not merely that a branch moved.
If you deliberately keep the PR a draft, append `paused [at=<epoch>]: {why the draft is held}` instead of done.
Before adding a helper, search for an existing one and name the one you reused, or the search that found none, as answer (d) of your landing note.
Before the `done:` line that finishes this task - the ready report - write `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.CpqNHB/data/pr-other/landing-note.md` with four short answers:
- (a) what this change made harder to change next;
- (b) the one structure-only tidy you would do next, under about one hour and with no behaviour change, naming its files, or `none`;
- (c) one fact you needed that this brief or the project's `AGENTS.md` did not give you, or `none`.
- (d) the existing helper you reused, or the search that found none.
That note is task material outside your worktree: never commit it.
When this task fixes a bug, first add a test that reproduces the bug and fails, and commit it on its own before any fix; then fix the code, not the test.
   Never edit, weaken, skip, or delete that test to make it pass; if the test itself turns out to be wrong, append `blocked [at=<epoch>]: {why the bug test is wrong}` and stop instead of changing it.

Delivery: this task is finished only when the /no-mistakes run you start has opened a PR; run /no-mistakes yourself as soon as your implementation is committed, because a `done:` line without that PR's https:// URL is refused.
