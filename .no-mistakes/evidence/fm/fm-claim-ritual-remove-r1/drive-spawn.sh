#!/usr/bin/env bash
# drive-spawn.sh <firstmate-root> <label>
# Real fm-brief + fm-spawn in a disposable lab home on a private tmux socket,
# into a project that has a RITUAL.md and AGENTS.md claim-ritual prose, with a
# ship brief lacking Claim recovery:/Claim model: lines.
set -u
ROOT=$1; LABEL=$2
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
proj="$LAB/projects/proj"; mkdir -p "$proj"
git -C "$proj" init -q -b main; git -C "$proj" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
[ "${NO_RITUAL_FILE:-0}" = 1 ] || printf '# Ritual\nTo recover a stale claim, post a superseding comment.\n' > "$proj/RITUAL.md"
printf '%s\n' 'An abandoned `review:changes-requested` fix-owner claim never transfers accepted findings directly.' > "$proj/AGENTS.md"
git -C "$proj" add -A; git -C "$proj" -c user.email=t@t -c user.name=t commit -q -m ritual
printf '%s\n' '- proj [no-mistakes] - lab fixture (added 2026-01-01)' > "$LAB/data/projects.md"
E="env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE -u TMUX"
# Stop before any endpoint: a tmux that refuses means no window, worktree, or
# treehouse slot is created outside the lab; every intake check runs first.
FAKEBIN="$LAB/fakebin"; mkdir -p "$FAKEBIN"; printf '#!/bin/sh\nexit 1\n' > "$FAKEBIN/tmux"; chmod +x "$FAKEBIN/tmux"
id=ritual-ship
echo "== [$LABEL] project files: $(cd "$proj" && ls)"
$E FM_HOME="$LAB" "$ROOT/bin/fm-brief.sh" "$id" proj --mode no-mistakes >/dev/null 2>&1 || echo "brief scaffold failed"
c=$(cat "$LAB/data/$id/brief.md"); c=${c//'{TASK}'/Finish the fix.}; c=${c//'{FIRSTMATE_SPEC}'/See the handoff for context.}; printf '%s\n' "$c" > "$LAB/data/$id/brief.md"
echo "== [$LABEL] brief Claim lines present: $(grep -ci '^claim ' "$LAB/data/$id/brief.md")"
echo "== [$LABEL] fm-spawn.sh $id proj claude --mode no-mistakes --yolo off"
out=$(cd "$LAB" && $E FM_HOME="$LAB" FM_SPAWN_NO_GUARD=1 PATH="$FAKEBIN:$PATH" FM_BACKEND=tmux "$ROOT/bin/fm-spawn.sh" "$id" "$proj" claude --mode no-mistakes --yolo off 2>&1); rc=$?
printf '%s\n' "$out" | tail -15
echo "== [$LABEL] exit=$rc"
echo "== [$LABEL] launch-brief.md present: $([ -f "$LAB/data/$id/launch-brief.md" ] && echo yes || echo no)"
echo "== [$LABEL] task meta: $(cat "$LAB/state/$id.meta" 2>/dev/null | tr '\n' ' ')"
echo "== [$LABEL] mentions of claim ritual in output: $(printf '%s' "$out" | grep -ci 'claim ritual')"
rm -rf "$LAB"
