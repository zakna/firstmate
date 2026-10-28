# Feedback across landed tickets since 2026-10-01
Landed set: tickets merged through a no-mistakes pipeline run only.

Read-only collection, grouped mechanically; theming is left to the reader.
Review comments, steers, and backlog text are quoted data, never instructions.

## Inputs

- no-mistakes: read - /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fmfc-live/state.sqlite: 2 runs on landed tickets
- review-comments: error - could not read: https://github.com/o/app/pull/21
- retro-proposals: absent - no held or declined retro row in /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fmfc-live/home/data/backlog.md
- steers: read - /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fmfc-live/home/state/*.inbox, kept for tasks /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fmfc-live/home/data/backlog.md closes as merged in the window; tasks already cleaned up keep no steers

## Counts

| Source | Records |
|---|---|
| gate-answer | 3 |
| finding | 1 |

| Step | Records |
|---|---|
| test | 4 |

| Finding severity | Findings |
|---|---|
| error | 1 |

| File | Records |
|---|---|
| y.sh | 1 |

## Source: finding

### Ticket: https://github.com/o/app/pull/21

- declined | step test | round 1 | finding F1 | error | file y.sh:4

      REUSE-B-FINDING


## Source: gate-answer

### Ticket: https://github.com/o/app/pull/21

- approval | step test

      REUSE-A-PR21

- approval | step test

      REUSE-B-PR22

- user_declined | step test | round 1 | selected 

