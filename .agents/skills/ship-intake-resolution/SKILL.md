---
name: ship-intake-resolution
description: Load at every ship or scout intake and scout promotion, before writing or promoting instructions, to resolve the applicable delivery posture, branch/base branch, and concurrency for that task.
user-invocable: false
metadata:
  internal: true
---

# Ship intake resolution

Moved from AGENTS.md section 7 "Intake and authority".

## Delivery mode, yolo, and branches

Resolve every ship task's concrete delivery mode and `yolo` merge posture at ship intake.
Pass the mode explicitly to a ship brief, and pass both values explicitly to a ship spawn; each command refuses to guess the values it consumes.
A scout intake omits mode, `yolo`, and branch prefix because its report has no merge contract or branch; resolve only an optional base branch there.
A scout promotion is a new ship intake: re-resolve mode, `yolo`, and the project's registered branch prefix, then pass all three explicitly to `bin/fm-promote.sh` rather than relying on its `fm/` default.
A current explicit captain instruction wins; otherwise the project's registry entry is the captain's standing posture, and dropping below its rigor needs a reason you can state.
Resolve the project's registered ship-branch prefix the same way, via `bin/fm-project-mode.sh --branch-prefix <project>`, and pass it explicitly to a ship brief and spawn as `--branch-prefix` (default `fm/` needs no flag); a scout intake omits it because it makes no branch.
When the work must start from and target a branch other than the project's default, such as a named feature or release branch, pass it to a ship brief and spawn as `--base-branch <branch>` only when the ship is `no-mistakes` or `direct-PR` with `forge=none`; a scout may carry an optional base only when its eventual promotion can retain that compatible delivery, and promotion reads it from task meta and revalidates it.
Decide that at scout intake: a recorded base cannot be cleared at promotion, and `fm_base_branch_valid` refuses a local-only or forge-backed promotion that carries one, so the remedy is to promote to a compatible mode or re-scout without a base.
On a `no-mistakes-prod-only` project, classify the task's surface: internal-only tooling, automation, contributor or operator process, and release or submission work ships `direct-PR`, while product-facing, mixed, and uncertain work ships `no-mistakes`; never infer internal-only from file location or project name.
An unregistered project or absent registry resolves to `no-mistakes` with yolo off for a ship, and the registration gap goes to the captain.
Record the resulting mode, `yolo` merge posture, and the one-line reason for any deviation in the backlog item note for a ship or promoted scout; a scout records no delivery posture.

## Concurrency and capacity

Treat file or subsystem overlap as a risk signal rather than an automatic reason to wait, and dispatch isolated work immediately with no concurrency cap when each change can be independently implemented and validated and the selected delivery path can reconcile ordinary rebases or conflicts.
A project's declared machine capacity (`config/project-capacity`) still bounds that dispatch: a spawn beyond it exits 75 without launching, and its item stays queued rather than blocked.
Serialize only for a true semantic dependency, shared mutable external state, incompatible concurrent migration, or another concrete condition that makes independent progress or reconciliation unsafe; same-file editing alone is insufficient, and genuine blockers remain durable.
A new feature in a code area with a queued structure-only tidy waits on that tidy as an ordinary dependency; `ship-landing` owns the tidy slot.
Write the task-specific brief with `bin/fm-brief.sh` before spawning: for a ship, pass the resolved `--mode`, the registered forge explicitly as `--forge <value>` from `bin/fm-project-mode.sh --forge <project>` (including `none` when that is the result), and any resolved `--branch-prefix` or `--base-branch`; for a scout, pass `--scout` and any optional `--base-branch`.
`crewmate-brief-authoring` owns ship and scout subsections, and `secondmate-provisioning` owns charters.
