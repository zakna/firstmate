#!/usr/bin/env bash
# Check or prepare the `--intent` string a no-mistakes worker passes, before the
# run starts: the pipeline publishes that string as the pull request body.
# Usage: fm-intent-check.sh check <task-data-dir|brief-file> <intent-file> [--captain-words <file>]... [--resolved <file>]...
#        fm-intent-check.sh scrub <task-data-dir|brief-file>
# Run it from the task's repository: fleet terms that repository's tracked
# files already use are its own vocabulary and are not refused, and only its
# github.com origin's issue URLs are required as `Refs #<n>`.
# check exits 0 when the file passes, 1 with one `intent-check:` line per
# refused line, and 2 on a usage or read error.
# scrub prints the authorized words plus the `Refs #<n>` line the check
# requires; when any line is refused it prints nothing, names each refused
# line on stderr, and exits 1, never removing or rewording a sentence.
# bin/fm-dod-lib.sh owns the rules (fm_intent_check, fm_intent_scrub) and
# which file a task directory resolves to (fm_intent_source_file).
set -u

# shellcheck source=bin/fm-dod-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fm-dod-lib.sh"

usage() {
  sed -n '4,5p' "${BASH_SOURCE[0]}" | sed 's/^# //'
}

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -ge 2 ] || { usage >&2; exit 2; }
cmd=$1 source=$2
shift 2
if [ -d "$source" ]; then
  dir=$source
  source=$(fm_intent_source_file "$dir") || { echo "intent-check: no brief in $dir" >&2; exit 2; }
fi
case "$cmd" in
  check)
    [ $# -ge 1 ] || { usage >&2; exit 2; }
    fm_intent_check "$source" "$@"
    ;;
  scrub)
    [ $# -eq 0 ] || { usage >&2; exit 2; }
    fm_intent_scrub "$source"
    ;;
  *) usage >&2; exit 2 ;;
esac
