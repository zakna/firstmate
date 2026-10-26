#!/usr/bin/env bash
# fm-pi-durable.sh - owner of the opt-in pi-durable pilot runtime: installing
# its pinned dependencies into one home, checking that install, and launching
# the host (bin/pi-durable/host.mjs) under the process name Firstmate's
# liveness probes recognize.
#
# Usage:
#   fm-pi-durable.sh install [--state <dir>]
#       Install the exact dependency tree pinned by bin/pi-durable/package-lock.json
#       into <state>/pi-durable-runtime with `npm ci --ignore-scripts`, then
#       verify it loads. Re-running converges: an install whose lock already
#       matches is left alone.
#   fm-pi-durable.sh check [--state <dir>]
#       Exit 0 only when Node meets the package's floor and the home's install
#       matches the tracked lockfile and loads. Prints the reason otherwise.
#   fm-pi-durable.sh launch --state <dir> -- <host arguments>
#       Refuse unless `check` passes, then exec Node on the host with argv[0]
#       set to `pi-durable`, passing --runtime for this home's install.
#
# <state> defaults to $FM_STATE_OVERRIDE, else $FM_HOME/state, else this
# checkout's state/. The install is per home on purpose: a home never borrows
# another home's or the global Pi installation. Nothing here changes the pi or
# pi-signed adapters, and nothing is installed globally.
#
# Exit codes: 0 ok; 1 refused or failed; 2 usage.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$SCRIPT_DIR/pi-durable"
NODE_FLOOR=22.19.0

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

CMD=${1:-}
case "$CMD" in install | check | launch) shift ;; -h | --help) usage ;; *) usage ;; esac
STATE=
while [ "$#" -gt 0 ]; do
  case "$1" in
  --state)
    [ "$#" -ge 2 ] || usage
    STATE=$2
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *) usage ;;
  esac
done
if [ -z "$STATE" ]; then
  STATE=${FM_STATE_OVERRIDE:-${FM_HOME:-$(cd "$SCRIPT_DIR/.." && pwd)}/state}
fi
[ -d "$STATE" ] || {
  echo "error: state dir not found: $STATE" >&2
  exit 1
}
RUNTIME="$STATE/pi-durable-runtime"

lock_digest() {  # <lockfile>
  shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
}

version_at_least() {  # <have> <floor>
  local have=$1 floor=$2 a b i
  IFS=. read -r -a a <<<"$have"
  IFS=. read -r -a b <<<"$floor"
  for i in 0 1 2; do
    [ "${a[$i]:-0}" -gt "${b[$i]:-0}" ] && return 0
    [ "${a[$i]:-0}" -lt "${b[$i]:-0}" ] && return 1
  done
  return 0
}

node_ok() {
  local node version
  node=$(command -v node) || {
    echo "pi-durable: node is not on PATH; Node >= $NODE_FLOOR is required" >&2
    return 1
  }
  version=$("$node" --version 2>/dev/null) || version=
  version=${version#v}
  case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *)
    echo "pi-durable: cannot read the Node version from $node" >&2
    return 1
    ;;
  esac
  version_at_least "$version" "$NODE_FLOOR" || {
    echo "pi-durable: Node $version is below the required $NODE_FLOOR" >&2
    return 1
  }
}

install_ok() {
  local want have
  want=$(lock_digest "$PKG_DIR/package-lock.json")
  have=$(cat "$RUNTIME/.fm-lock-sha256" 2>/dev/null) || have=
  [ -n "$want" ] && [ "$want" = "$have" ] || {
    echo "pi-durable: no install matching bin/pi-durable/package-lock.json in $RUNTIME; run bin/fm-pi-durable.sh install" >&2
    return 1
  }
  node "$PKG_DIR/host.mjs" --check --runtime "$RUNTIME" >/dev/null || {
    echo "pi-durable: the install in $RUNTIME does not load; rerun bin/fm-pi-durable.sh install" >&2
    return 1
  }
}

case "$CMD" in
check)
  node_ok && install_ok && echo "pi-durable: ready ($RUNTIME)"
  ;;
install)
  node_ok || exit 1
  if install_ok 2>/dev/null; then
    echo "pi-durable: already installed ($RUNTIME)"
    exit 0
  fi
  command -v npm >/dev/null || {
    echo "error: npm is not on PATH" >&2
    exit 1
  }
  mkdir -p "$RUNTIME" && chmod 700 "$RUNTIME" || exit 1
  rm -f "$RUNTIME/.fm-lock-sha256"
  cp "$PKG_DIR/package.json" "$PKG_DIR/package-lock.json" "$PKG_DIR/load.mjs" "$RUNTIME/" || exit 1
  (cd "$RUNTIME" && npm ci --ignore-scripts --no-audit --no-fund --loglevel=error) || {
    echo "error: npm ci failed in $RUNTIME" >&2
    exit 1
  }
  lock_digest "$PKG_DIR/package-lock.json" >"$RUNTIME/.fm-lock-sha256"
  install_ok || exit 1
  echo "pi-durable: installed ($RUNTIME)"
  ;;
launch)
  node_ok || exit 1
  install_ok || exit 1
  # argv[0] is the identity the liveness probes read on both platforms:
  # macOS reports it as the process name, Linux exposes it as argv[0].
  exec -a pi-durable node "$PKG_DIR/host.mjs" --runtime "$RUNTIME" "$@"
  ;;
esac
