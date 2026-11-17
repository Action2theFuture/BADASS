#!/usr/bin/env bash
# Part 2 checks: VXLAN 10 between two routers, static then multicast.
# Sourced by tests/run.sh.

P2="$REPO/scripts/p2.sh"

p2_mode_is() { "$P2" status | grep "router-$LOGIN-$1" | grep -q "$2"; }
p2_ping()    { dx "host-$LOGIN-1" ping -c 2 -W 1 30.1.1.2; }
p2_port()    { dx "router-$LOGIN-1" ip -d link show vxlan10 | grep -q 'dstport 4789'; }
p2_group()   { dx "router-$LOGIN-1" ip maddr show dev eth0 | grep -q 239.1.1.1; }

p2_boot() {
    lab P2
    wait_containers "router-$LOGIN-1" "router-$LOGIN-2" "host-$LOGIN-1" "host-$LOGIN-2"
    local r
    for r in 1 2; do
        eventually 30 "router-$LOGIN-$r : br0 created by the startup config" dx "router-$LOGIN-$r" ip link show br0
    done
}

p2_mode() {   # $1 = s|g   $2 = STATIC|MULTICAST
    "$P2" "$1" >/dev/null 2>&1 || ko "scripts/p2.sh $1 failed"
    local r
    for r in 1 2; do check "router-$LOGIN-$r : vxlan10 mode $2" p2_mode_is "$r" "$2"; done
    check "router-$LOGIN-1 : vxlan10 dstport 4789" p2_port
    eventually 20 "host-$LOGIN-1 -> 30.1.1.2 over VXLAN ($2)" p2_ping
}

test_p2s() { title "P2 - static VXLAN";    p2_boot; p2_mode s STATIC; }
test_p2g() { title "P2 - multicast VXLAN"; p2_boot; p2_mode g MULTICAST
             check "router-$LOGIN-1 : joined group 239.1.1.1" p2_group; }
