# Backlog

## In flight
## Queued
- [ ] ha-72-author-note-rollup - Author note: rollup physical-test simplification (kind: docs) (since 2026-09-26) (hold: declined simplification finding left as author call from ha-72-retro-s1) (hold-kind: captain)
  Captain hold set: 2026-09-26T01:24:07Z

  Finding: rollup physical-test propagation component (see rollup.py:42) looks removable.
  Why declined: author call; a Fix would expand the contract (DO NOT CHANGE).
  Suggested change: drop propagate_physical(x) and its test.
- [ ] ha-99-author-note-rollup - Author note: rollup physical-test propagation simplification (repo: ha-climate) (kind: docs) (since 2026-09-26)
  Author note from ha-99-rollup-s1 (declined ask-user simplification finding, ha-climate).

  Finding: the rollup physical-test propagation component in rollup.py could be removed; the task's instructions never asked for it.
  Why declined: removing it changes the rollup contract, and the accepted task scope does not authorize a rollup contract change, so the ship keeps the component as is and leaves removal to the author.
  Suggested change: if the author decides the propagation is unwanted, remove the physical-test propagation component from rollup.py together with its tests, and update any rollup contract documentation and callers that rely on propagated physical-test results, as its own deliberate contract change.
  Related: ha-72-author-note-rollup records an earlier note on the same component from ha-72-retro-s1.

## Done
