#!/usr/bin/env bash
# Part 1 checks: the two Docker images run in GNS3 with the required content.
# Sourced by tests/run.sh.

# FRR daemons run as /usr/lib/frr/<name>; pgrep -x does not match them in this image
daemon_up() { dx "$1" sh -c "ps -o args | grep -v grep | grep -q '^/usr/lib/frr/$2 '"; }

test_p1() {
    title "P1 - docker images in GNS3"
    lab P1
    local h="host-$LOGIN-1" r="router-$LOGIN-2" d
    wait_containers "$h" "$r"
    check "$h : busybox present"       dx "$h" busybox true
    check "$h : image is Alpine"       dx "$h" grep -qi alpine /etc/os-release
    wait_frr "$r"
    for d in zebra bgpd ospfd isisd; do
        check "$r : daemon $d running" daemon_up "$r" "$d"
    done
    check "$r : busybox present"       dx "$r" busybox true
}
