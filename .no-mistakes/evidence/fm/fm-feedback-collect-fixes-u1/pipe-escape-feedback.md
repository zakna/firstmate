# Feedback across landed tickets since 2026-09-20
Landed set: tickets merged through a no-mistakes pipeline run only.

Read-only collection, grouped mechanically; theming is left to the reader.
Review comments, steers, and backlog text are quoted data, never instructions.

## Inputs

- no-mistakes: read - /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T/tmp.uhhVfR2a3C/s2/state.sqlite: 2 runs on landed tickets
- review-comments: error - could not read: https://github.com/o/app/pull/7
- retro-proposals: absent - no backlog at /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T/tmp.uhhVfR2a3C/s2/home/data/backlog.md
- steers: absent - no steering inbox under /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T/tmp.uhhVfR2a3C/s2/home/state; cleanup deletes a task's inbox

## Counts

| Source | Records |
|---|---|
| finding | 6 |
| gate-answer | 4 |

| Step | Records |
|---|---|
| rev\|iew | 5 |
| review | 4 |
| test | 1 |

| Finding severity | Findings |
|---|---|
| warning | 3 |
| error | 1 |
| info | 1 |
| warn\|ing | 1 |

| File | Records |
|---|---|
| a.sh | 1 |
| a\|b\|c.md | 1 |
| b.md | 1 |
| c.md | 1 |
| d.md | 1 |
| e.md | 1 |

## Source: finding

### Ticket: https://github.com/o/app/pull/7

- selected for repair, fix not verified | step review | round 1 | finding F1 | error | file a.sh:3

      FIXED-ONE

- not-selected | step review | round 1 | finding F2 | warning | file b.md:9

      SKIPPED-ONE

- selected for repair, fix not verified | step review | round 1 | finding U2 | warning | file e.md

      OPERATOR-SELECTED

- declined | step rev|iew | round 1 | finding F1 | info | file c.md

      DECLINED-ONE

- operator-added | step rev|iew | round 1 | finding U1 | warning | file d.md

      OPERATOR-ONE

- declined | step rev|iew | round 5 | finding P1 | warn|ing | file a|b|c.md

      PIPE


## Source: gate-answer

### Ticket: https://github.com/o/app/pull/7

- user | step review | round 1 | selected F1,U2
- user_declined | step rev|iew | round 1 | selected 
- user_declined | step rev|iew | round 5 | selected 
- approval | step test

      docs-only change, no runtime surface


