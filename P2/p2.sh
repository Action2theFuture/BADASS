#!/usr/bin/env bash
# =============================================================================
# BADASS Part 2 helper - run from the VM, inside the repository's P2/ folder
#
#   ./p2.sh s        apply static VXLAN   (router-*_s scripts)
#   ./p2.sh g        apply multicast VXLAN (router-*_g scripts)
#   ./p2.sh status   show the current VXLAN mode of every router
#   ./p2.sh ping     ping host-2 from host-1 (overlay test)
# =============================================================================
set -euo pipefail

LOGIN="junsan"
ROUTERS=("router-${LOGIN}-1" "router-${LOGIN}-2")
HOST_SRC="host-${LOGIN}-1"
HOST_DST_IP="30.1.1.2"

cd "$(dirname "$0")"     # scripts are looked up next to this file

# Find the running GNS3 container whose name contains the node name
container() {
    local c
    c=$(docker ps --format '{{.Names}}' | grep -- "$1" | head -1 || true)
    if [ -z "$c" ]; then
        echo "[-] container for '$1' not found (is the node started in GNS3?)" >&2
        exit 1
    fi
    echo "$c"
}

apply() {
    local mode="$1"
    for r in "${ROUTERS[@]}"; do
        local script="${r}_${mode}"
        [ -f "$script" ] || { echo "[-] missing file: $script" >&2; exit 1; }
        local c; c=$(container "$r")
        docker exec -i "$c" sh < "$script"
        echo "[+] $r : applied $script"
    done
    status
}

status() {
    for r in "${ROUTERS[@]}"; do
        local c line mode; c=$(container "$r")
        line=$(docker exec "$c" sh -c \
            "ip -d link show vxlan10 2>/dev/null | grep -o 'vxlan id.*dstport [0-9]*'" || true)
        case "$line" in
            *group*)  mode="MULTICAST" ;;
            *remote*) mode="STATIC" ;;
            *)        mode="NONE (no vxlan10)" ;;
        esac
        printf '%-18s %-18s %s\n' "$r" "$mode" "$line"
    done
}

ping_test() {
    local c; c=$(container "$HOST_SRC")
    docker exec "$c" ping -c 3 "$HOST_DST_IP"
}

case "${1:-}" in
    s)      apply s ;;
    g)      apply g ;;
    status) status ;;
    ping)   ping_test ;;
    *)      echo "usage: $0 {s|g|status|ping}"; exit 1 ;;
esac
