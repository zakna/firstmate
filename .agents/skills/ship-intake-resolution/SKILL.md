---
name: ship-intake-resolution
description: Load at every ship or scout intake, before writing the brief, to resolve the concrete delivery mode, yolo merge posture, branch prefix, base branch, and concurrency for that task.
user-invocable: false
metadata:
  internal: true
---

# Ship intake resolution

Moved from AGENTS.md section 7 "Intake and authority".

## Delivery mode, yolo, and branches

Resolve every ship task's concrete delivery mode and `yolo` merge posture at ship intake.
Pass the mode explicitly to a ship brief, and pass both values explicitly to a ship spawn; each command refuses to guess the values it consumes.
A scout intake omits mode and `yolo` because its report has no merge contract; resolve those values only when a scout is promoted to a ship.
A current explicit captain instruction wins; otherwise the project's registry entry is the captain's standing posture, and dropping below its rigor needs a reason you can state.
Resolve the project's registered ship-branch prefix the same way, via `bin/fm-project-mode.sh --branch-prefix <project>`, and pass it explicitly to a ship brief and spawn as `--branch-prefix` (default `fm/` needs no flag); a scout makes no branch and omits it.
When the work must start from and target a branch other than the project's default, such as a named feature or release branch, pass it to the ship or scout brief and spawn as `--base-branch <branch>`; any scout promotion reads it from task meta.
On a `no-mistakes-prod-only` project, classify the task's surface: internal-only tooling, automation, contributor or operator process, and release or submission work ships `direct-PR`, while product-facing, mixed, and uncertain work ships `no-mistakes`; never infer internal-only from file location or project name.
An unregistered project or absent registry resolves to `no-mistakes` with yolo off for a ship, and the registration gap goes to the captain.
Record the resulting mode, `yolo` merge posture, and the one-line reason for any deviation in the backlog item note for a ship; a scout records no delivery posture.

## Concurrency and capacity

Treat file or subsystem overlap as a risk signal rather than an automatic reason to wait, and dispatch isolated work immediately with no concurrency cap when each change can be independently implemented and validated and the selected delivery path can reconcile ordinary rebases or conflicts.
A project's declared machine capacity (`config/project-capacity`) still bounds that dispatch: a spawn beyond it exits 75 without launching, and its item stays queued rather than blocked.
Serialize only for a true semantic dependency, shared mutable external state, incompatible concurrent migration, or another concrete condition that makes independent progress or reconciliation unsafe; same-file editing alone is insufficient, and genuine blockers remain durable.
A new feature in a code area with a queued structure-only tidy waits on that tidy as an ordinary dependency; `ship-landing` owns the tidy slot.
Write the task-specific brief under AGENTS.md section 11 before spawning.
Fill the task subsections according to section 11.
