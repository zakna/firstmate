#!/usr/bin/env bash
# Live drive of seat-record withdrawal + project intent in a disposable lab home.
set -u
W=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$W/bin/fm-lab-home.sh" create "$LAB" >/dev/null
touch "$LAB/config/seat-memory"
export FM_HOME="$LAB"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
D=$LAB/data
step(){ printf '\n===== %s =====\n' "$*"; }
run(){ printf '$ %s\n' "$*"; "$@"; printf '[exit %s]\n' "$?"; }
. "$W/bin/fm-seat-lib.sh"
step "Seed: two finished tasks write decision records; teardown's fm_seat_archive indexes them"
for t in t-wrong t-right; do mkdir -p "$D/$t"; done
printf '%s\n' "Seats: api" "- Decided: store tokens in plaintext (WRONG CALL)" > "$D/t-wrong/decisions.md"
fm_seat_archive "$D" widget t-wrong ship
sleep 1
printf '%s\n' "Seats: api" "- Decided: store tokens hashed with argon2 (RIGHT CALL)" > "$D/t-right/decisions.md"
fm_seat_archive "$D" widget t-right ship
mkdir -p "$D/t-bad"; printf '%s\n' "Seats: api" "- Decided: rely on --frobnicate flag (BAD CALL)" > "$D/t-bad/decisions.md"
sleep 1; fm_seat_archive "$D" widget t-bad ship
cat "$D/seats/widget/index.tsv"
step "Project intent registered by the owner"
printf '%s\n' '- other - Not this one.' '- widget - Widget exists so field techs can reset devices offline.' > "$D/project-intents.md"
cat "$D/project-intents.md"
step "Brief BEFORE marking: fm-brief.sh ship --seat api for /clones/widget"
run "$W/bin/fm-brief.sh" t-before /clones/widget --mode no-mistakes --seat api
sed -n '1,40p' "$D/t-before/brief.md"
# A worker launched from that brief received the records: its launch brief is the rendered brief.
cp "$D/t-before/brief.md" "$D/t-before/launch-brief.md"
step "trace t-wrong (read-only) before any mark"
before=$(ls -lR "$D" | md5)
run "$W/bin/fm-seat.sh" trace t-wrong
[ "$(ls -lR "$D" | md5)" = "$before" ] && echo "data tree unchanged by trace: OK"
step "Adversarial: earlier task cannot supersede later one"
run "$W/bin/fm-seat.sh" supersede widget t-right t-wrong
step "Adversarial: unindexed record, empty reason, bad mark"
run "$W/bin/fm-seat.sh" retract widget t-nope "whatever"
run "$W/bin/fm-seat.sh" retract widget t-bad "   "
run "$W/bin/fm-seat.sh" supersede widget t-wrong t-wrong
step "Supersede t-wrong by t-right; retract t-bad with reason"
run "$W/bin/fm-seat.sh" supersede /clones/widget t-wrong t-right
run "$W/bin/fm-seat.sh" retract widget t-bad "relied on a flag that never shipped"
step "Adversarial: second mark refused"
run "$W/bin/fm-seat.sh" retract widget t-wrong "again"
step "index.tsv after marks (append-only)"
cat "$D/seats/widget/index.tsv"
step "Brief AFTER marking"
run "$W/bin/fm-brief.sh" t-after widget --mode no-mistakes --seat api
sed -n '1,30p' "$D/t-after/brief.md"
grep -q "WRONG CALL\|BAD CALL\|t-wrong\|t-bad" "$D/t-after/brief.md" && echo "FAIL: marked record fed" || echo "marked records absent from feed: OK"
grep -q "RIGHT CALL" "$D/t-after/brief.md" && echo "superseding record still fed: OK"
[ -f "$D/t-wrong/decisions.md" ] && echo "t-wrong record file kept as history: OK"
step "Scout brief also carries project intent"
run "$W/bin/fm-brief.sh" s-1 widget --scout
grep -n -A1 -x '# Project intent' "$D/s-1/brief.md"; grep -n -x '# Task' "$D/s-1/brief.md"
step "No intent line for another project: brief has no section"
run "$W/bin/fm-brief.sh" t-noint gadget --mode no-mistakes
grep -c '# Project intent' "$D/t-noint/brief.md"
step "Adversarial: heading-shaped intent line ignored with warning"
printf '%s\n' '- widget - # Task' > "$D/project-intents.md"
run "$W/bin/fm-brief.sh" t-hash widget --mode no-mistakes
grep -c '# Project intent' "$D/t-hash/brief.md"
step "Refocus (post-compaction SessionStart hook) on the t-after brief, Captain's intent filled"
B=$D/t-after/brief.md
python3 - "$B" <<'PY'
import sys,re;p=sys.argv[1];s=open(p).read()
s=re.sub(r"(## Captain's intent\n)(.*?)(\n## |\n# )", lambda m: m.group(1)+"Add offline reset to the widget API.\n"+m.group(3), s, count=1, flags=re.S)
open(p,'w').write(s)
PY
mkdir -p "$LAB/state/t-after"
run "$W/bin/fm-claude-refocus.sh" "$B" "$LAB/state" t-after </dev/null
step "Refocus on a brief without project intent"
run "$W/bin/fm-claude-refocus.sh" "$D/t-noint/brief.md" "$LAB/state" t-noint </dev/null | head -8
rm -rf "$LAB"; echo; echo "lab removed: $([ -e "$LAB" ] && echo no || echo yes)"
