#!/usr/bin/env bash
# Part 3 checks: OSPF underlay, iBGP EVPN with a route reflector, VXLAN overlay.
# Routers first (type 3 only), hosts after (type 2 appears). Sourced by tests/run.sh.

P3="$REPO/scripts/p3.sh"
ROUTERS3=("router-$LOGIN-1" "router-$LOGIN-2" "router-$LOGIN-3" "router-$LOGIN-4")
HOSTS3=("host-$LOGIN-1" "host-$LOGIN-2" "host-$LOGIN-3")

ospf_full()  { [ "$(vty "router-$LOGIN-1" 'show ip ospf neighbor' | grep -c Full)" -eq 3 ]; }
bgp_estab()  { [ "$(vty "router-$LOGIN-1" 'show bgp l2vpn evpn summary json' | grep -Ec '"state": *"Established"')" -eq 3 ]; }
evpn_count() { "$P3" bgp | grep -c "\[$1\]:\[0\]"; }
type3_ok()   { [ "$(evpn_count 3)" -eq 12 ]; }     # 3 VTEPs seen by 4 routers
type2_none() { [ "$(evpn_count 2)" -eq 0 ]; }
type2_ok()   { [ "$(evpn_count 2)" -ge 12 ]; }     # 3 host MACs seen by 4 routers
loops_ok()   { ! "$P3" ping | grep -q FAIL; }
hosts_ok()   { local o; o=$("$P3" hping) && ! grep -q FAIL <<<"$o" && [ "$(grep -c OK <<<"$o")" -eq 6 ]; }
remote_mac() { vty "router-$LOGIN-2" 'show evpn mac vni 10' | grep -q remote; }

test_p3() {
    title "P3 - BGP EVPN (routers first, hosts after)"
    lab P3 "${ROUTERS3[@]}"
    wait_containers "${ROUTERS3[@]}"
    wait_frr "${ROUTERS3[@]}"
    "$P3" apply >/dev/null 2>&1 || ko "scripts/p3.sh apply (routers) failed"

    eventually 90 "OSPF : RR has 3 Full neighbors"          ospf_full
    eventually 30 "underlay : 9 loopback pings OK"          loops_ok
    eventually 90 "BGP : RR has 3 Established EVPN peers"   bgp_estab
    eventually 60 "EVPN : type 3 (IMET) routes, 12 lines"   type3_ok
    check         "EVPN : no type 2 before hosts start"     type2_none

    $CTL start P3 "${HOSTS3[@]}" >/dev/null || exit 1
    wait_containers "${HOSTS3[@]}"
    "$P3" apply "${HOSTS3[@]}" >/dev/null 2>&1 || ko "scripts/p3.sh apply (hosts) failed"

    eventually 40 "overlay : 6 host-to-host pings OK"       hosts_ok
    eventually 30 "EVPN : type 2 (MAC) routes, >= 12 lines" type2_ok
    check         "router-$LOGIN-2 : remote MACs learned via BGP" remote_mac
}
