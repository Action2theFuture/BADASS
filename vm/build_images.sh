#!/usr/bin/env bash
# =============================================================================
# BADASS : build the Docker images natively for THIS machine's architecture,
#          then check that every image referenced by P1/P2/P3 projects exists.
# Usage  : ./build_images.sh            (run from the repo root, e.g. ~/badass)
# Why    : .gns3project files only store the image NAME, never the image itself.
#          A missing name makes GNS3 try "docker pull" (-> docker login prompt).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."      # repo root

HOST_IMG="badass-host:1.0"
ROUTER_IMG="badass-router:1.0"

ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m[-] %s\033[0m\n' "$*"; }

# --- 1. build ----------------------------------------------------------------
docker build -t "$HOST_IMG"   P1/host
docker build -t "$ROUTER_IMG" P1/router

# --- 2. architecture must match the machine ----------------------------------
machine="$(dpkg --print-architecture)"            # amd64 on the cluster, arm64 on Mac
for img in "$HOST_IMG" "$ROUTER_IMG"; do
    arch="$(docker image inspect --format '{{.Architecture}}' "$img")"
    if [ "$arch" = "$machine" ]; then ok "$img : $arch"; else fail "$img : $arch (machine: $machine)"; fi
done

# --- 3. images referenced by the exported projects ---------------------------
status=0
for proj in P1/P1.gns3project P2/P2.gns3project P3/P3.gns3project; do
    if [ ! -f "$proj" ]; then fail "$proj : not found (export it from GNS3)"; status=1; continue; fi
    # a .gns3project is a zip; project.gns3 inside it is JSON
    imgs="$(python3 -I - "$proj" <<'EOF'
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    name = next(n for n in z.namelist() if n.endswith(".gns3") and "/" not in n)
    topo = json.loads(z.read(name))["topology"]
for node in topo["nodes"]:
    if node.get("node_type") == "docker":
        print(node["name"], node["properties"]["image"])
EOF
)"
    while read -r node img; do
        [ -z "${node:-}" ] && continue
        if docker image inspect "$img" >/dev/null 2>&1; then
            ok "$proj : $node -> $img"
        else
            fail "$proj : $node -> $img (MISSING)"; status=1
        fi
    done <<< "$imgs"
done

if [ "$status" -eq 0 ]; then ok "all images ready"; else fail "fix the missing items above"; fi
exit "$status"
