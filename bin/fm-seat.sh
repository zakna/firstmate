#!/usr/bin/env bash
# fm-seat.sh - the owner's commands for seat-memory decision records
# (docs/seat-memory.md).
#
# Usage:
#   fm-seat.sh supersede <project> <task-id> <later-task-id>
#   fm-seat.sh retract <project> <task-id> <reason>...
#   fm-seat.sh trace <task-id>
#
# supersede and retract append one mark line to the project's seat index so
# the "# Seat decisions" feed skips that task's record from then on; the
# record file stays as history. <project> is the project's name or clone path,
# keyed by its clone directory name as everywhere in seat memory.
# trace is read-only: it prints the launch brief of every task that received
# the record, one path per line, so the workers it reached can be found.
# bin/fm-seat-lib.sh's header owns the index format and the rules each mark
# checks (fm_seat_mark, fm_seat_trace).
# Exit status: 0 on success, 1 on a refused mark, 2 on a usage error.
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
resolve_directory_input() {
  local name=$1 path=$2 resolved
  case "$path" in
    /*) printf '%s\n' "$path"; return 0 ;;
  esac
  resolved=$(CDPATH='' cd -- "$path" 2>/dev/null && pwd -P) || {
    echo "error: $name directory cannot be resolved: $path" >&2
    return 1
  }
  printf '%s\n' "$resolved"
}

FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME=$(resolve_directory_input FM_HOME "${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}") || exit 1
if [ -n "${FM_DATA_OVERRIDE:-}" ]; then
  DATA=$(resolve_directory_input FM_DATA_OVERRIDE "$FM_DATA_OVERRIDE") || exit 1
else
  DATA="$FM_HOME/data"
fi
# shellcheck source=bin/fm-seat-lib.sh
. "$SCRIPT_DIR/fm-seat-lib.sh"

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  supersede)
    [ "$#" -eq 4 ] || { usage >&2; exit 2; }
    project=$(fm_seat_project_key "$2") || { echo "error: '$2' is not a seat-memory project" >&2; exit 1; }
    fm_seat_mark "$DATA" "$project" "$3" superseded "$4"
    ;;
  retract)
    [ "$#" -ge 4 ] || { usage >&2; exit 2; }
    project=$(fm_seat_project_key "$2") || { echo "error: '$2' is not a seat-memory project" >&2; exit 1; }
    id=$3
    shift 3
    fm_seat_mark "$DATA" "$project" "$id" retracted "$*"
    ;;
  trace)
    [ "$#" -eq 2 ] || { usage >&2; exit 2; }
    fm_seat_trace "$DATA" "$2"
    ;;
  *) usage >&2; exit 2 ;;
esac
