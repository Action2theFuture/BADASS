#!/usr/bin/env bash
# =============================================================================
# BADASS shared shell helpers - sourced by scripts/p2.sh, scripts/p3.sh, tests/
# =============================================================================

# shellcheck disable=SC2034  # used by the scripts that source this file
LOGIN="junsan"
# shellcheck disable=SC2034
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Name of the running GNS3 container for a node (GNS3 names it GNS3.<node>.<uuid>).
# Prints the name, returns 1 if the node is not running.
container() {
    local c
    c=$(docker ps --format '{{.Names}}' | grep -- "$1" | head -1)
    if [ -z "$c" ]; then
        echo "[-] container for '$1' not found (is the node started in GNS3?)" >&2
        return 1
    fi
    echo "$c"
}

# dx <node> <cmd...> : run a command inside a node's container
dx() {
    local c
    c=$(container "$1") || return 1
    shift
    docker exec "$c" "$@"
}

# apply_file <node> <file> : feed a node script to the container's shell
apply_file() {
    local c
    [ -f "$2" ] || { echo "[-] missing file: $2" >&2; return 1; }
    c=$(container "$1") || return 1
    docker exec -i "$c" sh < "$2"
}
