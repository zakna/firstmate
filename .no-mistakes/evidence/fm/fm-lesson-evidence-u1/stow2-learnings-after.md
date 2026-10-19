# Learnings
<!-- memory tiers: see the stow skill -->

- Never restart the shared no-mistakes daemon while runs are active. <!--P-->
- Codex writes its trust prompt to stderr, not stdout. <!--a:2026-10-10-->
- When two Herdr resume spawns can run concurrently (as in CI), the second refuses on session-lock contention unless `--herdr-resume-lock-wait` is passed to `bin/fm-spawn.sh` (header owns details). [ev: fm-spawn.sh header read; CI failed on two separate PRs from this; h] <!--a:2026-10-19-->
- Treehouse get prints the slot path on its last stdout line. <!--a:2026-10-19-->
- Lavish sessions survive a daemon restart. <!--g-->
