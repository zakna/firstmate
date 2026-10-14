#!/usr/bin/env bash
# Live Herdr submit-confirmation guard (live-harness-optin family).
#
# Herdr's native agent_status can stay idle for a whole landed Claude turn, and
# a busy-queued Enter can keep proven pending text visible. A stub cannot prove
# either signal. This guard launches real Claude Code in an isolated Herdr lab
# and requires fm_backend_herdr_send_text_submit to report empty for a landed
# idle steer. It requires bin/fm-send.sh to deliver a skill slash command to a
# named Claude session idle after a finished turn, and the skill to run. It
# then requires the same submit path to prove and submit a
# typed /exit slash command behind the command popup Claude renders below the
# composer (the fm-control exit breakage on 2.1.283) and verifies the agent
# actually exited. It fails naming the harness and version rather than
# degrading quietly.
#
# Run explicitly with FM_HERDR_SUBMIT_CONFIRM_LIVE=1 after a Herdr or Claude
# upgrade, and before trusting a refreshed docs/verification/runtime-backends.md
# "Herdr submit confirmation" entry.
# Every Herdr call, including adapter calls, is routed through bin/fm-herdr-lab.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB_HELPER=${HERDR_LAB_HELPER:-$ROOT/bin/fm-herdr-lab.sh}

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

fm_live_gate opt-in FM_HERDR_SUBMIT_CONFIRM_LIVE herdr jq claude

[ -x "$LAB_HELPER" ] || fail "FM_HERDR_SUBMIT_CONFIRM_LIVE=1 but the Herdr lab helper is not executable at $LAB_HELPER"

# shellcheck source=tests/herdr-test-safety.sh
. "$ROOT/tests/herdr-test-safety.sh"
herdr_forget_inherited_pane

ORIGINAL_PATH=$PATH
SESSION=$("$LAB_HELPER" name herdr-submit-confirm-live)
TMP_ROOT=$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd -P)/fm-herdr-submit-confirm-live.XXXXXX")
FAKEBIN="$TMP_ROOT/fakebin"
mkdir -p "$FAKEBIN"
CHECKED=0

cleanup() {
  local rc=$?
  trap - EXIT
  if ! PATH="$ORIGINAL_PATH" "$LAB_HELPER" teardown "$SESSION"; then
    rc=1
  fi
  rm -rf "$TMP_ROOT"
  exit "$rc"
}
trap cleanup EXIT

cat > "$FAKEBIN/herdr" <<EOF
#!/usr/bin/env bash
set -u
args=("\$@")
n=\${#args[@]}
if [ "\$n" -ge 2 ] && [ "\${args[\$((n-2))]}" = --session ]; then
  [ "\${args[\$((n-1))]}" = "$SESSION" ] || { echo "wrapper refused foreign session" >&2; exit 97; }
  args=("\${args[@]:0:\$((n-2))}")
else
  echo "wrapper requires trailing --session $SESSION" >&2
  exit 98
fi
exec env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "\${args[@]}"
EOF
chmod +x "$FAKEBIN/herdr"

"$LAB_HELPER" provision "$SESSION" || fail "could not provision the isolated Herdr lab"
export PATH="$FAKEBIN:$ORIGINAL_PATH"

# shellcheck source=/dev/null
. "$ROOT/bin/backends/herdr.sh"

lab() { env PATH="$ORIGINAL_PATH" "$LAB_HELPER" run "$SESSION" "$@"; }
WS_JSON=$(lab workspace create --cwd "$ROOT" --label fm-submitlive --no-focus) \
  || fail "could not create the isolated submit-confirm workspace"
PANE=$(printf '%s' "$WS_JSON" | jq -er '.result.root_pane.pane_id') \
  || fail "workspace create did not return a pane id"
TARGET="$SESSION:$PANE"
VERSION=$(PATH="$ORIGINAL_PATH" claude --version 2>/dev/null | head -1 || printf 'version-unknown')
HERDR_VER=$(PATH="$ORIGINAL_PATH" herdr --version 2>/dev/null | head -1 || printf 'herdr-unknown')

lab pane run "$PANE" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --dangerously-skip-permissions --settings '{\"feedbackDrafts\":\"off\"}'" >/dev/null \
  || fail "could not launch Claude Code ($VERSION) in the isolated Herdr pane"

idle=0
trusted=0
i=0
while [ "$i" -lt 60 ]; do
  screen=$(lab pane read "$PANE" --source visible 2>/dev/null || true)
  case "$screen" in
    *'bypass permissions on'*)
      # The composer footer means Claude is past any folder-trust prompt. Herdr
      # can report the agent idle while that prompt is still up, so the wait
      # keys off the rendered composer rather than the native status alone.
      st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
      case "$st" in idle|done) idle=1; break ;; esac
      ;;
    *'Yes, I trust this folder'*)
      # A fresh checkout path stops on Claude's folder-trust prompt, which the
      # pre-send proof would read as a non-empty composer. Accept it once and
      # keep waiting for a real idle composer; the accepted dialog stays in the
      # viewport. The prompt preselects "No, exit", so move to "Yes" before
      # confirming; a bare Enter quits Claude.
      if [ "$trusted" = 0 ]; then
        trusted=1
        lab pane send-keys "$PANE" down enter >/dev/null \
          || fail "could not accept Claude's folder-trust prompt"
      fi
      ;;
  esac
  i=$((i + 1))
  sleep 1
done
[ "$idle" = 1 ] || fail "Claude Code ($VERSION) on $HERDR_VER never rendered an idle composer in the lab pane"

TOKEN="FMHERDRPONG$$_$RANDOM"
verdict=$(fm_backend_herdr_send_text_submit "$TARGET" "Reply with exactly $TOKEN and nothing else." 3 0.4 0.4) \
  || fail "send_text_submit failed to run against Claude Code ($VERSION) on $HERDR_VER"
CHECKED=1
[ "$verdict" = empty ] \
  || fail "Claude Code ($VERSION) on $HERDR_VER: a landed idle steer must confirm empty, got '$verdict'"

# Confirm the instruction reached Claude, not merely that the composer cleared.
# The token occurs once in the submitted prompt and once in Claude's reply.
landed=0
i=0
screen=''
while [ "$i" -lt 45 ]; do
  screen=$(lab pane read "$PANE" --source recent --lines 200 2>/dev/null || true)
  occurrences=$(printf '%s\n' "$screen" | grep -F -c "$TOKEN" || true)
  if [ "$occurrences" -ge 2 ]; then
    landed=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
[ "$landed" = 1 ] \
  || fail "Claude Code ($VERSION) on $HERDR_VER: submit reported '$verdict' but the expected reply never rendered"
pass "live Herdr submit confirm: Claude Code ($VERSION) on $HERDR_VER reports empty and renders the requested reply in isolated session $SESSION"

# Away-mode digests start with U+2063, which Claude's composer read-back drops.
# The pre-Enter proof must still accept the rest of the payload.
# shellcheck source=bin/fm-operational-input.sh
. "$ROOT/bin/fm-operational-input.sh"
i=0
while [ "$i" -lt 45 ]; do
  st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  case "$st" in idle|done) break ;; esac
  i=$((i + 1))
  sleep 1
done
OP_TOKEN="FMHERDROPPONG$$_$RANDOM"
op_text=
fm_operational_input_encode away-supervisor "Reply with exactly $OP_TOKEN and nothing else." op_text \
  || fail "could not encode an away-supervisor payload"
verdict=$(fm_backend_herdr_send_text_submit "$TARGET" "$op_text" 3 0.4 0.4) \
  || fail "send_text_submit failed to run an operational payload against Claude Code ($VERSION) on $HERDR_VER"
[ "$verdict" = empty ] \
  || fail "Claude Code ($VERSION) on $HERDR_VER: a landed U+2063 operational payload must confirm empty, got '$verdict'"
landed=0
i=0
while [ "$i" -lt 45 ]; do
  screen=$(lab pane read "$PANE" --source recent --lines 200 2>/dev/null || true)
  occurrences=$(printf '%s\n' "$screen" | grep -F -c "$OP_TOKEN" || true)
  if [ "$occurrences" -ge 2 ]; then
    landed=1
    break
  fi
  i=$((i + 1))
  sleep 1
done
[ "$landed" = 1 ] \
  || fail "Claude Code ($VERSION) on $HERDR_VER: operational submit reported '$verdict' but the expected reply never rendered"
pass "live Herdr submit confirm: Claude Code ($VERSION) on $HERDR_VER submits a U+2063 away-supervisor payload whose read-back drops the mark"

# A skill slash command steered through fm-send to a NAMED Claude worker. A
# named session titles the composer's top rule; before that rule paired as the
# composer separator, the pre-Enter proof read the typed command as absent,
# cleared it, and fm-send reported "herdr send failed". This drives the real
# typed plane: a task selector resolved through a throwaway home's metadata
# (flat pane, no presentation binding), a pane idle after a finished turn, and
# a project skill whose reply proves the command ran rather than only landed.
SKILL_TOKEN="FMHERDRSKILL$$_$RANDOM"
SKILL_WORK="$TMP_ROOT/skillwork"
SKILL_HOME="$TMP_ROOT/skillhome"
mkdir -p "$SKILL_WORK/.claude/skills/fmprobe" "$SKILL_HOME/state" "$SKILL_HOME/config" "$SKILL_HOME/data"
cat > "$SKILL_WORK/.claude/skills/fmprobe/SKILL.md" <<EOF
---
name: fmprobe
description: Live-guard probe skill. Reply with exactly $SKILL_TOKEN and nothing else.
---
Reply with exactly $SKILL_TOKEN and nothing else.
EOF
git -C "$SKILL_WORK" init -q || fail "could not initialize the skill probe directory"
SKILL_JSON=$(lab workspace create --cwd "$SKILL_WORK" --label fm-submitskill --no-focus) \
  || fail "could not create the isolated named-session workspace"
SKILL_PANE=$(printf '%s' "$SKILL_JSON" | jq -er '.result.root_pane.pane_id') \
  || fail "named-session workspace create did not return a pane id"
lab pane run "$SKILL_PANE" "CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_SEND_FEEDBACK=0 claude --dangerously-skip-permissions --settings '{\"feedbackDrafts\":\"off\"}' -n fm-submitskill" >/dev/null \
  || fail "could not launch a named Claude Code ($VERSION) session in the isolated Herdr pane"
idle=0
trusted=0
i=0
while [ "$i" -lt 60 ]; do
  screen=$(lab pane read "$SKILL_PANE" --source visible 2>/dev/null || true)
  case "$screen" in
    *'bypass permissions on'*)
      st=$(lab agent get "$SKILL_PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
      case "$st" in idle|done) idle=1; break ;; esac
      ;;
    *'Yes, I trust this folder'*)
      if [ "$trusted" = 0 ]; then
        trusted=1
        lab pane send-keys "$SKILL_PANE" down enter >/dev/null \
          || fail "could not accept Claude's folder-trust prompt in the named session"
      fi
      ;;
  esac
  i=$((i + 1))
  sleep 1
done
[ "$idle" = 1 ] || fail "named Claude Code ($VERSION) session on $HERDR_VER never rendered an idle composer"
screen=$(lab pane read "$SKILL_PANE" --source visible 2>/dev/null || true)
case "$screen" in
  *fm-submitskill*) ;;
  *) fail "Claude Code ($VERSION) on $HERDR_VER: the named session did not render its title, so this scenario would not cover a titled composer rule" ;;
esac
cat > "$SKILL_HOME/state/submitskill-o1.meta" <<EOF
window=$SESSION:$SKILL_PANE
endpoint_task_id=submitskill-o1
worktree=$SKILL_WORK
harness=claude
kind=ship
backend=herdr
herdr_session=$SESSION
herdr_pane_id=$SKILL_PANE
EOF
skill_send() { # <text>
  FM_HOME="$SKILL_HOME" FM_SEND_SETTLE=0 bash "$ROOT/bin/fm-send.sh" submitskill-o1 "$1" >/dev/null 2>&1
}
skill_wait_reply() { # <token> <min-occurrences>
  local n=0 occurrences
  while [ "$n" -lt 45 ]; do
    occurrences=$(lab pane read "$SKILL_PANE" --source recent --lines 200 2>/dev/null | grep -F -c "$1" || true)
    [ "$occurrences" -ge "$2" ] && return 0
    n=$((n + 1))
    sleep 1
  done
  return 1
}
# A finished turn first, so the slash command reaches a worker that is idle
# after work rather than a fresh composer. It is typed with raw Herdr keys so
# only the slash command below depends on the submit path under test.
WARM_TOKEN="FMHERDRWARM$$_$RANDOM"
lab pane send-text "$SKILL_PANE" "Reply with exactly $WARM_TOKEN and nothing else." >/dev/null \
  || fail "could not type the warm-up turn into the named session"
sleep 0.5
lab pane send-keys "$SKILL_PANE" enter >/dev/null \
  || fail "could not submit the warm-up turn in the named session"
skill_wait_reply "$WARM_TOKEN" 2 \
  || fail "Claude Code ($VERSION) on $HERDR_VER: the named session never answered its warm-up turn"
i=0
while [ "$i" -lt 45 ]; do
  st=$(lab agent get "$SKILL_PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  case "$st" in idle|done) break ;; esac
  i=$((i + 1))
  sleep 1
done
skill_send '/fmprobe' \
  || fail "Claude Code ($VERSION) on $HERDR_VER: fm-send refused a skill slash command to an idle named session (the herdr send failed shape)"
skill_wait_reply "$SKILL_TOKEN" 1 \
  || fail "Claude Code ($VERSION) on $HERDR_VER: fm-send reported a delivered skill slash command but the skill never replied"
pass "live Herdr submit confirm: Claude Code ($VERSION) on $HERDR_VER runs a skill slash command sent by fm-send to an idle named session"

# The fm-control exit regression: a typed slash command (/exit) makes Claude
# Code 2.1.283 render its command popup between the composer and the pane
# bottom, which pushed the composer above the old bounded proof read - the
# typed command was judged unsent, cleared, and never submitted. The viewport
# capture must prove the typed /exit and submit it; Claude must actually
# exit. This scenario runs last because it ends the lab's Claude process.
i=0
while [ "$i" -lt 45 ]; do
  st=$(lab agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status // empty')
  case "$st" in idle|done) break ;; esac
  i=$((i + 1))
  sleep 1
done
verdict=$(fm_backend_herdr_send_text_submit "$TARGET" '/exit' 3 0.4 1.2) \
  || fail "send_text_submit failed to run the /exit submission against Claude Code ($VERSION) on $HERDR_VER"
[ "$verdict" != send-failed ] \
  || fail "Claude Code ($VERSION) on $HERDR_VER: a typed /exit behind its command popup was judged unsent and cleared instead of submitted"
exited=0
i=0
while [ "$i" -lt 30 ]; do
  if ! lab agent get "$PANE" >/dev/null 2>&1; then exited=1; break; fi
  i=$((i + 1))
  sleep 1
done
[ "$exited" = 1 ] \
  || fail "Claude Code ($VERSION) on $HERDR_VER: the /exit submission reported '$verdict' but the agent never exited"
pass "live Herdr submit confirm: Claude Code ($VERSION) on $HERDR_VER proves and submits a typed /exit behind its command popup"

[ "$CHECKED" -gt 0 ] || fail "FM_HERDR_SUBMIT_CONFIRM_LIVE=1 checked no harness"
