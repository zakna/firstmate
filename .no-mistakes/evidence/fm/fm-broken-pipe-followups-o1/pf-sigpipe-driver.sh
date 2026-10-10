#!/usr/bin/env bash
# Drives the real bin/fm-public-followup.sh consume refusal path with SIGPIPE
# ignored (as CI does) and a tasks-axi refusal that writes a large multi-line
# stderr, then reports consume's stderr and the recorded rejection reason.
# Usage: pf-sigpipe-driver.sh <repo-root>
set -u
ROOT_ARG=$1
TESTF="$ROOT_ARG/tests/fm-public-followup.test.sh"
# Source the suite's helpers only (drop the bare test invocations).
src=$(mktemp); grep -v '^test_[a-z0-9_]*$' "$TESTF" | sed "s#\$(dirname \"\${BASH_SOURCE\[0\]}\")#$ROOT_ARG/tests#" > "$src"
cd "$ROOT_ARG/tests" && . "$src"
home=$(make_home sigpipe)
seed_commitment "$home" pf-sp req-sp discord main work-sp
REAL=$(command -v tasks-axi)
cat > "$home/fakebin/tasks-axi" <<SH
#!/usr/bin/env bash
if [ "\$1" = public-followup ] && [ "\$2" = work-event ]; then
  printf 'first refusal line: deliverable refused\n' >&2
  for i in \$(seq 1 20000); do printf 'detail line %05d padding padding padding\n' "\$i"; done >&2
  exit 1
fi
exec "$REAL" "\$@"
SH
chmod +x "$home/fakebin/tasks-axi"
id=$(publish_raw_event "$home/state/public-followup/events" pf-sp main work-sp pr-merged \
  '{"pr_url":"https://example.invalid/example/repo/pulls/7"}')
out=$( (trap '' PIPE; run_pf "$home" consume) 2>"$home/consume.err"); rc=$?
echo "consume rc=$rc"
echo "consume stdout: $out"
echo "consume stderr ($(wc -c <"$home/consume.err" | tr -d ' ') bytes):"; cat "$home/consume.err"
echo "rejection reason file:"; cat "$home/state/public-followup/rejected/$id.reason"; echo
