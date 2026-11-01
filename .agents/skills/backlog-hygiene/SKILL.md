---
name: backlog-hygiene
description: Load before writing, replacing, or archiving a backlog item note, or before any backlog command beyond add and hold.
user-invocable: false
metadata:
  internal: true
---

# Backlog schema and note hygiene

Moved from AGENTS.md section 10 "Backlog contract".

`.tasks.toml`, `docs/configuration.md`, and current `tasks-axi --help` own the backlog schema, compatibility, retention, and routine command syntax.
Use compatible `tasks-axi` when the configured backend selects it, always through `bin/fm-tasks-axi.sh` so the call reaches this home's backlog from any directory, and the documented manual path otherwise; keep only the configured recent Done entries.
`secondmate-provisioning` and `bin/fm-backlog-handoff.sh` own cross-home handoff safety.

Keep free-form notes free of temporary paths, moving versions, ephemeral identifiers, and copied state that will rot.
Inspect the current task note before replacing its considered body, and archive the superseded body when recoverability matters rather than appending by default.
Verify volatile details against their authoritative config, live system, or API before acting, and correct or delete stale prose immediately.
Preserve durable structured identifiers, dependencies, and completion artifact links, and route reusable knowledge to section 6 rather than scattering it through task notes.
