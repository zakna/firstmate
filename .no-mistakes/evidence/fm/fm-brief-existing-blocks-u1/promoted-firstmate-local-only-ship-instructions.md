Your scout task has been promoted to a ship task, mode=local-only. Your window, worktree, and context stay as they are; only the contract below changes.

# Task
## Captain's intent
Ship the change.

## Firstmate spec
If these promotion steps were already completed before a relaunch, preserve the existing `fm/p-fm-https` branch and continue from its current state; do not repeat them destructively.
1. **Verify isolation before anything else.** Run `pwd -P` and `git rev-parse --show-toplevel`; both must resolve to the disposable task worktree you were launched in, such as a treehouse pool path or an Orca-managed worktree, not the primary checkout firstmate operates from. If either does not resolve to the worktree you were launched in, stop and escalate to firstmate.
2. Inventory this worktree's scratch state with `git status` and `git log` before changing anything.
3. Return to a clean default-branch base, then create your branch: `git checkout -b fm/p-fm-https --`.
4. Carry over only the intended fix changes. Leave scratch commits, debug edits, and experiment files behind.
5. If you reproduced a bug, turn that reproduction into a regression test.
6. Treat the scout-time Firstmate spec and any unmarked legacy `# Task` text as investigation context, not captain intent or current ship-time instructions.
7. Everything else in your original instructions carries over unchanged: the status protocol; the instruction inbox and its acknowledgement; the escalation rules, including ask-user; and every safety rule, except where the current delivery contract below explicitly replaces scout-only delivery rules.


# Scope allowance
However narrowly the task above states its scope, the smallest downstream changes needed to keep already accepted behavior correct, add behavioral tests where an executable contract exists, or keep documentation accurate stay within this task even in files it does not name; Firstmate's `/Users/olivier/.no-mistakes/worktrees/0b1ab7dd6182/01M571TDANJY3555G9W72KZNW1/.agents/skills/validation-supervision/SKILL.md` owns this allowance.

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
This task is now kind=ship with mode=local-only.
This section supersedes every earlier brief instruction about delivery mode.
These current ship instructions supersede the scout delivery rules and report-based Definition of done.
Any earlier "Never push" or scout-only delivery language in this file is superseded.
This replaces the scout rule limiting outside-worktree writes to the report and status file.
Keep project edits inside this worktree; keep proof and scratch output outside it, under `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.1Hatba/data/p-fm-https/` or a temporary directory.
Outside the worktree, write only that task material and the status and steering-inbox records authorized below.
Leave the worktree clean before reporting done.
The mode-specific Definition of done below is the current delivery contract.

# Current ship safety rule
1. Never push to any remote and never open a PR. Work only on your `fm/p-fm-https` branch; firstmate handles the merge into local `main`.

# Definition of done
Delivery contract: mode=local-only
Ship branch: fm/p-fm-https
This task ships **local-only**: no remote, no PR, no pipeline.
The task is complete only when committed on your branch `fm/p-fm-https`. Do NOT push, do NOT open a PR, do NOT merge.
A `done:` is accepted when the named head is on this project's shared local branch, not only on a detached copy; the check tests that head, not merely that a branch moved.
Keep your branch a clean fast-forward onto the current default branch - if `main` has advanced, rebase onto it so the eventual merge stays a fast-forward.
When it is implemented and committed, append `done [at=<epoch>]: ready in branch fm/p-fm-https` to the status file and stop.
The configured merge authority approves the ready branch, then firstmate merges it into local `main` through the guarded fast-forward path.
Before adding a helper, search for an existing one and name the one you reused, or the search that found none, as answer (d) of your landing note.
Before the `done:` line that finishes this task - the ready report - write `/var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-lab.1Hatba/data/p-fm-https/landing-note.md` with four short answers:
- (a) what this change made harder to change next;
- (b) the one structure-only tidy you would do next, under about one hour and with no behaviour change, naming its files, or `none`;
- (c) one fact you needed that this brief or the project's `AGENTS.md` did not give you, or `none`.
- (d) the existing helper you reused, or the search that found none.
That note is task material outside your worktree: never commit it.
When this task fixes a bug, first add a test that reproduces the bug and fails, and commit it on its own before any fix; then fix the code, not the test.
   Never edit, weaken, skip, or delete that test to make it pass; if the test itself turns out to be wrong, append `blocked [at=<epoch>]: {why the bug test is wrong}` and stop instead of changing it.
