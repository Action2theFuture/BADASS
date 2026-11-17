# BADASS — Bgp At Doors of Autonomous Systems is Simple

GNS3 + Docker lab: FRR routers, VXLAN (static / multicast), BGP EVPN with a route reflector.
One Vagrant VM runs everything, on an Apple Silicon Mac (arm64) and on the Ubuntu cluster (amd64).

---

## Quick start

```bash
make up          # create the VM: Ubuntu 24.04 + GNS3 2.2.59 + Docker images (first run takes a while)
make test        # 50 automated checks -> "RESULT: 50 passed, 0 failed"
make gui         # VM window: log in vagrant / vagrant, run `gns3`
```

Reset everything: `make destroy && make up && make test`.

---

## Layout

```
.
├── Makefile             host entry point (make help)
├── Vagrantfile          VM definition (VirtualBox; UTM fallback on Mac)
├── P1/                  Docker images + GNS3 project
│   ├── host/Dockerfile                       Alpine host (busybox)
│   ├── router/{Dockerfile,start.sh,frr.conf,vtysh.conf}   FRR (zebra bgpd ospfd isisd)
│   └── P1.gns3project
├── P2/                  VXLAN 10 between two routers
│   ├── router-xx-{1,2}_s                 static   (remote peer)
│   ├── router-xx-{1,2}_g                 multicast (group 239.1.1.1)
│   ├── host-xx-{1,2}
│   └── P2.gns3project
├── P3/                  OSPF underlay + iBGP EVPN (route reflector) + VXLAN
│   ├── router-xx-1                       spine / route reflector
│   ├── router-xx-{2,3,4}                 leaves / VTEPs
│   ├── host-xx-{1,2,3}
│   └── P3.gns3project
├── vm/                  provisioning (run by Vagrant, re-runnable)
│   ├── setup_vm.sh                           GNS3, ubridge, docker, Xfce, keyboard, arm64 display fixes
│   └── build_images.sh                       build images for this CPU, check project references
├── scripts/             tools used inside the VM
│   ├── lib.sh                                shared helpers
│   ├── gns3ctl.py                            GNS3 REST API client (import/open/start/stop/export)
│   ├── p2.sh  p3.sh                          apply / inspect each part
└── tests/               automated checks (no GUI needed)
    ├── run.sh  assert.sh
    └── test_p1.sh  test_p2.sh  test_p3.sh
```

---

## Make targets

| Group | Targets |
|---|---|
| VM | `up` `gui` `ssh` `halt` `reload` `destroy` `provision` `images` `sync` |
| Tests | `p1` `p2s` `p2g` `p3` `test` |
| Demo P2 | `p2-s` `p2-g` `p2-status` `p2-ping` |
| Demo P3 | `p3-apply` `p3-ospf` `p3-bgp` `p3-ping` `p3-evpn` `p3-hping` |
| GNS3 | `status` `lab-down` `server` `export-p1` `export-p2` `export-p3` `export-all` |

Files are edited on the host; every test/demo target first copies them into the VM (`make sync`).
After changing a topology in the GNS3 GUI, `make export-pN` writes `PN/PN.gns3project` back to the host.

---

## What the tests prove

Each part closes the other labs, imports/opens its GNS3 project through the API, starts the nodes,
applies the part's scripts, then asserts. `eventually` checks poll until the protocol converges.

### P1 — Docker images (10)

| Check | Proves |
|---|---|
| host / router containers running | GNS3 starts both images (names match the project) |
| busybox in host and router | required tool present in both images |
| host is Alpine | lightweight host image |
| FRR answers `vtysh` | routing engine config loaded |
| zebra, bgpd, ospfd, isisd running | the four required services |

### P2 — VXLAN static (10) and multicast (11)

| Check | Proves |
|---|---|
| br0 created by the startup config | GNS3 project keeps the bridge (eth1 + vxlan10) config |
| vxlan10 mode STATIC / MULTICAST | VNI 10 with `remote` peer / `group 239.1.1.1` |
| dstport 4789 | IANA VXLAN port (Linux default is 8472) |
| host-1 → 30.1.1.2 | Layer 2 extended over the Layer 3 network |
| joined group 239.1.1.1 (multicast) | IGMP join: peers discovered through the group |

### P3 — BGP EVPN (19), routers first, hosts after

| Check | Proves |
|---|---|
| RR has 3 OSPF Full neighbors | underlay link-state database synchronized |
| 9 loopback pings | /32 loopbacks reachable (BGP source and VTEP addresses) |
| RR has 3 Established EVPN peers | iBGP L2VPN EVPN sessions via dynamic neighbors |
| 12 type-3 lines, 0 type-2 | each VTEP advertises VNI 10; no MAC routes without hosts |
| 6 host-to-host pings | overlay works across all leaves |
| ≥ 12 type-2 lines | host MACs advertised once hosts exist |
| remote MACs on a leaf | data plane (`nolearning`) filled by the control plane |

---

## Not covered by the tests (show by hand)

| Item | How |
|---|---|
| Topology and node names (`*-junsan-*`) | `make gui` → `gns3` → open P1 / P2 / P3 |
| Image content | node → Console → `ps`, `busybox`, `vtysh` |
| Running configuration | `vagrant ssh -c '~/badass/scripts/p3.sh run router-junsan-1 "show running-config"'` |
| VXLAN packets | link → Start capture: outer UDP 4789, VNI 10, inner ICMP |
| Multicast discovery | first ARP sent to 239.1.1.1, IGMPv3 report to 224.0.0.22 |
| BGP UPDATE | TCP 179, MP_REACH_NLRI AFI 25 / SAFI 70, route types 2 and 3 |
| Ingress replication | first packet to an unknown MAC copied to every type-3 VTEP |

### P3 manual demo order

```bash
# GNS3: start the 4 routers only
make p3-apply && make p3-ospf && make p3-bgp        # type 3 only
# GNS3: start the 3 hosts
vagrant ssh -c '~/badass/scripts/p3.sh apply host-junsan-1 host-junsan-2 host-junsan-3'
make p3-hping && make p3-bgp && make p3-evpn        # type 2 appears, remote MACs
```
