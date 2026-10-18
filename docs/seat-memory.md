# Seat memory

Seat memory keeps the decisions behind a project's past work and hands them to the next worker on the same area of that project.
It also links each Claude worker's conversation to its task.
It is opt-in and off by default.

The idea comes from OpenRig's rigs and seats, with no OpenRig dependency.
A rig is a registered project.
A seat is a named, durable area of that project, such as a module or subsystem, that outlives every worker and gathers that area's decision records.
Workers stay disposable, with one worktree per task.

## Turning it on and off

Create the presence flag `config/seat-memory` in a firstmate home to turn seat memory on, and delete it to turn it off.
The flag is local, gitignored, and per home.
While it is absent, briefs, worker launches, task records, and cleanup are byte-identical to a home without the feature, and `--seat` and `--path` on `bin/fm-brief.sh` are accepted and change nothing.
Records already written stay in `data/` as history when the flag is removed.

## What it does

With the flag present:

- Every ship and scout definition of done asks the worker to write `data/<task-id>/decisions.md` before its `done:` line.
- Cleanup of a ship or scout task indexes that record under its seats in `data/seats/<project>/index.tsv`.
- Every ship and scout launch carries a `# Seat decisions` section with its seats' newest records, newest first and bounded in size, each with the path of its full record.
  - A brief scaffolded with `--seat <seat>` or `--path <path>` carries the section for exactly those seats.
  - A brief scaffolded with neither gets the section when the worker launches, from its filled `# Task` text, headings excluded: each known seat (one defined in `seats.txt` or already in the index, other than `root`) whose name appears in that text as a word, and the defined seat of each path the text names.
    These inferred seats are offered as likely areas only; they never become the task's `Task seats:` line.
  - When nothing in that text matches, the section holds the project's newest records across all seats, within the same size bound.
- A Claude ship or scout worker starts with `--session-id <uuid>`, its task record names that id as `claude_session_id=`, and the archived `data/<task-id>/meta.txt` keeps it.
  A relaunch starts a new id and keeps the earlier ones in `claude_prior_session_ids=`, and its predecessor recap reads the previous worker's own conversation by that id.
  Other worker tools accept no id chosen at launch, so their records name none.

## The decision record

The worker writes a short, structured file:

```markdown
Seats: spawn docs

## Record the session id in the task record
Reason: the recap had to guess the conversation from the worktree and a start time
Rejected: a separate session store - a second source of truth
UNVERIFIED: none
```

The `Seats:` line names the seats the brief listed (task seats or likely areas) that the work touched, and may be empty for a ship. A scout, which changes no product files, names the listed seats it investigated, else the top-level directory of each area it investigated.
Each `##` heading is one decision, followed by its reason, the options rejected, and any fact relied on but not checked.

## Where everything lives

Everything stays in the home's private `data/` tree, never in a project's `AGENTS.md` or `CLAUDE.md` and never in a second store:

| Path | Contents |
| --- | --- |
| `data/<task-id>/decisions.md` | The full record the worker wrote |
| `data/seats/<project>/index.tsv` | One line per record and seat: Unix time, seat, task id, task kind |
| `data/seats/<project>/seats.txt` | Optional seat definitions, one per line: a seat name followed by the project paths it covers |

`<project>` is the project's clone directory name.
The index points at each task's own record rather than copying it.

## How a task finds its seats

A seat name is letters, digits, dots, underscores, and dashes, starting with a letter or digit.
A path belongs to the seat whose defined path in `seats.txt` is its longest match, else to its top-level directory, else to `root` for a top-level file.

At cleanup, a record's seats are its `Seats:` line, else the brief's `Task seats:` line from `--seat` or `--path`, together with, for a ship, the seats of the files its branch changed.
A scout's scratch changes are not its product, so a scout without either line is not indexed.

`bin/fm-seat-lib.sh`'s header owns the exact matching rules, feed bounds and their environment overrides, and file formats.

## Limits

A record exists only when the worker writes it; nothing captures the reasoning on its own.
There is no command to search past records or to ask a finished worker a question, and no messaging lane between workers.
