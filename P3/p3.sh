#!/usr/bin/env bash
# =============================================================================
# BADASS Part 3 helper - run from the VM, inside the repository's P3/ folder
#
#   ./p3.sh apply [node...]   run each node's script inside its container
#                             (default: all routers)
#   ./p3.sh ospf              OSPF neighbors + learned routes on every router
#   ./p3.sh bgp               BGP EVPN summary + routes on every router
#   ./p3.sh run <node> <cmd>  run one vtysh command on one router
#   ./p3.sh ping              loopback reachability test from every leaf
#   ./p3.sh evpn              VNI + MAC table (local / remote) on every leaf
#   ./p3.sh hping             ping between all hosts (overlay test)
# =============================================================================
set -euo pipefail

LOGIN="junsan"
ROUTERS=("router-${LOGIN}-1" "router-${LOGIN}-2" "router-${LOGIN}-3" "router-${LOGIN}-4")
LOOPBACKS=("1.1.1.1" "1.1.1.2" "1.1.1.3" "1.1.1.4")
HOSTS=("host-${LOGIN}-1" "host-${LOGIN}-2" "host-${LOGIN}-3")
HOST_IPS=("20.1.1.1" "20.1.1.2" "20.1.1.3")

cd "$(dirname "$0")"     # node scripts are looked up next to this file

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
    local nodes=("$@") n c
    [ ${#nodes[@]} -eq 0 ] && nodes=("${ROUTERS[@]}")
    for n in "${nodes[@]}"; do
        [ -f "$n" ] || { echo "[-] missing file: $n" >&2; exit 1; }
        c=$(container "$n")
        docker exec -i "$c" sh < "$n"
        echo "[+] $n : applied"
    done
}

vty_all() {
    local n c cmd
    for n in "${ROUTERS[@]}"; do
        c=$(container "$n")
        echo "==================== $n"
        for cmd in "$@"; do docker exec "$c" vtysh -c "$cmd"; done
    done
}

ping_loopbacks() {
    local i n c src dst
    for i in 1 2 3; do
        n="${ROUTERS[$i]}"; src="${LOOPBACKS[$i]}"; c=$(container "$n")
        for dst in "${LOOPBACKS[@]}"; do
            [ "$dst" = "$src" ] && continue
            if docker exec "$c" ping -c 1 -W 1 -I "$src" "$dst" >/dev/null 2>&1; then
                echo "[+] $n : $src -> $dst OK"
            else
                echo "[-] $n : $src -> $dst FAIL"
            fi
        done
    done
}

evpn_leaves() {
    local i n c
    for i in 1 2 3; do
        n="${ROUTERS[$i]}"; c=$(container "$n")
        echo "==================== $n"
        docker exec "$c" vtysh -c "show evpn vni" -c "show evpn mac vni 10"
    done
}

ping_hosts() {
    local i n c dst
    for i in 0 1 2; do
        n="${HOSTS[$i]}"; c=$(container "$n")
        for dst in "${HOST_IPS[@]}"; do
            [ "$dst" = "${HOST_IPS[$i]}" ] && continue
            if docker exec "$c" ping -c 2 -W 1 "$dst" >/dev/null 2>&1; then
                echo "[+] $n : ${HOST_IPS[$i]} -> $dst OK"
            else
                echo "[-] $n : ${HOST_IPS[$i]} -> $dst FAIL"
            fi
        done
    done
}

case "${1:-}" in
    apply) shift; apply "$@" ;;
    ospf)  vty_all "show ip ospf neighbor" "show ip route ospf" ;;
    bgp)   vty_all "show bgp l2vpn evpn summary" "show bgp l2vpn evpn" ;;
    run)   [ $# -ge 3 ] || { echo "usage: $0 run <node> <vtysh command>"; exit 1; }
           c=$(container "$2"); docker exec "$c" vtysh -c "$3" ;;
    ping)  ping_loopbacks ;;
    evpn)  evpn_leaves ;;
    hping) ping_hosts ;;
    *)     echo "usage: $0 {apply [node...]|ospf|bgp|run <node> <cmd>|ping|evpn|hping}"; exit 1 ;;
esac
