#!/usr/bin/env bash
# =============================================================================
# BADASS test helpers - sourced by tests/run.sh
# =============================================================================
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"

CTL="python3 $REPO/scripts/gns3ctl.py"
PASS=0; FAIL=0; FAILED=()

ok()    { printf '\033[1;32m[PASS]\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko()    { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); FAILED+=("$*"); }
title() { printf '\n\033[1;34m=== %s ===\033[0m\n' "$*"; }

# check "<description>" <command...> : one-shot assertion
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else ko "$d"; fi; }

# retry <seconds> <command...> : poll every 2 s until the command succeeds
retry() {
    local t="$1"; shift; local end=$((SECONDS + t))
    until "$@" >/dev/null 2>&1; do
        [ $SECONDS -ge $end ] && return 1
        sleep 2
    done
}

# eventually <seconds> "<description>" <command...> : polled assertion
eventually() { local t="$1" d="$2"; shift 2; if retry "$t" "$@"; then ok "$d"; else ko "$d"; fi; }

vty() { dx "$1" vtysh -c "$2"; }

# lab <project> [node...] : one lab at a time (node names overlap between parts)
lab() {
    local project="$1"; shift
    $CTL down >/dev/null
    $CTL up "$project" || exit 1
    $CTL start "$project" "$@" || exit 1
}

wait_containers() { local n; for n in "$@"; do eventually 60 "container $n is running" dx "$n" true; done; }
wait_frr()        { local n; for n in "$@"; do eventually 60 "$n : FRR answers (vtysh)" vty "$n" "show version"; done; }

summary() {
    printf '\n\033[1m=== RESULT: %d passed, %d failed ===\033[0m\n' "$PASS" "$FAIL"
    local f
    for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done
}
