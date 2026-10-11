#!/usr/bin/env bash
# Runs only the claim-ritual scenarios of tests/fm-task-delivery.test.sh: real
# bin/fm-brief.sh, bin/fm-spawn.sh and bin/fm-promote.sh against fixture homes
# and fixture projects (fake tmux backstop; no live windows).
set -u
cd "$1"
src=$(sed -n '1,1808p' tests/fm-task-delivery.test.sh | sed 's|"$(dirname "${BASH_SOURCE\[0\]}")/lib.sh"|tests/lib.sh|')
eval "$src"
ROOT=$PWD SPAWN="$ROOT/bin/fm-spawn.sh" BRIEF="$ROOT/bin/fm-brief.sh" PROMOTE="$ROOT/bin/fm-promote.sh"
test_spawn_refuses_claim_ritual_project_without_recovery_and_model
test_promotion_refuses_claim_ritual_project_without_recovery_and_model
echo "# claim-ritual scenarios passed"
