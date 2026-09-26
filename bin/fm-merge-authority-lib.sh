#!/usr/bin/env bash
# Durable ownership of the authority under which a task's merge was accepted.
#
# The away-posture record (state/.afk-contract) is resolved only at the merge
# gate. After a forge accepts the merge, bin/fm-pr-merge.sh persists that answer
# as:
#   state/<task-id>.merge-authority
#   fm-merge-authority-v1
#   <provider>
#   <host>
#   <path>
#   <number>
#   <authority>                 away | attended
# While the away-posture record exists every merge runs under away authority
# (the record's presence is the whole mechanical fact; which merge the captain's
# away words meant is the supervision session's reading); without it the merge
# is attended. The retired values yolo and away-grant are still accepted when an
# existing record is read, so a merge persisted before the words model landed is
# still consumed, but they are never written again.
# The identity comes from the merge run's immutable canonical URL parse;
# persistence revalidates the task's current pr= metadata under its metadata
# and lifecycle locks and refuses a mismatch. The file is atomically published,
# mode 0600, single-link, and on the state filesystem. A poll consumes it only
# when all identity fields match its own validated snapshot. Missing, malformed,
# or mismatched state means external; it is never resolved again from a later
# away-posture record.
#
# Resolution authorizes nothing by itself. bin/fm-pr-merge.sh owns the merge
# gate and persists only after a forge command succeeds, before releasing the
# task lifecycle lock. After observing a landed merge, bin/fm-watch.sh acquires
# that same lock, revalidates the poll, publishes its durable outcome, and
# retires only the exact authority record it read. Teardown uses the same lock,
# so it cannot interleave with that consumption transaction, and removes any
# remaining record.
#
# External merge record. A merged poll that finds no matching record above
# observed an external merge: the pull request landed outside
# bin/fm-pr-merge.sh. fm_merge_external_record then writes what the forge says
# about that landing into state/<task-id>.meta, placed before the pr= line
# because fm_pr_metadata_identity_parse refuses unknown lines after it:
#   merge_origin=external
#   merge_commit=<sha> | unknown
#   merge_parents=<parent count of the merge commit> | unknown
#   merge_actor=<login of the merging account> | unknown
#   merged_at=<ISO-8601 UTC merge time> | unknown
# A merge through bin/fm-pr-merge.sh writes none of these. Only GitHub is read,
# through the one GraphQL record read in bin/fm-pr-lib.sh, bounded by
# FM_MERGE_EXTERNAL_READ_TIMEOUT seconds (default 10). Another forge, a failed or
# timed-out read, and any value that fails validation record unknown. The
# record is best effort and runs after the outcome is published, while the poll
# still holds the task lifecycle lock that teardown needs: its failure is only
# logged and never blocks, retries, or changes that delivery.
# bin/fm-teardown.sh carries the fields into the backlog Done note.
#
# Sourced by those scripts and by tests. No side effects on source beyond its
# sourced libraries.

_FM_MERGE_AUTHORITY_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/fm-pr-lib.sh
. "$_FM_MERGE_AUTHORITY_LIB_DIR/fm-pr-lib.sh"
# shellcheck source=bin/fm-afk-contract.sh
. "$_FM_MERGE_AUTHORITY_LIB_DIR/fm-afk-contract.sh"
# shellcheck source=bin/fm-timeout-lib.sh
. "$_FM_MERGE_AUTHORITY_LIB_DIR/fm-timeout-lib.sh"

# shellcheck disable=SC2034 # Public results consumed by sourcing callers.
FM_MERGE_AUTHORITY=
# shellcheck disable=SC2034 # Public results consumed by sourcing callers.
FM_MERGE_AUTHORITY_REASON=
# shellcheck disable=SC2034 # Public results consumed by sourcing callers.
FM_MERGE_AUTHORITY_RECORD_IDENTITY=
FM_MERGE_EXTERNAL_COMMIT=unknown
FM_MERGE_EXTERNAL_PARENTS=unknown
FM_MERGE_EXTERNAL_ACTOR=unknown
FM_MERGE_EXTERNAL_AT=unknown

fm_merge_authority_resolve() {  # <home> <state> <meta> <task-id>
  local home=${1-} state=${2-} meta=${3-} id=${4-}
  FM_MERGE_AUTHORITY=
  FM_MERGE_AUTHORITY_REASON='invalid'
  [ -n "$home" ] && [ -n "$state" ] && [ -n "$meta" ] && [ -n "$id" ] || return 1

  if ! fm_afk_contract_present "$state"; then
    FM_MERGE_AUTHORITY='attended'
    FM_MERGE_AUTHORITY_REASON='attended'
    return 0
  fi
  if ! FM_HOME="$home" FM_STATE_OVERRIDE="$state" \
    "$_FM_MERGE_AUTHORITY_LIB_DIR/fm-afk-contract.sh" validate >/dev/null 2>&1; then
    FM_MERGE_AUTHORITY_REASON='record-unreadable'
    return 1
  fi
  FM_MERGE_AUTHORITY='away'
  # shellcheck disable=SC2034 # Public results consumed by sourcing callers.
  FM_MERGE_AUTHORITY_REASON='away'
  return 0
}

fm_merge_authority_record_matches() {  # <record> <device> <provider> <host> <path> <number>
  local record=$1 device=$2 expected_provider=$3 expected_host=$4 expected_path=$5 expected_number=$6
  local version provider host path number authority
  fm_pr_private_file_valid "$record" 600 "$device" || return 1
  exec 8< "$record" || return 1
  IFS= read -r version <&8 || { exec 8<&-; return 1; }
  IFS= read -r provider <&8 || { exec 8<&-; return 1; }
  IFS= read -r host <&8 || { exec 8<&-; return 1; }
  IFS= read -r path <&8 || { exec 8<&-; return 1; }
  IFS= read -r number <&8 || { exec 8<&-; return 1; }
  IFS= read -r authority <&8 || { exec 8<&-; return 1; }
  if IFS= read -r _extra <&8; then
    exec 8<&-
    return 1
  fi
  exec 8<&-
  case "$authority" in away|attended|yolo|away-grant) ;; *) return 1 ;; esac
  [ "$version" = fm-merge-authority-v1 ] \
    && [ "$provider" = "$expected_provider" ] \
    && [ "$host" = "$expected_host" ] \
    && [ "$path" = "$expected_path" ] \
    && [ "$number" = "$expected_number" ] || return 1
  FM_MERGE_AUTHORITY=$authority
}

fm_merge_authority_persist() {  # <state> <task-id> <meta> <provider> <host> <path> <number> <authority>
  local state=$1 id=$2 meta=$3 provider=$4 host=$5 path=$6 number=$7 authority=$8
  local record tmp='' state_device lock status=0
  fm_pr_task_id_valid "$id" || return 1
  case "$authority" in away|attended) ;; *) return 1 ;; esac
  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  state_device=$(fm_pr_file_device "$state") || return 1
  fm_pr_metadata_identity_parse "$meta" || return 1
  [ "$FM_PR_META_PROVIDER" = "$provider" ] \
    && [ "$FM_PR_META_HOST" = "$host" ] \
    && [ "$FM_PR_META_PATH" = "$path" ] \
    && [ "$FM_PR_META_NUMBER" = "$number" ] || return 1
  record="$state/$id.merge-authority"
  lock="$record.lock"
  fm_lock_acquire_wait "$lock" || return 1
  fm_pr_regular_destination_on_device_or_absent "$record" "$state_device" || status=1
  if [ "$status" -eq 0 ]; then
    umask 077
    tmp=$(mktemp "$state/.fm-merge-authority.XXXXXX") || status=1
  fi
  if [ "$status" -eq 0 ]; then
    printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
      fm-merge-authority-v1 "$provider" "$host" "$path" "$number" "$authority" > "$tmp" \
      || status=1
  fi
  if [ "$status" -eq 0 ]; then
    chmod 0600 "$tmp" \
      && fm_merge_authority_record_matches "$tmp" "$state_device" \
        "$provider" "$host" "$path" "$number" \
      && fm_pr_regular_destination_on_device_or_absent "$record" "$state_device" \
      && mv -f -- "$tmp" "$record" \
      && fm_merge_authority_record_matches "$record" "$state_device" \
        "$provider" "$host" "$path" "$number" \
      || status=1
  fi
  [ "$status" -eq 0 ] || rm -f -- "$tmp"
  fm_lock_release "$lock" || status=1
  return "$status"
}

fm_merge_authority_read() {  # <state> <task-id> <provider> <host> <path> <number>
  local state=$1 id=$2 provider=$3 host=$4 path=$5 number=$6
  local record state_device lock status=0
  FM_MERGE_AUTHORITY='external'
  FM_MERGE_AUTHORITY_RECORD_IDENTITY=
  fm_pr_task_id_valid "$id" || return 1
  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  state_device=$(fm_pr_file_device "$state") || return 1
  record="$state/$id.merge-authority"
  lock="$record.lock"
  fm_lock_acquire_wait "$lock" || return 1
  if fm_merge_authority_record_matches "$record" "$state_device" \
      "$provider" "$host" "$path" "$number"; then
    # shellcheck disable=SC2034 # Public results consumed by sourcing callers.
    FM_MERGE_AUTHORITY_RECORD_IDENTITY=$(fm_pr_file_identity "$record") || status=1
  else
    FM_MERGE_AUTHORITY='external'
    status=1
  fi
  fm_lock_release "$lock" || status=1
  return "$status"
}

fm_merge_authority_remove_if_matches() {  # <state> <task-id> <provider> <host> <path> <number> <authority> <file-identity>
  local state=$1 id=$2 provider=$3 host=$4 path=$5 number=$6
  local authority=$7 expected_file_identity=$8 record state_device lock current_file_identity status=0
  fm_pr_task_id_valid "$id" || return 1
  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  state_device=$(fm_pr_file_device "$state") || return 1
  record="$state/$id.merge-authority"
  lock="$record.lock"
  fm_lock_acquire_wait "$lock" || return 1
  if [ -e "$record" ] || [ -L "$record" ]; then
    if fm_merge_authority_record_matches "$record" "$state_device" \
        "$provider" "$host" "$path" "$number"; then
      current_file_identity=$(fm_pr_file_identity "$record") || status=1
      if [ "$status" -eq 0 ] \
        && [ "$FM_MERGE_AUTHORITY" = "$authority" ] \
        && [ "$current_file_identity" = "$expected_file_identity" ]; then
        rm -f -- "$record" || status=1
      fi
    elif ! fm_pr_private_file_valid "$record" 600 "$state_device"; then
      status=1
    fi
  fi
  fm_lock_release "$lock" || status=1
  return "$status"
}

fm_merge_external_read() {  # <provider> <path> <number>
  local provider=$1 path=$2 number=$3 record commit parents actor at timeout
  local LC_ALL=C
  FM_MERGE_EXTERNAL_COMMIT=unknown
  FM_MERGE_EXTERNAL_PARENTS=unknown
  FM_MERGE_EXTERNAL_ACTOR=unknown
  FM_MERGE_EXTERNAL_AT=unknown
  [ "$provider" = github ] || return 0
  timeout=${FM_MERGE_EXTERNAL_READ_TIMEOUT:-10}
  case "$timeout" in ''|*[!0-9]*|0) timeout=10 ;; esac
  # shellcheck disable=SC2016  # The inner script expands after bash -c receives positional args.
  record=$(fm_run_timed "$timeout" bash -c '
    . "$1"
    fm_pr_github_read_record "$2" "$3" "$4" || exit 1
    [ "$FM_PR_RECORD_MERGED" = true ] || exit 1
    printf "%s\n" "$FM_PR_RECORD_MERGE_COMMIT" "$FM_PR_RECORD_MERGE_PARENTS" \
      "$FM_PR_RECORD_MERGE_ACTOR" "$FM_PR_RECORD_MERGED_AT"
  ' _ "$_FM_MERGE_AUTHORITY_LIB_DIR/fm-pr-lib.sh" "${path%%/*}" "${path#*/}" "$number" \
    </dev/null 2>/dev/null) || return 0
  { IFS= read -r commit; IFS= read -r parents; IFS= read -r actor; IFS= read -r at; } <<RECORD
$record
RECORD
  [[ "$commit" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] && FM_MERGE_EXTERNAL_COMMIT=$commit
  [[ "$parents" =~ ^[0-9]{1,3}$ ]] && FM_MERGE_EXTERNAL_PARENTS=$parents
  [[ "$actor" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}(\[bot\])?$ ]] && FM_MERGE_EXTERNAL_ACTOR=$actor
  [[ "$at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] && FM_MERGE_EXTERNAL_AT=$at
  return 0
}

fm_merge_external_record() {  # <state> <task-id> <provider> <host> <path> <number>
  local state=$1 id=$2 provider=$3 host=$4 path=$5 number=$6
  local meta lock tmp='' state_device line status=0 inserted=0
  fm_pr_task_id_valid "$id" || return 1
  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  state_device=$(fm_pr_file_device "$state") || return 1
  meta="$state/$id.meta"
  fm_merge_external_read "$provider" "$path" "$number"
  lock=$(fm_meta_lock_path "$meta") || return 1
  fm_lock_acquire_wait "$lock" || return 1
  fm_pr_metadata_identity_parse "$meta" \
    && [ "$FM_PR_META_PROVIDER" = "$provider" ] && [ "$FM_PR_META_HOST" = "$host" ] \
    && [ "$FM_PR_META_PATH" = "$path" ] && [ "$FM_PR_META_NUMBER" = "$number" ] \
    && [ "$(fm_pr_file_device "$meta")" = "$state_device" ] || status=1
  if [ "$status" -eq 0 ]; then
    tmp=$(umask 077; mktemp "$state/.fm-merge-external.XXXXXX") || status=1
  fi
  if [ "$status" -eq 0 ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        merge_origin=*|merge_commit=*|merge_parents=*|merge_actor=*|merged_at=*) continue ;;
        pr=*)
          if [ "$inserted" -eq 0 ]; then
            printf '%s\n' merge_origin=external \
              "merge_commit=$FM_MERGE_EXTERNAL_COMMIT" \
              "merge_parents=$FM_MERGE_EXTERNAL_PARENTS" \
              "merge_actor=$FM_MERGE_EXTERNAL_ACTOR" \
              "merged_at=$FM_MERGE_EXTERNAL_AT" >> "$tmp" || status=1
            inserted=1
          fi
          ;;
      esac
      printf '%s\n' "$line" >> "$tmp" || status=1
    done < "$meta"
  fi
  if [ "$status" -eq 0 ]; then
    chmod 0600 "$tmp" \
      && fm_pr_private_file_valid "$tmp" 600 "$state_device" \
      && fm_pr_metadata_identity_parse "$tmp" \
      && [ "$FM_PR_META_PROVIDER" = "$provider" ] && [ "$FM_PR_META_HOST" = "$host" ] \
      && [ "$FM_PR_META_PATH" = "$path" ] && [ "$FM_PR_META_NUMBER" = "$number" ] \
      && fm_pr_regular_destination_on_device_or_absent "$meta" "$state_device" \
      && mv -f -- "$tmp" "$meta" \
      || status=1
  fi
  [ "$status" -eq 0 ] || { [ -z "$tmp" ] || rm -f -- "$tmp"; }
  fm_lock_release "$lock" || status=1
  return "$status"
}
