#!/usr/bin/env bash
# Regression test for fm-spawn's refusal of a Treehouse slot anchored to
# another clone.
#
# Treehouse names a pool by the repository directory name plus a hash of the
# origin URL, so two clones of one origin that sit in same-named directories
# share one pool, while each slot is a worktree of whichever clone created it.
# This builds that world with no harness: a bare origin, two clones named
# alike, and a pool slot anchored to the second clone. It drives the real spawn
# path with a fake terminal for a non-Claude worker and proves the spawn for the
# first clone refuses by name before it claims the slot or refreshes its base,
# while the same slot still launches for the clone that owns it.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

TMP_ROOT=$(fm_test_tmproot fm-spawn-pool-slot-anchor)

test_slot_anchored_to_another_clone_refuses() {
  local case_dir home origin seed clone_a clone_b pool slot fakebin id out status before
  case_dir="$TMP_ROOT/two-clones"
  home="$case_dir/home"
  origin="$case_dir/origin.git"
  seed="$case_dir/seed"
  clone_a="$case_dir/home-a/project"
  clone_b="$case_dir/home-b/project"
  pool="$case_dir/pool"
  slot="$pool/1/project"
  fakebin=$(make_spawn_fakebin "$case_dir/fake")

  fm_test_spawn_home "$home" codex

  git init --quiet -b main "$seed"
  printf 'base\n' > "$seed/README.md"
  git -C "$seed" add README.md
  git -C "$seed" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial
  git clone --quiet --bare "$seed" "$origin"
  git clone --quiet "file://$origin" "$clone_a"
  git clone --quiet "file://$origin" "$clone_b"
  [ "$(git -C "$clone_a" remote get-url origin)" = "$(git -C "$clone_b" remote get-url origin)" ] \
    || fail "fixture clones do not share one origin"

  mkdir -p "$pool/1"
  git -C "$clone_b" worktree add --quiet --detach "$slot" HEAD
  printf '{"worktrees":[{"name":"1","path":"%s"}]}\n' "$slot" > "$pool/treehouse-state.json"
  before=$(git -C "$slot" rev-parse HEAD)

  id='pool-anchor-foreign-r1'
  fm_test_spawn_brief "$home" "$id"
  out=$(fm_test_run_spawn "$home" "$slot" "$fakebin" "$id" "$clone_a" --scout)
  status=$?
  if [ "${FM_TEST_EVIDENCE:-0}" = 1 ]; then
    printf '$ bin/fm-spawn.sh %s %s --scout   # pane in %s\n%s\nexit=%s\n' \
      "$id" "$clone_a" "$slot" "$out" "$status"
  fi
  [ "$status" -ne 0 ] || fail "spawn for clone A launched in a slot anchored to clone B"$'\n'"$out"
  assert_contains "$out" "Treehouse pool slot $slot is a worktree of clone '$clone_b'" \
    "the refusal did not name the slot and the clone it is anchored to"
  assert_contains "$out" "not of clone '$clone_a' this spawn is for" \
    "the refusal did not name the clone the spawn wanted"
  [ ! -e "$home/state/$id.meta" ] || fail "the refused spawn published task metadata"
  [ ! -e "$pool/1/.fm-slot-owner" ] || fail "the refused spawn claimed the foreign slot"
  [ ! -e "$clone_b/.git/FETCH_HEAD" ] || fail "the refused spawn fetched into the foreign clone"
  [ "$(git -C "$slot" rev-parse HEAD)" = "$before" ] || fail "the refused spawn moved the foreign slot's HEAD"
  pass "a spawn for one clone refuses a Treehouse slot anchored to another clone of the same origin"

  # The same slot is a legitimate allocation for the clone that owns it, so the
  # refusal above is about anchoring, not about the slot itself.
  id='pool-anchor-own-r1'
  fm_test_spawn_brief "$home" "$id"
  out=$(fm_test_run_spawn "$home" "$slot" "$fakebin" "$id" "$clone_b" --scout)
  status=$?
  expect_code 0 "$status" "spawn for clone B should launch in its own slot"$'\n'"$out"
  assert_grep "worktree=$slot" "$home/state/$id.meta" "spawn for clone B did not record its slot"
  grep -Fxq -- "task=$id" "$pool/1/.fm-slot-owner" \
    || fail "spawn for clone B did not claim its own slot"
  pass "the same slot still launches and is claimed for the clone that owns it"
}

test_slot_anchored_to_another_clone_refuses

echo "# all fm-spawn-pool-slot-anchor tests passed"
