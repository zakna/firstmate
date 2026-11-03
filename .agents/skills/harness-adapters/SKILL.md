---
name: harness-adapters
description: >-
  Load before spawning or recovering a crewmate or secondmate, choosing a runtime backend, handling a trust dialog, sending a harness-specific skill invocation, steering a worker, answering or resending a steer, interrupting or exiting an agent, resuming an exited agent, or verifying a new harness adapter.
  Contains verified facts for claude, codex, opencode, pi, pi-signed, grok, kimi, cursor, gemini, muse, rovo, omp, agy, devin, and the opt-in pi-durable pilot, plus Command Code, Polytoken, Cortex, and Kiro.
user-invocable: false
metadata:
  internal: true
---

# harness-adapters

This is the one skill, trigger, and routing owner for harness-specific Firstmate operations.
Load this router first, then exactly the common reference and one harness reference selected below.
When an action spans rows, load the union once rather than every reference.
Files under `references/` are resources of this skill, not additional catalogued skills.

## Path contract

The skill directory is the directory containing this `SKILL.md`.
Resolve on-demand reference links and relative links to their executable, documentation, or sibling-skill owners against the skill directory, including links named by a nested reference.
Operational paths keep the context named by their owner: `config/` and active-home settings belong to the active Firstmate home, `state/` belongs to that home, and project settings such as `.claude/settings.json` belong to the target project.

## Non-negotiable safety

Never dispatch a crewmate or secondmate on an unverified adapter.
If `config/crew-harness` or `config/secondmate-harness` names one, tell the captain under `../../../AGENTS.md` section 9 that the requested worker runtime is not verified, use firstmate's own verified runtime for current work, and ask only whether to verify the requested runtime for future work.
Do not pause current work for that choice.

On `unknown`, ask the captain instead of guessing.
A current captain override beats detection, while a per-task override governs only that dispatch.
For recovery and control, use the exact `harness=` in `state/<id>.meta`; never infer it from a model or provider.

For a local task, deliver lifecycle actions only through `../../../bin/fm-control.sh <task-id> interrupt|exit|relaunch`.
A remotely placed secondmate is refused by local `fm-control.sh`: use `../../../bin/fm-remote-secondmate-relaunch.sh` for relaunch and the `secondmate-provisioning` remote-liveness recovery path; remote interrupt and exit have no local route.
Never type an interrupt key or exit command through `fm-send`, where routing-marked lifecycle text becomes chat.
Trust handling is complete only when inspection proves the target started processing its instructions; delivery success alone is not proof.
Muse, Gemini, Devin, Command Code, Polytoken, Cortex, Kiro, and the pi-durable pilot are verified only for crewmate and scout work, never a secondmate or primary.

## Detection

`../../../bin/fm-harness.sh` prints firstmate's own harness from verified environment markers and process ancestry, and owns how they combine.
A marker names its harness, but a structural ancestor of a different harness outranks it, because a marker is ordinary environment state a child or a multiplexer can retain while ancestry is what proves who owns the process tree.
Only `FM_PI_HARNESS=pi-signed` at the launch boundary together with `PI_CODING_AGENT=true` selects Pi-signed; shared unmarked launcher ancestry remains Pi.
omp publishes no marker of its own; `FM_OMP_HARNESS=omp` is Firstmate's launch marker and the anchored process name `omp` is its ancestry evidence, as `references/harness/omp.md` records.
`../../../bin/fm-spawn.sh` owns worker marker establishment, while the README launch command owns the signed-primary boundary.
`../../../bin/fm-harness.sh crew` resolves `config/crew-harness`, where absent or `default` means firstmate's own harness.
[`docs/configuration.md`](../../../docs/configuration.md#choose-the-secondmate-harness) owns secondmate pin resolution, including per-mate overrides; [`bin/fm-harness.sh`](../../../bin/fm-harness.sh) owns the resolver commands.
`../../../bin/fm-spawn.sh` re-resolves on every spawn, and an explicit per-spawn argument wins for that spawn.
A new adapter's verified marker and command name must land in `../../../bin/fm-harness.sh`.

## Runtime backend

`../../../docs/configuration.md` owns runtime-backend schemas, and `../../../bin/fm-spawn.sh` owns launch flags and fail-closed validation.
Dispatch only on a backend that `fm-spawn` validates as spawn-capable; pass an explicit per-spawn `--backend` only under that exact task's own authority, never as later-task precedent (selection contract: [`../../../docs/configuration.md`](../../../docs/configuration.md) "Runtime backend").
A missing dependency, authentication failure, unsupported backend, or version refusal is a blocker; never silently retry on another backend.
`../secondmate-provisioning/SKILL.md` owns secondmate harness pins and inherited local material; this router owns the runtime consequences.

## Steering and lifecycle

Steer ordinary text addressed to a task selector through fail-closed `../../../bin/fm-send.sh`: the message becomes a durable record in the task's steering inbox (multi-line text is legal, local and remote alike) and the worker's terminal receives only a constant doorbell line, with the watcher re-ringing an unacknowledged local message and escalating a stuck one (`../../../bin/fm-task-inbox-lib.sh`; `../../../bin/fm-send.sh` owns the typed-plane carve-outs).
For a local crewmate or scout task selector, a harness-native invocation (leading `/`, or leading `$` to a Codex target) is the typed exception and reaches the local harness parser; a local secondmate parser-native request is marked before submission and arrives as marker-prefixed chat rather than a parser command.
An explicit backend target is also typed because it names an endpoint rather than a task.
A remote secondmate has no typed text plane, so its text steers remain inbox records; only `--key` crosses to its remote pane as a keystroke.
For a reply-bearing remote secondmate steer after an unconfirmed delivery, only the exact `FM_PENDING_REPLY_EXISTING_CORR=<id>` resend command printed by `fm-send` is safe because it preserves the request body for remote enqueue deduplication.
A remote `--fire-and-forget <delivery-id>` steer creates no pending-reply expectation; retry it only with the same caller-supplied delivery id (`../../../bin/fm-send.sh` header).
When a steer answers an open keyed decision or blocker, pass `fm-send`'s `--resolve-key` so the answer itself closes that decision record at answer time, identically for local and remote workers (contract: `../../../bin/fm-send.sh` header).
`fm-control.sh` owns the per-runtime lifecycle mechanics, verifies each action, and never tears down or discards anything ([`../../../docs/agent-control.md`](../../../docs/agent-control.md)).
A secondmate's routed reply returns through status or a document pointer, not by firstmate peeking into its chat.
For the parent-owned correlation, recovery, and escalation contract on marked secondmate requests, see `../../../bin/fm-pending-reply-lib.sh`.
When the captain adds or changes an ask mid-task, append the captain's words to a ship or scout brief's `## Captain's intent` and relay those words to the worker; on a secondmate, charter authoring or updates follow `secondmate-provisioning` instead of these task sections.
For ship or scout work, Firstmate build constraints stay in `## Firstmate spec` or the steer.

## Operation-to-reference matrix

Every emitted plan appends the selected or recorded harness reference after the named common references.
The `harness-adapter-routing-v1` object is the machine-readable and human-visible selection contract: choose the operation, choose the scenario within it, then append the selected harness reference.
`default` is the normal scenario when no narrower scenario applies.
Kimi establishes its unsupported primary boundary in its selected harness reference; Muse and Gemini follow Non-negotiable safety above.
A new tool remains undispatchable until the `verify` plan, its harness entry, every named owner, and the live checks land.

```json harness-adapter-routing-v1
{
  "operations": {
    "start": {
      "default": ["references/common/dispatch.md", "references/common/model-and-effort.md"],
      "trust-dialog": ["references/common/control-and-recovery.md"]
    },
    "trust": {"default": ["references/common/control-and-recovery.md"]},
    "skill": {"default": ["references/common/control-and-recovery.md"]},
    "interrupt": {"default": ["references/common/control-and-recovery.md"]},
    "exit": {"default": ["references/common/control-and-recovery.md"]},
    "resume": {"default": ["references/common/control-and-recovery.md"]},
    "recovery": {
      "default": ["references/common/control-and-recovery.md"],
      "replacement-profile": ["references/common/control-and-recovery.md", "references/common/dispatch.md", "references/common/model-and-effort.md"],
      "secondmate": ["references/common/control-and-recovery.md", "references/common/primary-hooks.md"],
      "replacement-secondmate": ["references/common/control-and-recovery.md", "references/common/dispatch.md", "references/common/model-and-effort.md", "references/common/primary-hooks.md"]
    },
    "primary": {"default": ["references/common/primary-hooks.md"]},
    "model-effort": {
      "default": ["references/common/model-and-effort.md"],
      "configured-profile": ["references/common/model-and-effort.md", "references/common/dispatch.md"]
    },
    "verify": {"default": ["references/common/dispatch.md", "references/common/control-and-recovery.md", "references/common/primary-hooks.md", "references/common/model-and-effort.md"]}
  },
  "harnesses": {
    "claude": "references/harness/claude.md",
    "codex": "references/harness/codex.md",
    "opencode": "references/harness/opencode.md",
    "pi": "references/harness/pi.md",
    "pi-signed": "references/harness/pi.md",
    "grok": "references/harness/grok.md",
    "kimi": "references/harness/kimi.md",
    "cursor": "references/harness/cursor.md",
    "gemini": "references/harness/gemini.md",
    "muse": "references/harness/muse.md",
    "rovo": "references/harness/rovo.md",
    "omp": "references/harness/omp.md",
    "agy": "references/harness/agy.md",
    "devin": "references/harness/devin.md",
    "pi-durable": "references/harness/pi-durable.md",
    "commandcode": "references/harness/commandcode.md",
    "polytoken": "references/harness/polytoken.md",
    "cortex": "references/harness/cortex.md",
    "kiro": "references/harness/kiro.md"
  }
}
```
