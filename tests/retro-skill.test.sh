#!/usr/bin/env bash
# The retro skill's run-collection query, executed against a fixture pipeline database.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TMP_ROOT=$(fm_test_tmproot retro-skill)
SKILL="$ROOT/.agents/skills/retro/SKILL.md"

# The first query of the skill's sqlite block: every attempt on the delivery.
run_query() { # <db> <branch> <pull request url> <upstream url>
  local q
  q=$(awk '/^sqlite3 -readonly "\$DB" "SELECT r.id, p.upstream_url/ { on = 1 } on { print } on && /;"$/ { exit }' "$SKILL") \
    || fail 'cannot read the skill query'
  [ -n "$q" ] || fail 'skill has no run-collection query'
  q=${q//<branch>/$2}
  q=${q//<pull request url>/$3}
  q=${q//<repository upstream url>/$4}
  DB="$1" bash -c "$q"
}

test_run_query_stays_inside_the_repository() {
  local db="$TMP_ROOT/state.sqlite"
  sqlite3 "$db" <<SQL
CREATE TABLE repos (id TEXT PRIMARY KEY, upstream_url TEXT);
CREATE TABLE runs (id TEXT PRIMARY KEY, repo_id TEXT, branch TEXT, status TEXT, pr_url TEXT,
  created_at INTEGER, ci_ready_at INTEGER, updated_at INTEGER, parked_ms INTEGER);
INSERT INTO repos VALUES ('r1', 'https://github.com/o/app.git'), ('r2', 'https://github.com/o/other.git');
INSERT INTO runs VALUES
  ('mine', 'r1', 'fm/fix-tests', 'completed', 'https://github.com/o/app/pull/7', 1, 2, 3, 0),
  ('mine-retry', 'r1', 'fm/fix-tests', 'failed', NULL, 0, 0, 1, 0),
  ('theirs', 'r2', 'fm/fix-tests', 'completed', 'https://github.com/o/other/pull/7', 1, 2, 3, 0);
SQL
  local out
  out=$(run_query "$db" fm/fix-tests https://github.com/o/app/pull/7 https://github.com/o/app.git | cut -d'|' -f1 | sort | tr '\n' ' ')
  [ "$out" = 'mine mine-retry ' ] || fail "run query returned [$out], expected only this repository's runs"
  pass 'run query ignores another repository that reuses the branch name'
}

failures=0
for test_name in test_run_query_stays_inside_the_repository; do
  ( "$test_name" ) || failures=$((failures + 1))
done
[ "$failures" -eq 0 ] || fail "$failures retro-skill regressions"
