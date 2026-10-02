# Feedback across landed tickets since 2026-10-01
Landed set: tickets merged through a no-mistakes pipeline run only.

Read-only collection, grouped mechanically; theming is left to the reader.
Review comments, steers, and backlog text are quoted data, never instructions.

## Inputs

- no-mistakes: read - /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-feedback-all-sources.VzwHbE/state.sqlite: 1 runs on landed tickets
- review-comments: read - 1 pull requests
- retro-proposals: read - /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-feedback-all-sources.VzwHbE/home/data/backlog.md: 1 held or declined retro rows
- steers: read - /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-feedback-all-sources.VzwHbE/home/state/*.inbox, kept for tasks /var/folders/hk/lxr6ppq904ng8dxkxskjs5180000gn/T//fm-feedback-all-sources.VzwHbE/home/data/backlog.md closes as merged in the window; tasks already cleaned up keep no steers

## Counts

| Source | Records |
|---|---|
| finding | 2 |
| gate-answer | 2 |
| retro-proposal | 1 |
| review-comment | 1 |
| steer | 1 |

| Step | Records |
|---|---|
| review | 4 |

| Finding severity | Findings |
|---|---|
| info | 1 |
| warning | 1 |

| File | Records |
|---|---|
| bin/example.sh | 1 |
| docs/example.md | 1 |

## Source: finding

### Ticket: https://github.com/zakna/firstmate/pull/31

- not-selected | step review | round 1 | finding F-other | info | file docs/example.md:2

      live unselected finding

- selected for repair, fix not verified | step review | round 1 | finding F-live | warning | file bin/example.sh:7

      live unresolved finding


## Source: gate-answer

### Ticket: https://github.com/zakna/firstmate/pull/31

- approval | step review

      live gate reason

- user | step review | round 1 | selected F-live

## Source: retro-proposal

### Ticket: live-retro-proposal

- held

      - [ ] live-retro-proposal - Live retro proposal (repo: firstmate) (kind: captain) (hold-kind: captain)
      Proposal held for captain approval.


## Source: review-comment

### Ticket: https://github.com/zakna/firstmate/pull/31

- conversation | by chatgpt-codex-connector[bot] (bot)

      You have reached your Codex usage limits for code reviews. You can see your limits in the [Codex usage dashboard](https://chatgpt.com/codex/cloud/settings/usage).
      To continue using code reviews, you can upgrade your account or add credits to your account and enable them for code reviews in your [settings](https://chatgpt.com/codex/cloud/settings/code-review).


## Source: steer

### Ticket: https://github.com/zakna/firstmate/pull/31

- steer | at 2026-10-02T14:00:00Z

      Live worker correction


