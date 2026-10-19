# Learnings
<!-- memory tiers: see the stow skill -->

- When running bin/fm-fleet-ledger.sh, jq must be on PATH: every ledger event is built with `jq -cn` and the script never checks for jq first, so each append fails without it. [ev: read append() in source; h] <!--a:2026-10-19-->
- Herdr lab sessions must use an fm-lab-* name. <!--a:2026-10-19-->
- When locating the "primary" tmux session in this lab home, it lives on the lab server (`TMUX_TMPDIR="$FM_HOME/tmux" tmux -L fm-lab`); plain `tmux ls` shows it only because the shell's inherited $TMUX points at that socket, and the default server has none. [ev: socket_path of primary was the fm-lab socket; `env -u TMUX -u TMUX_TMPDIR tmux ls` found no default server; m] <!--a:2026-10-19-->
