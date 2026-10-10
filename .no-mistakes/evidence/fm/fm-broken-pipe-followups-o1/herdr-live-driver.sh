#!/usr/bin/env bash
# Calls the changed herdr resolvers against a live fm-lab-* Herdr session with
# SIGPIPE ignored. `herdr session list` is narrowed to the lab session so the
# bare-selector scan never reaches the operator's default session.
# Usage: herdr-live-driver.sh <repo-root> <lab-session>
trap '' PIPE
R=$1 S=$2 REAL=$(command -v herdr)
herdr() {
  if [ "$1" = session ] && [ "$2" = list ]; then
    "$REAL" session list --json --session "$S" | jq -c --arg s "$S" '.sessions |= map(select(.name == $s))'
  else "$REAL" "$@"; fi
}
. "$R/bin/backends/herdr.sh"
echo "pane_for_tab w1:t2 -> $(fm_backend_herdr_pane_for_tab "$S" w1 w1:t2); rc=$?"
echo "pane_for_tab w1:t9 (absent) -> [$(fm_backend_herdr_pane_for_tab "$S" w1 w1:t9)]"
echo "resolve_bare_selector fm-dup -> $(fm_backend_herdr_resolve_bare_selector fm-dup)"
echo "resolve_bare_selector fm-none -> [$(fm_backend_herdr_resolve_bare_selector fm-none 2>&1)]"
echo "socket_path $S -> $(fm_backend_herdr_socket_path "$S")"
echo "socket_path fm-lab-absent -> [$(fm_backend_herdr_socket_path fm-lab-absent)]"
