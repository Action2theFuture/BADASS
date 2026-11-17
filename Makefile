# ===========================================================================
#  BADASS - everything is driven from here (run on the HOST, next to the Vagrantfile)
#
#  VM        make up | gui | ssh | halt | reload | destroy | provision | images
#  Tests     make p1 | p2s | p2g | p3 | test        (GUI not needed, exit code = failures)
#  Demo      make p2-s | p2-g | p2-status | p2-ping
#            make p3-apply | p3-ospf | p3-bgp | p3-ping | p3-evpn | p3-hping
#  GNS3      make status | lab-down | server | export-p1 | export-p2 | export-p3 | export-all
#
#  Inside the VM:  ~/badass/tests/run.sh p3      ~/badass/scripts/p3.sh bgp
# ===========================================================================
VM       ?= badass-junsan
VAGRANT  ?= vagrant
GUEST    := /home/vagrant/badass
# macOS ssh forwards LC_* (ko_KR.UTF-8) which the guest does not have
export LC_ALL := C.UTF-8
export LANG   := C.UTF-8

RUN      = $(VAGRANT) ssh -c
CTL      = python3 $(GUEST)/scripts/gns3ctl.py
SSHCFG   = .vagrant/ssh-config

.PHONY: help up gui ssh halt destroy reload provision images sync \
        p1 p2s p2g p2 p2m p3 test status lab-down server \
        export-p1 export-p2 export-p3 export-all

help:
	@sed -n '2,11p' Makefile

# ------------------------------------------------------------------- VM --
up:
	$(VAGRANT) up

gui:
	@if VBoxManage showvminfo $(VM) --machinereadable | grep -q 'VMState="running"'; then \
		echo "[*] $(VM) is already running: select it in the VirtualBox app and press Show"; \
		(open -a VirtualBox 2>/dev/null || (VirtualBox >/dev/null 2>&1 &)); \
	else VBoxManage startvm $(VM) --type gui; fi

ssh:
	$(VAGRANT) ssh

halt:
	$(VAGRANT) halt

reload:
	$(VAGRANT) reload

destroy:
	$(VAGRANT) destroy -f

## re-run every provisioner (vm/setup_vm.sh is idempotent)
provision: sync
	$(VAGRANT) provision

## rebuild only the docker images inside the VM
images: sync
	$(VAGRANT) provision --provision-with images

## copy host edits into the VM (one-way, host -> VM)
sync:
	@$(VAGRANT) status --machine-readable | grep -q ',state,running' || $(VAGRANT) up
	@$(VAGRANT) rsync >/dev/null && echo "[+] host -> VM sync done"

# ---------------------------------------------------------------- tests --
p1 p2s p2g p3: sync
	$(RUN) '$(GUEST)/tests/run.sh $@'

p2: p2s
p2m: p2g

test: sync
	$(RUN) '$(GUEST)/tests/run.sh all'

# ----------------------------------------------------------------- demo --
# make p2-s  -> scripts/p2.sh s      make p3-bgp -> scripts/p3.sh bgp
p2-%: sync
	$(RUN) '$(GUEST)/scripts/p2.sh $*'

p3-%: sync
	$(RUN) '$(GUEST)/scripts/p3.sh $*'

# ----------------------------------------------------------------- GNS3 --
server:
	$(RUN) '$(CTL) server'

status:
	$(RUN) '$(CTL) status'

lab-down:
	$(RUN) '$(CTL) down'

# export inside the VM, then copy the binary back with scp (vagrant ssh -c would corrupt it)
$(SSHCFG):
	$(VAGRANT) ssh-config > $@

# static pattern rule: works with .PHONY (plain pattern rules do not)
export-p1 export-p2 export-p3: export-p%: $(SSHCFG)
	$(RUN) '$(CTL) export P$* /tmp/P$*.gns3project'
	scp -q -F $(SSHCFG) default:/tmp/P$*.gns3project P$*/P$*.gns3project
	@echo "[+] P$*/P$*.gns3project updated on the host (commit it)"

export-all: export-p1 export-p2 export-p3
