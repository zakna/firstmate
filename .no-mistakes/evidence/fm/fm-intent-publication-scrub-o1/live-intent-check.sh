#!/usr/bin/env bash
# Live driver: scaffold a real no-mistakes brief in a disposable lab home, fill it
# with retro leak patterns, and run bin/fm-intent-check.sh from a project repo.
set -u
WT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
REPO=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab-repo.XXXXXX")
git init -q "$REPO"; printf 'Fan controller for the rack.\n' > "$REPO/README.md"
git -C "$REPO" add README.md; git -C "$REPO" -c user.name=t -c user.email=t@e commit -q -m init
git -C "$REPO" remote add origin https://github.com/acme/rackfan.git
ID=intent-live-a1; D="$LAB/data/$ID"; CHECK="$WT/bin/fm-intent-check.sh"
say() { printf '\n$ %s\n' "$*"; }
run() { say "$*"; (cd "$REPO" && env FM_HOME="$LAB" "$@"); echo "[exit $?]"; }
fill() {  # <intent> <spec>
  python3 - "$D/brief.md" "$1" "$2" <<'PY'
import sys; p,i,s=sys.argv[1:]; t=open(p).read()
t=t.replace("{TASK}",i,1).replace("{FIRSTMATE_SPEC}",s,1); open(p,"w").write(t)
PY
}
say "fm-brief.sh $ID rackfan --mode no-mistakes"
env -u NO_MISTAKES_GATE FM_HOME="$LAB" "$WT/bin/fm-brief.sh" "$ID" rackfan --mode no-mistakes >/dev/null; echo "[exit $?]"
echo "--- Definition of done lines naming the check:"; grep -n "fm-intent-check\|never drop or reword" "$D/brief.md" | sed "s#$LAB#\$LAB#g"
cp "$D/brief.md" "$D/brief.template"

echo; echo "=== Scenario A: leaky Captain's intent (dotagents/unraid/ha retro patterns) ==="
fill 'Captain: make the fan quieter at night, see https://github.com/acme/rackfan/issues/43.
The captain said "yes implement it".
You must rebase your branch before starting.
Checks are green and no run exists yet, so the crewmate should start the pipeline.
Keep the curve below 30 percent after 22:00.' 'Refactor the PWM module first. Use a table-driven test.'
cat "$D/brief.md" | sed -n "/## Captain's intent/,/## Firstmate spec/p"
run "$CHECK" scrub "$D"

echo; echo "=== Scenario B: clean specification; scrub adds Refs at creation; check passes ==="
cp "$D/brief.template" "$D/brief.md"
fill 'Make the fan quieter at night, as described in https://github.com/acme/rackfan/issues/43.
Keep the curve below 30 percent after 22:00.
Show the temperature so you can see drift.
[Fan docs](https://example.com/fan) describe the night curve.' 'Refactor the PWM module first. Use a table-driven test.'
say "$CHECK scrub \$D > intent.txt"; (cd "$REPO" && FM_HOME="$LAB" "$CHECK" scrub "$D" > "$LAB/intent.txt"); echo "[exit $?]"; echo "--- intent.txt:"; cat "$LAB/intent.txt"
run "$CHECK" check "$D" "$LAB/intent.txt"

echo; echo "=== Scenario C: composed string drops the Refs line ==="
grep -v '^Refs' "$LAB/intent.txt" > "$LAB/norefs.txt"
run "$CHECK" check "$D" "$LAB/norefs.txt"

echo; echo "=== Scenario D: composed string adds Firstmate spec / framing / label / invented ref ==="
{ cat "$LAB/intent.txt"; printf 'Refactor the PWM module first.\n## Firstmate spec\nUser: ship it tonight.\nRefs #99\n'; } > "$LAB/bad.txt"
cat "$LAB/bad.txt"
run "$CHECK" check "$D" "$LAB/bad.txt"

echo; echo "=== Scenario E: launch overlay (as fm-spawn renders it) is the source and repeats the no-drop rule ==="
( . "$WT/bin/fm-dod-lib.sh"; { cat "$D/brief.md"; fm_brief_intent_overlay 'Keep the curve below 30 percent after 22:00.'; } > "$D/launch-brief.md" )
grep -n "never drop or reword" "$D/launch-brief.md" | tail -1
run "$CHECK" check "$D" "$LAB/intent.txt"
printf 'Keep the curve below 30 percent after 22:00.\n' > "$LAB/ov.txt"
run "$CHECK" check "$D" "$LAB/ov.txt"
rm -rf "$LAB" "$REPO"; echo; echo "(lab removed)"
