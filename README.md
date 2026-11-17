# BADASS — Bgp At Doors of Autonomous Systems is Simple

GNS3 + Docker lab: FRR routers, VXLAN (static / multicast), BGP EVPN with a route reflector.
One Vagrant VM runs everything, on an Apple Silicon Mac (arm64) and on the Ubuntu cluster (amd64).

## Layout

```
.
├── Makefile             host entry point (make help)
├── Vagrantfile          VM: Ubuntu 24.04, VirtualBox (or UTM on Mac), GNS3 2.2.59
├── P1/                  part 1 deliverables: Docker images + GNS3 project
│   ├── host/Dockerfile                 Alpine host (busybox)
│   ├── router/{Dockerfile,start.sh,frr.conf,vtysh.conf}   FRR router (zebra bgpd ospfd isisd)
│   └── P1.gns3project
├── P2/                  part 2 deliverables: VXLAN 10 between 2 routers
│   ├── router-junsan-{1,2}_s           static VXLAN (remote)
│   ├── router-junsan-{1,2}_g           multicast VXLAN (group 239.1.1.1)
│   ├── host-junsan-{1,2}
│   └── P2.gns3project
├── P3/                  part 3 deliverables: OSPF + iBGP EVPN (RR) + VXLAN
│   ├── router-junsan-1                 spine / route reflector
│   ├── router-junsan-{2,3,4}           leaves / VTEPs
│   ├── host-junsan-{1,2,3}
│   └── P3.gns3project
├── vm/                  VM provisioning (run by Vagrant, re-runnable by hand)
│   ├── setup_vm.sh                     GNS3, ubridge, docker, Xfce, keyboard, arm64 display fixes
│   └── build_images.sh                 build images for this CPU + check project references
├── scripts/             tools used inside the VM
│   ├── lib.sh                          shared helpers (container lookup, docker exec)
│   ├── gns3ctl.py                      GNS3 REST API client: import/open/start/stop/export
│   ├── p2.sh                           apply/inspect part 2
│   └── p3.sh                           apply/inspect part 3
└── tests/               automated checks (GUI not needed)
    ├── run.sh                          dispatcher + summary, exit code = failures
    ├── assert.sh                       check / eventually / lab helpers
    └── test_p1.sh test_p2.sh test_p3.sh
```

## Quick start

```bash
make up          # first time: box download + provisioning (+ reboot)
make test        # P1, P2 static, P2 multicast, P3 -> "RESULT: N passed, 0 failed"
make gui         # VM window: login vagrant / vagrant, then run `gns3`
```

## Demo commands (host)

| Part | Commands |
|---|---|
| P2 | `make p2-s` / `make p2-g` / `make p2-status` / `make p2-ping` |
| P3 | `make p3-apply` / `make p3-ospf` / `make p3-bgp` / `make p3-ping` / `make p3-evpn` / `make p3-hping` |

Edit files on the host, then `make sync` (or any test target) copies them into the VM.
After changing a topology in the GNS3 GUI: `make export-p3` writes `P3/P3.gns3project` back to the host.
