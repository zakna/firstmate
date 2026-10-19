# Learnings
<!-- memory tiers: see the stow skill -->

- When running bin/fm-fleet-ledger.sh, jq must be on PATH: every ledger event is built with `jq -cn` and the script never checks for jq first, so each append fails without it. [ev: read append() in source; h] <!--a:2026-10-19-->
- Herdr lab sessions must use an fm-lab-* name. <!--a:2026-10-19-->
