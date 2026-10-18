Your scout task has been promoted to a ship task, mode=direct-PR. Your window, worktree, and context stay as they are; only the contract below changes.

# Task
## Captain's intent
Ship the change.

## Firstmate spec
If these promotion steps were already completed before a relaunch, preserve the existing `fm/live-promote-firstmate` branch and continue from its current state; do not repeat them destructively.
1. **Verify isolation before anything else.** Run `pwd -P` and `git rev-parse --show-toplevel`; both must resolve to the disposable task worktree you were launched in, such as a treehouse pool path or an Orca-managed worktree, not the primary checkout firstmate operates from. If either does not resolve to the worktree you were launched in, stop and escalate to firstmate.
2. Inventory this worktree's scratch state with `git status` and `git log` before changing anything.
3. Return to a clean default-branch base, then create your branch: `git checkout -b fm/live-promote-firstmate --`.
4. Carry over only the intended fix changes. Leave scratch commits, debug edits, and experiment files behind.
5. If you reproduced a bug, turn that reproduction into a regression test.
6. Treat the scout-time Firstmate spec and any unmarked legacy `# Task` text as investigation context, not captain intent or current ship-time instructions.
7. Everything else in your original instructions carries over unchanged: the status protocol; the instruction inbox and its acknowledgement; the escalation rules, including ask-user; and every safety rule, except where the current delivery contract below explicitly replaces scout-only delivery rules.


# Scope allowance
However narrowly the task above states its scope, the smallest downstream changes needed to keep already accepted behavior correct, add behavioral tests where an executable contract exists, or keep documentation accurate stay within this task even in files it does not name; Firstmate's `/Users/olivier/.no-mistakes/worktrees/0b1ab7dd6182/01M575EEP26Q7HZFQPZY922G3P/.agents/skills/validation-supervision/SKILL.md` owns this allowance.

# Existing building blocks
Before writing a new helper, search `bin/` and `docs/scripts.md` for one that already does the job, and reuse it.
These shared libraries already own their contract:
- `fm-brief-heading-lib.sh` - reading a brief's sections, shared by the `--intent` contract, spawn and promotion validation, and `fm-dispatch-resolve.sh`
- `fm-gate-delegation-lib.sh` - the wording spawn, promotion, and task-worker steers warn on when it hands the worker its own ask-user gate responses
- `fm-composer-lib.sh` - composer shapes, capability-aware screen classification, and verdicts
- `fm-task-inbox-lib.sh` - durable steering-inbox records, acknowledgement, doorbells, and the delivery-attempt ladder
- `fm-nm-run-lib.sh` - shared no-mistakes run-attribution primitives and rules
- `fm-timeout-lib.sh` - hard-bounded command execution and its fallback watchdog
- `fm-timing-lib.sh` - the deferred network stage's per-step elapsed-time records, inert unless a run asks for them
- `fm-lease-lib.sh` - the supervision lease contract and the main-only role-partition guards
- `fm-control-lib.sh` - the control-plane verb allowlist, per-harness interrupt/exit mechanics, per-backend capability, and the endpoint-absence proof both `exit` and `relaunch` read
- `fm-busy-lib.sh` - the semantic busy-state contract: verdicts, source attribution, and per-harness sources

# Current delivery mode contract
This task is now kind=ship with mode=direct-PR.
This section supersedes every earlier brief instruction about delivery mode.
These current ship instructions supersede the scout delivery rules and report-based Definition of done.
Any earlier "Never push" or scout-only delivery language in this file is superseded.
This replaces the scout rule limiting outside-worktree writes to the report and status file.
Keep project edits inside this worktree; keep proof and scratch output outside it, under `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.3G7Q2J/data/live-promote-firstmate/` or a temporary directory.
Outside the worktree, write only that task material and the status and steering-inbox records authorized below.
Leave the worktree clean before reporting done.
The mode-specific Definition of done below is the current delivery contract.

# Current ship safety rule
1. Never push to the default branch (push only your `fm/live-promote-firstmate` branch). Never merge a PR.

# Definition of done
Delivery contract: mode=direct-PR
Ship branch: fm/live-promote-firstmate
This task ships **direct-PR**: you raise the PR yourself, without the no-mistakes pipeline.
The task is complete only when committed on your branch.
When it is implemented and committed, push your branch and open a PR with `gh-axi` that is ready for review, not a draft.
Before you report done, read the PR back from the forge and confirm it is not a draft (`gh-axi pr view <number> --repo <owner>/<repo>` must print `draft: no`, where <number> and <owner>/<repo> come from your PR URL, because a bare number can resolve to a different repository); if it is a draft, mark it ready with `gh-axi pr ready <number> --repo <owner>/<repo>`.
A draft cannot be merged, so a done report on one leaves the merge unasked.
Then append `done [at=<epoch>]: PR {url}` to the status file and stop.
If you hold back any part of the ready claim - a review, check, or verification still required on this final head, or anything else the merge authority must know before merging - end that ready line with ` held: {one line}`; never leave that disclosure only in a PR comment or description, where the merge authority does not read it.
Keep the whole ready line on one line, with the URL as the first word after `PR` and one space after it.
That `done:` is accepted only when this copy's HEAD - your latest commit - is pushed to your PR branch; the check tests that commit, not merely that a branch moved.
If you deliberately keep the PR a draft, append `paused [at=<epoch>]: {why the draft is held}` instead of done.
Do NOT run /no-mistakes. The configured merge authority decides whether to merge the PR; firstmate relays the outcome.
Before adding a helper, search for an existing one and name the one you reused, or the search that found none, in the PR description.
Before the `done:` line that finishes this task - the ready report - write `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.3G7Q2J/data/live-promote-firstmate/landing-note.md` with three short answers:
- (a) what this change made harder to change next;
- (b) the one structure-only tidy you would do next, under about one hour and with no behaviour change, naming its files, or `none`;
- (c) one fact you needed that this brief or the project's `AGENTS.md` did not give you, or `none`.
That note is task material outside your worktree: never commit it.
When this task fixes a bug, first add a test that reproduces the bug and fails, and commit it on its own before any fix; then fix the code, not the test.
   Never edit, weaken, skip, or delete that test to make it pass; if the test itself turns out to be wrong, append `blocked [at=<epoch>]: {why the bug test is wrong}` and stop instead of changing it.
