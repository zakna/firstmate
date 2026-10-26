# pi-durable pilot

`pi-durable` is an opt-in, one-worker pilot runtime: a Firstmate-owned Node host that runs one task on the experimental `@earendil-works/pi-durable` library.
It is not the Pi CLI and not a variant of the `pi` or `pi-signed` adapters, which, like default dispatch, stay unchanged; nothing selects it unless a home names it.
The router owns the crewmate/scout-only boundary; primary and secondmate integration is unsupported.
[Runtime verification](../../../../../docs/verification/runtime-backends.md#pi-durable-pilot) and its live guard refresh the facts below.

## Operating facts

| Fact | Value |
|---|---|
| Install | Per home: `../../../../../bin/fm-pi-durable.sh install` puts the exact tree pinned by `bin/pi-durable/package-lock.json` under `state/pi-durable-runtime/`; the spawn refuses until `fm-pi-durable.sh check` passes. Node must be at least the package floor the script enforces. |
| Busy state | The host's own event stream: `run_start` opens and `run_end` closes through the generation-bound writer under source `pi-durable-host`; a reopened store with nothing left to run and no newly admitted input settles idle at once. `turn_end` touches the turn-end notification. |
| Exit command | `/quit`; Ctrl-D on an empty row also exits. |
| Interrupt | Single Escape; it aborts the current run, kills its running tool, and withdraws queued inputs. The host renders `interrupted` and settles idle. |
| Skill invocation | None; the host has no slash commands other than `/quit`, so use natural language. |
| Resume | No resume flag: the task's store is `state/<id>.pi-durable/`, and every launch, including `fm-control.sh relaunch`, reopens it and continues any unfinished run. |
| Model flag | `--model <provider>/<id>`, required, naming an `openai-completions` provider declared in `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/models.json`; that provider's and model's `compat` flags are applied. OAuth providers are refused: the pilot has no credential bridge. |
| Effort flag | None; thinking levels are not translated, so Firstmate records the effort axis without passing it and the host refuses `--thinking`. |
| Model discovery | The providers and models in that `models.json`. |
| Marker | None; the host runs as Node with argv[0] `pi-durable` (macOS reports it as the process name, Linux as argv[0]), which liveness and ancestry recognize. |
| Trust dialogs | None. |
| Account pin | Not applied; `config/pi-account` governs only `pi` and `pi-signed`. |

## Recovery and side effects

The per-task SQLite store is the one recovery authority for the conversation; Firstmate's task record keeps the endpoint and status authority, and no Pi session file is involved.
On an empty store the launch brief starts the task under a request id derived from its text.
Once the store holds that launch brief, a relaunch's rebuilt brief, including its predecessor recap, is admitted once per distinct text as a steering note: the worker was relaunched, the conversation and completed tool results are intact, the brief and recap are context only, and completed side effects must not be repeated.
A relaunch therefore never starts the task over.
Only `read` is replay-safe.
`bash`, `write`, and `edit` keep pi-durable's unsafe policy: a call cut off by a host crash is never executed again, and the model receives the committed interrupted result instead.
A hard kill of the host does not kill a running `bash` tool's child processes, so a command that outlives the host can still finish its own work.

## Store retention

The store holds prompts, tool arguments, and results, so it is created owner-only (directory 0700, files 0600) and the host refuses a store that is not.
It lives for the task: teardown removes it with the task's other state, while a relaunch onto another adapter, such as the rollback to `pi`, leaves it in place.

## Composer and steering

The composer is the bare row `⟫ ` plus typed text, registered as an agent glyph in `../../../../../bin/fm-composer-lib.sh`.
Enter submits the row: while a run is busy it steers that run after the current tool round, otherwise it starts a new run.
Before submitting any row, and once at every open, the host bridges the `../../../../../bin/fm-task-inbox-lib.sh` steering inbox: each unhandled message is admitted as durable input in numeric order under a request id derived from its name and bytes.
The host moves a message into `handled/` only once its submission is placed into the conversation, not at admission.
An interrupt that withdraws a queued message leaves it in the inbox, so the watcher's re-ring and escalation still apply, and the next bridge pass admits it again under a request id naming the withdrawn submission.
The doorbell line itself only triggers that bridge and never reaches the model, and a re-rung doorbell, a relaunch, or a crash before the move never admits one message twice.
The host renders no busy footer, so delivery relies on the composer verdict, not a rendered busy signal.

## Primary integration

No primary Stop guard, watcher protocol, pre-tool protection, or session-start contract exists for this host.
Do not launch a primary or secondmate with this adapter.
