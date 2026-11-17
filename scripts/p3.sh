#!/usr/bin/env bash
# =============================================================================
# BADASS Part 3 helper - run inside the VM (from anywhere)
#
#   scripts/p3.sh apply [node...]   run P3/<node> inside its container (default: all routers)
#   scripts/p3.sh ospf              OSPF neighbors + learned routes on every router
#   scripts/p3.sh bgp               BGP EVPN summary + routes on every router
#   scripts/p3.sh run <node> <cmd>  one vtysh command on one router
#   scripts/p3.sh ping              loopback reachability from every leaf
#   scripts/p3.sh evpn              VNI + MAC table (local / remote) on every leaf
#   scripts/p3.sh hping             ping between all hosts (overlay test)
# =============================================================================
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

NODES="$REPO/P3"
ROUTERS=("router-${LOGIN}-1" "router-${LOGIN}-2" "router-${LOGIN}-3" "router-${LOGIN}-4")
LOOPBACKS=("1.1.1.1" "1.1.1.2" "1.1.1.3" "1.1.1.4")
HOSTS=("host-${LOGIN}-1" "host-${LOGIN}-2" "host-${LOGIN}-3")
HOST_IPS=("20.1.1.1" "20.1.1.2" "20.1.1.3")

apply() {
    local nodes=("$@") n
    [ ${#nodes[@]} -eq 0 ] && nodes=("${ROUTERS[@]}")
    for n in "${nodes[@]}"; do
        apply_file "$n" "$NODES/$n"
        echo "[+] $n : applied"
    done
}

vty_all() {
    local n cmd
    for n in "${ROUTERS[@]}"; do
        echo "==================== $n"
        for cmd in "$@"; do dx "$n" vtysh -c "$cmd"; done
    done
}

ping_loopbacks() {
    local i n src dst
    for i in 1 2 3; do
        n="${ROUTERS[$i]}"; src="${LOOPBACKS[$i]}"
        for dst in "${LOOPBACKS[@]}"; do
            [ "$dst" = "$src" ] && continue
            if dx "$n" ping -c 1 -W 1 -I "$src" "$dst" >/dev/null 2>&1; then
                echo "[+] $n : $src -> $dst OK"
            else
                echo "[-] $n : $src -> $dst FAIL"
            fi
        done
    done
}

evpn_leaves() {
    local i
    for i in 1 2 3; do
        echo "==================== ${ROUTERS[$i]}"
        dx "${ROUTERS[$i]}" vtysh -c "show evpn vni" -c "show evpn mac vni 10"
    done
}

ping_hosts() {
    local i dst
    for i in 0 1 2; do
        for dst in "${HOST_IPS[@]}"; do
            [ "$dst" = "${HOST_IPS[$i]}" ] && continue
            if dx "${HOSTS[$i]}" ping -c 2 -W 1 "$dst" >/dev/null 2>&1; then
                echo "[+] ${HOSTS[$i]} : ${HOST_IPS[$i]} -> $dst OK"
            else
                echo "[-] ${HOSTS[$i]} : ${HOST_IPS[$i]} -> $dst FAIL"
            fi
        done
    done
}

case "${1:-}" in
    apply) shift; apply "$@" ;;
    ospf)  vty_all "show ip ospf neighbor" "show ip route ospf" ;;
    bgp)   vty_all "show bgp l2vpn evpn summary" "show bgp l2vpn evpn" ;;
    run)   [ $# -ge 3 ] || { echo "usage: $0 run <node> <vtysh command>"; exit 1; }
           dx "$2" vtysh -c "$3" ;;
    ping)  ping_loopbacks ;;
    evpn)  evpn_leaves ;;
    hping) ping_hosts ;;
    *)     echo "usage: $0 {apply [node...]|ospf|bgp|run <node> <cmd>|ping|evpn|hping}"; exit 1 ;;
esac
