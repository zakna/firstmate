# Existing building blocks
Before writing a new helper, search `bin/` and `docs/scripts.md` for one that already does the job, and reuse it.
These shared libraries already own their contract:
- `fm-brief-heading-lib.sh` - reading a brief's sections, shared by the `--intent` contract, spawn and promotion validation, and `fm-dispatch-resolve.sh`
- `fm-gate-delegation-lib.sh` - the wording spawn, promotion, and task-worker steers warn on when it hands the worker its own ask-user gate responses
- `fm-composer-lib.sh` - composer shapes, capability-aware screen classification, and verdicts
- `fm-task-inbox-lib.sh` - durable steering-inbox records, acknowledgement, doorbells, and the delivery-attempt ladder
- `fm-nm-run-lib.sh` - shared no-mistakes run-attribution primitives and rules
- `fm-timeout-lib.sh` - hard-bounded command execution and its fallback watchdog
- `fm-timing-lib.sh` - the deferred network stage's per-step elapsed-time records, inert unless a run asks for them
- `fm-lease-lib.sh` - the supervision lease contract and the main-only role-partition guards
- `fm-control-lib.sh` - the control-plane verb allowlist, per-harness interrupt/exit mechanics, per-backend capability, and the endpoint-absence proof both `exit` and `relaunch` read
- `fm-busy-lib.sh` - the semantic busy-state contract: verdicts, source attribution, and per-harness sources
