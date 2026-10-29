#!/usr/bin/env bash
# Behavior tests for the Sonnet/Haiku effort ceiling enforced at spawn and relaunch time.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HARNESS="$ROOT/bin/fm-harness.sh"
SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-model-effort-limit)

# <harness> <model> <effort> <allow|refuse> <expected error substring, refuse only>
while IFS='|' read -r harness model effort want expect; do
  [ -n "$harness" ] || continue
  out=$(bash "$HARNESS" validate-model-effort "$harness" "$model" "$effort" 2>&1)
  rc=$?
  case "$want" in
    allow) [ "$rc" -eq 0 ] && [ -z "$out" ] || fail "$harness $model $effort should be allowed (rc=$rc): $out" ;;
    refuse)
      [ "$rc" -ne 0 ] || fail "$harness $model $effort should be refused"
      case "$out" in *"$expect"*) ;; *) fail "$harness $model $effort refusal lacks '$expect': $out" ;; esac
      case "$out" in *"$model"*"$effort"*) ;; *) fail "refusal must name model and effort: $out" ;; esac
      ;;
  esac
done <<'TABLE'
claude|claude-sonnet-5-5|low|allow|
claude|claude-sonnet-5-5|medium|allow|
claude|claude-sonnet-5-5|high|refuse|maximum for Sonnet is medium
claude|claude-sonnet-5-5|xhigh|refuse|maximum for Sonnet is medium
claude|claude-sonnet-5-5|max|refuse|maximum for Sonnet is medium
claude|sonnet|high|refuse|maximum for Sonnet is medium
claude|Claude-Sonnet-4-5|high|refuse|maximum for Sonnet is medium
claude|claude-haiku-5-5|low|allow|
claude|claude-haiku-5-5|medium|refuse|maximum for Haiku is low
claude|claude-haiku-5-5|high|refuse|maximum for Haiku is low
claude|haiku|xhigh|refuse|maximum for Haiku is low
claude|claude-opus-5-5|max|allow|
claude|claude-fable-5-1|xhigh|allow|
claude|claude-sonnet-5-5|default|allow|
claude|claude-sonnet-5-5||allow|
claude||high|allow|
codex|sonnet|high|allow|
pi|claude-haiku-5-5|high|allow|
TABLE
pass "validate-model-effort table"

# The spawn entry point refuses before any provisioning.
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$HOME_DIR/state" "$HOME_DIR/config" "$HOME_DIR/data"
out=$(FM_HOME="$HOME_DIR" bash "$SPAWN" model-effort-t1 "$TMP_ROOT/nowhere" --scout --harness claude --model claude-sonnet-5-5 --effort high 2>&1)
rc=$?
[ "$rc" -ne 0 ] || fail "spawn should refuse Sonnet at high effort"
case "$out" in *"maximum for Sonnet is medium"*) ;; *) fail "spawn refusal missing: $out" ;; esac
pass "fm-spawn refuses Sonnet at high effort"

# Effort gauge (fm-tooling #34): config/effort-gauge caps Opus effort by the fresh weekly runway.
GAUGE_BIN="$TMP_ROOT/gaugebin"
mkdir -p "$GAUGE_BIN"
cat > "$GAUGE_BIN/quota-axi" <<'SH'
#!/usr/bin/env bash
[ "${FM_FAKE_QUOTA_FAIL:-0}" = 0 ] || exit 1
if [ "${FM_FAKE_QUOTA_SCHEMA6:-0}" = 1 ]; then
  printf '{"schemaVersion":6,"providers":[{"provider":"claude","accountKey":"other","state":{"status":"fresh","stale":false},"quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","runway":{"status":"through_reset"}}]}},{"provider":"claude","accountKey":"default","state":{"status":"fresh","stale":false},"quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","runway":{"status":"%s"}}]}}]}\n' "${FM_FAKE_QUOTA_RUNWAY:-through_reset}"
  exit 0
fi
printf '{"providers":[{"provider":"claude","state":{"status":"%s","stale":%s},"quotaSemantics":{"effectiveAvailability":[{"scope":"all_models","runway":{"status":"%s"}}]}}]}\n' \
  "${FM_FAKE_QUOTA_STATE:-fresh}" "${FM_FAKE_QUOTA_STALE:-false}" "${FM_FAKE_QUOTA_RUNWAY:-through_reset}"
SH
chmod +x "$GAUGE_BIN/quota-axi"
GAUGE_CFG="$TMP_ROOT/gaugecfg"
mkdir -p "$GAUGE_CFG"
gauge() { # <effort> [override]; env FM_FAKE_QUOTA_* selects the reading
  PATH="$GAUGE_BIN:$PATH" FM_CONFIG_OVERRIDE="$GAUGE_CFG" bash "$HARNESS" validate-effort-gauge claude claude-opus-5-5 "$1" "${2:-}" 2>&1
}
out=$(gauge high) || fail "no gauge config must pass: $out"
echo medium > "$GAUGE_CFG/effort-gauge"
out=$(gauge medium) || fail "full gauge allows its own effort: $out"
out=$(gauge high) && fail "full gauge must refuse above medium"
case "$out" in *"above the effort gauge 'medium'"*"through_reset"*) ;; *) fail "refusal lacks gauge and runway: $out" ;; esac
out=$(FM_FAKE_QUOTA_RUNWAY=projected_exhaustion gauge medium) && fail "stepped-down gauge must refuse medium"
case "$out" in *"gauge 'low'"*) ;; *) fail "step-down refusal lacks low: $out" ;; esac
out=$(FM_FAKE_QUOTA_RUNWAY=projected_exhaustion gauge low) || fail "stepped-down gauge allows low: $out"
out=$(FM_FAKE_QUOTA_RUNWAY=projected_exhaustion gauge medium "quota is for a one-off audit") || fail "override must pass: $out"
case "$out" in *"by override: quota is for a one-off audit"*) ;; *) fail "override must print the gauge: $out" ;; esac
out=$(FM_FAKE_QUOTA_STALE=true gauge low) && fail "stale reading must refuse"
case "$out" in *"cannot read a fresh Claude weekly runway"*) ;; *) fail "stale refusal message: $out" ;; esac
out=$(FM_FAKE_QUOTA_FAIL=1 gauge low) && fail "unreadable quota must refuse"
out=$(FM_FAKE_QUOTA_RUNWAY=exhausted_now gauge low) && fail "exhausted runway must refuse"
case "$out" in *"exhausted now"*) ;; *) fail "exhausted refusal message: $out" ;; esac
out=$(FM_FAKE_QUOTA_STALE=true gauge low "stale is fine today") || fail "override must pass a stale reading: $out"
case "$out" in *"by override: stale is fine today"*) ;; *) fail "stale override must print why: $out" ;; esac
out=$(FM_FAKE_QUOTA_SCHEMA6=1 FM_FAKE_QUOTA_RUNWAY=projected_exhaustion gauge medium) && fail "schema 6 must bind the default Claude row"
case "$out" in *"gauge 'low'"*) ;; *) fail "schema 6 refusal lacks low: $out" ;; esac
out=$(FM_FAKE_QUOTA_FAIL=1 gauge low "no quota-axi here") || fail "override must pass unreadable quota: $out"
out=$(PATH="$GAUGE_BIN:$PATH" FM_CONFIG_OVERRIDE="$GAUGE_CFG" FM_FAKE_QUOTA_RUNWAY=projected_exhaustion bash "$HARNESS" validate-effort-gauge claude claude-sonnet-5-5 medium 2>&1) || fail "gauge covers Opus only: $out"
pass "validate-effort-gauge"

# The spawn entry point refuses before any provisioning, and the override flag is accepted.
out=$(PATH="$GAUGE_BIN:$PATH" FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$GAUGE_CFG" FM_FAKE_QUOTA_RUNWAY=projected_exhaustion bash "$SPAWN" gauge-t1 "$TMP_ROOT/nowhere" --scout --harness claude --model claude-opus-5-5 --effort medium 2>&1) &&
  fail "spawn should refuse Opus above the gauge"
case "$out" in *"above the effort gauge 'low'"*) ;; *) fail "spawn gauge refusal missing: $out" ;; esac
out=$(PATH="$GAUGE_BIN:$PATH" FM_HOME="$HOME_DIR" FM_CONFIG_OVERRIDE="$GAUGE_CFG" FM_FAKE_QUOTA_RUNWAY=projected_exhaustion bash "$SPAWN" gauge-t2 "$TMP_ROOT/nowhere" --scout --harness claude --model claude-opus-5-5 --effort medium --effort-gauge-override "audit" 2>&1)
case "$out" in *"above the effort gauge"*) fail "override flag must pass the gauge: $out" ;; esac
pass "fm-spawn applies the effort gauge"
