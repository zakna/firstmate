#!/usr/bin/env bash
# Usage: herdr-sigpipe-probe.sh <checkout-root>. Sources the real herdr backend with SIGPIPE ignored
# and drives the four first-match readers against producers that keep writing after the first match.
R=$1
bash -c '
trap "" PIPE
. "$0/bin/backends/herdr.sh"
big_tabs() { printf "{\"result\":{\"tabs\":["; for i in $(seq 1 20000); do printf "{\"label\":\"w\",\"tab_id\":\"t%s\",\"workspace_id\":\"ws%s\"}," $i $i; done; printf "{\"label\":\"x\",\"tab_id\":\"z\",\"workspace_id\":\"z\"}]}}"; }
big_panes() { printf "{\"result\":{\"panes\":["; for i in $(seq 1 20000); do printf "{\"tab_id\":\"t1\",\"pane_id\":\"p%s\"}," $i; done; printf "{\"tab_id\":\"q\",\"pane_id\":\"q\"}]}}"; }
fm_backend_herdr_workspace_find_all() { printf "%s\n" w1; sleep 0.3; printf "%s\n" w2; }
echo "workspace_find -> [$(fm_backend_herdr_workspace_find fmtest)]"
fm_backend_herdr_cli() { case "$2 $3" in "pane list") big_panes;; "tab list") big_tabs;; esac; }
echo "pane_for_tab -> [$(fm_backend_herdr_pane_for_tab s ws1 t1)]"
echo "pane_for_tab(no match) -> [$(fm_backend_herdr_pane_for_tab s ws1 none)] rc=$?"
herdr() { printf "{\"sessions\":["; for i in $(seq 1 20000); do printf "{\"name\":\"s\",\"socket_path\":\"/sock%s\"}," $i; done; printf "{\"name\":\"y\"}]}"; }
echo "socket_path -> [$(fm_backend_herdr_socket_path s)]"
echo "socket_path(no match) -> [$(fm_backend_herdr_socket_path nope)]"
sleep 0.5
' "$R"
