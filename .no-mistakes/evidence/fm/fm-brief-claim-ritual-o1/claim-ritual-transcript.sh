#!/usr/bin/env bash
# Transcript: real fm-brief.sh + fm-spawn.sh on fixture projects, printing what the operator sees.
set -u
cd "$1"
src=$(sed -n '1,1808p' tests/fm-task-delivery.test.sh | sed 's|"$(dirname "${BASH_SOURCE\[0\]}")/lib.sh"|tests/lib.sh|')
eval "$src"
ROOT=$PWD SPAWN="$ROOT/bin/fm-spawn.sh" BRIEF="$ROOT/bin/fm-brief.sh"
IFS='|' read -r home proj fakebin <<<"$(make_home transcript)"
show() { # id spec
  FM_HOME="$home" "$BRIEF" "$1" proj --mode no-mistakes >/dev/null 2>&1
  fill_brief_subsections "$home/data/$1/brief.md" 'Finish the fix.' "$2"
  echo "\$ fm-spawn.sh $1 ... (ship)"
  run_spawn "$home" "$fakebin" "$1" "$proj" claude --mode no-mistakes --yolo off | grep -i "claim ritual" || echo "(no claim-ritual message)"
  [ -e "$home/data/$1/launch-brief.md" ] && echo "=> launch brief rendered" || echo "=> NO launch brief rendered"
  echo
}
echo "## Project has RITUAL.md"; printf '# Ritual\nPost a superseding comment.\n' > "$proj/RITUAL.md"
show t-bare 'See the handoff for context.'
show t-half 'Claim recovery: post a superseding comment first.'
show t-full $'Claim recovery: post a superseding comment first.\nClaim model: gpt-5.6-sol'
show t-empty $'Claim recovery:\nClaim model: gpt-5.6-sol'
rm "$proj/RITUAL.md"
echo "## Project has only AGENTS.md with PR 43 wording"
printf '%s\n' 'An abandoned `review:changes-requested` fix-owner claim never transfers accepted findings directly.' > "$proj/AGENTS.md"
show t-prose 'Plain spec.'
echo "## AGENTS.md with harmless/product claim wording"
printf '%s\n' 'Do not claim the fix is verified without running tests.' 'The queue should recover stale lease claims after timeout.' > "$proj/AGENTS.md"
show t-harmless 'Plain spec.'
