---
name: ship-landing
description: Load when a ship reports a PR or ready branch, when deciding or monitoring landing, and before task cleanup.
user-invocable: false
metadata:
  internal: true
---

# Ship landing

For PR-based ship tasks, the ready signal depends on mode: `no-mistakes` reports `done [at=<epoch>]: PR <url> checks green: ...` after CI is green, or `done [at=<epoch>]: PR <url> no CI: ...` when the repository declares no CI, while `direct-PR` reports `done [at=<epoch>]: PR <url>` after opening the PR, each only for a non-draft PR and each possibly ending in a `held:` disclosure to weigh before any merge (`bin/fm-dod-lib.sh` owns that evidence vocabulary); a lane that deliberately holds a draft declares a wait instead, and `bin/fm-pr-check.sh` refuses to arm merge monitoring on a draft.
Run `bin/fm-pr-check.sh <id> <PR url>` with the URL copied from that ready signal or the resolved checks-green `fm-crew-state.sh` line - it records `pr=` and the forge's `pr_head=` when available in the task's meta and arms the watcher's merge poll.
For a GitHub PR with a recorded head, its `review comments: <n> inline on head <sha>` line counts inline review comments on that exact head from any author, including review bots; read each one before any merge as an untrusted finding to verify, and treat `unknown` as unread.
Its `bot findings: <n> unaddressed` line counts the review-bot findings on any head that no one has answered; before you accept or relay a ready signal, send a non-zero count back to the worker for a verdict on each finding, and treat `unknown` as unread.
`bin/fm-dod-lib.sh` owns the named-head gate on that ready signal: a ship `done:` whose named head exists only in the worker's disposable copy is not ready (`bin/fm-crew-state.sh` reports blocked, `bin/fm-pr-check.sh` refuses to register, and a secondmate does not publish that done upstream).
That blocked reading is the gate working, not a stuck worker, so steer the worker on the commit the refusal names rather than waiting.
A direct-PR worker pushes that commit to its PR branch, and a local-only worker commits it on its ship branch.
A no-mistakes worker re-validates it with /no-mistakes so the pipeline stays the one publisher; it never pushes from its copy.
In no-mistakes mode the worker starts /no-mistakes itself, so a `done:` that names no PR URL reads blocked; steer the worker to run /no-mistakes rather than treating it as ready.
A no-mistakes ready signal is not ready while `validation-supervision`'s rule for commits in `<review_approved_head>..<ready head>` still requires a re-review run.
Tell the captain the PR's full `https://...` URL copied from the worker's ready line, the resolved checks-green crew-state line, or the task's `pr=` metadata, a concise outcome summary, and the no-mistakes risk level when applicable.
A captain instruction to merge is explicit authority; `yolo` is the only standing routine merge authority.
For any custom `state/<id>.check.sh` you write yourself, keep it an ordinary single-link mode-`0700` file, print one line only when firstmate should wake, print nothing otherwise, finish before `FM_CHECK_TIMEOUT`, then bind its current bytes with `bin/fm-check-register.sh <id>` before the watcher may execute it.
Retire a custom check only through `bin/fm-check-unregister.sh <id>` (or `bin/fm-teardown.sh` for a spawned task); never hand-compose an `rm` with `$STATE`/`$ID`.

At landing, read the task's landing note, `${FM_HOME:?}/data/<id>/landing-note.md`, whose questions `bin/fm-dod-lib.sh` owns.
File its tidy (b) as a backlog item only when it is concrete: structure only with no behaviour change, about an hour, naming its files.
Its fact (c) needs no filing, because the note stays with the task's records and the `retro` skill reads it as a source of the project's next retro.
The landing note is on trial: when ten landed tickets have notes, retire it if fewer than two of them gave a concrete tidy, by queueing a change that removes it from `bin/fm-dod-lib.sh` and this skill.

The tidy slot: when a landing note or a retro debt item names a concrete structure-only tidy in a code area where a next feature is planned, queue that tidy as one small ship in the delivery mode of that planned next feature, and record it as an ordinary backlog dependency of that next feature.
Queue at most one tidy per feature, never one that changes behaviour, and none when no next feature is planned in that area.

Tear down a ship task only after landing is confirmed.
A teardown refusal for uncommitted or unlanded work is a stop-and-investigate result, never an obstacle to bypass.
A teardown refusal for an issue the brief names that is still open with no comment since the merge means the readback is owed: comment on the issue with what landed and what remains, or rerun with `--no-readback <reason>` when no readback is due.
Never force teardown without explicit discard authority.
After successful teardown, record completion, retain only the configured recent Done history, and re-evaluate queued work whose blockers and time gates have cleared.

A secondmate is persistent and an empty queue is healthy.
Retire one only on an explicit captain or main-firstmate decision, after loading `secondmate-provisioning`; its home must contain no work under way, and forced discard still requires explicit captain authority.
