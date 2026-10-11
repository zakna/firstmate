#!/usr/bin/env bash
# drive-promote.sh <firstmate-root> <label>
# Real fm-brief --scout + fm-promote in a disposable lab home, scout in a project
# with RITUAL.md (and, if NO_RITUAL_FILE=1, only AGENTS.md claim prose), whose
# Captain's intent lacks Claim recovery:/Claim model: lines.
set -u
ROOT=$1; LABEL=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
proj="$LAB/projects/proj"; mkdir -p "$proj"
[ "${NO_RITUAL_FILE:-0}" = 1 ] || printf '# Ritual\nTo recover a stale claim, post a superseding comment.\n' > "$proj/RITUAL.md"
printf '%s\n' 'An abandoned fix-owner claim needs a superseding comment before any edit.' > "$proj/AGENTS.md"
printf '%s\n' '- proj [direct-PR] - lab fixture (added 2026-01-01)' > "$LAB/data/projects.md"
E="env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX"
id=ritual-promote-r1; meta="$LAB/state/$id.meta"
printf 'window=fm-%s\nkind=scout\nworktree=/tmp/wt\nproject=%s\n' "$id" "$proj" > "$meta"
$E FM_HOME="$LAB" "$ROOT/bin/fm-brief.sh" "$id" proj --scout >/dev/null 2>&1 || echo "scout brief scaffold failed"
c=$(cat "$LAB/data/$id/brief.md"); c=${c//'{TASK}'/Finish the fix.}; c=${c//'{FIRSTMATE_SPEC}'/Plain spec.}; printf '%s\n' "$c" > "$LAB/data/$id/brief.md"
echo "== [$LABEL] project files: $(cd "$proj" && ls | tr '\n' ' ')"
echo "== [$LABEL] brief Claim lines present: $(grep -ci '^claim ' "$LAB/data/$id/brief.md")"
echo "== [$LABEL] meta before: $(grep kind= "$meta")"
echo "== [$LABEL] fm-promote.sh $id --mode direct-PR --yolo off"
out=$($E FM_HOME="$LAB" "$ROOT/bin/fm-promote.sh" "$id" --mode direct-PR --yolo off 2>&1); rc=$?
printf '%s\n' "$out" | tail -10
echo "== [$LABEL] exit=$rc"
echo "== [$LABEL] meta after: $(grep kind= "$meta")"
echo "== [$LABEL] ship-instructions.md present: $([ -f "$LAB/data/$id/ship-instructions.md" ] && echo yes || echo no)"
echo "== [$LABEL] mentions of claim ritual in output: $(printf '%s' "$out" | grep -ci 'claim ritual')"
rm -rf "$LAB"
