#!/usr/bin/env bash
# =============================================================================
# BADASS Part 2 helper - run inside the VM (from anywhere)
#
#   scripts/p2.sh s        apply static VXLAN    (P2/router-*_s)
#   scripts/p2.sh g        apply multicast VXLAN (P2/router-*_g)
#   scripts/p2.sh status   current VXLAN mode of every router
#   scripts/p2.sh ping     ping host-2 from host-1 (overlay test)
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

NODES="$REPO/P2"
ROUTERS=("router-${LOGIN}-1" "router-${LOGIN}-2")
HOST_SRC="host-${LOGIN}-1"
HOST_DST_IP="30.1.1.2"

apply() {
    local mode="$1" r
    for r in "${ROUTERS[@]}"; do
        apply_file "$r" "$NODES/${r}_${mode}"
        echo "[+] $r : applied P2/${r}_${mode}"
    done
    status
}

status() {
    local r line mode
    for r in "${ROUTERS[@]}"; do
        line=$(dx "$r" sh -c "ip -d link show vxlan10 2>/dev/null | grep -o 'vxlan id.*dstport [0-9]*'" || true)
        case "$line" in
            *group*)  mode="MULTICAST" ;;
            *remote*) mode="STATIC" ;;
            *)        mode="NONE (no vxlan10)" ;;
        esac
        printf '%-18s %-18s %s\n' "$r" "$mode" "$line"
    done
}

case "${1:-}" in
    s)      apply s ;;
    g)      apply g ;;
    status) status ;;
    ping)   dx "$HOST_SRC" ping -c 3 "$HOST_DST_IP" ;;
    *)      echo "usage: $0 {s|g|status|ping}"; exit 1 ;;
esac
