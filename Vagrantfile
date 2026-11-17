# -*- mode: ruby -*-
# =============================================================================
# BADASS lab VM - one Vagrantfile for both machines
#   * Mac M4 (arm64)      : vagrant up                    (VirtualBox >= 7.2, arm64 box)
#                           vagrant up --provider=utm     (fallback: UTM + vagrant_utm plugin)
#   * 42 cluster (amd64)  : vagrant up                    (VirtualBox, amd64 box)
# Vagrant >= 2.4 picks the box architecture matching the host CPU automatically.
# Provisioning = the same scripts used by hand: setup_vm.sh + build_images.sh
# =============================================================================

VM_NAME = "badass-junsan"
VM_CPUS = (ENV["BADASS_CPUS"] || 2).to_i
VM_MEM  = (ENV["BADASS_MEM"]  || 4096).to_i      # MB

Vagrant.configure("2") do |config|
  config.vm.box      = "bento/ubuntu-24.04"
  config.vm.hostname = "junsan"

  # Repo lives on the host; copied one-way into the VM (works with every provider).
  # After editing on the host: `vagrant rsync` (or keep `vagrant rsync-auto` running).
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.synced_folder ".", "/home/vagrant/badass", type: "rsync",
    rsync__exclude: [".vagrant/", ".git/", "*.tgz"]

  # --- VirtualBox: default provider on both the Mac and the cluster ----------
  config.vm.provider "virtualbox" do |vb|
    vb.name   = VM_NAME
    vb.gui    = true            # GNS3 needs a desktop window (lightdm -> Xfce)
    vb.cpus   = VM_CPUS
    vb.memory = VM_MEM
    # Apple Silicon: arm64 VMs use QemuRamFB (fixed-size framebuffer). If the
    # VirtualBox window asks the guest to follow its size, the guest switches to
    # e.g. 1284x840_vbox and the screen goes black. Keep a fixed 1280x800.
    vb.customize ["setextradata", :id, "GUI/AutoresizeGuest", "false"]
  end

  # --- UTM: Mac-only fallback (vagrant plugin install vagrant_utm) -----------
  config.vm.provider "utm" do |utm, override|
    override.vm.box = "utm/ubuntu-24.04"
    utm.name   = VM_NAME
    utm.cpus   = VM_CPUS
    utm.memory = VM_MEM
  end

  # --- Provisioning (first `vagrant up`, or `vagrant provision`) -------------
  # privileged: false -> runs as user 'vagrant' (setup_vm.sh refuses root,
  # it uses sudo itself; the vagrant user has passwordless sudo).
  config.vm.provision "setup", type: "shell", privileged: false, inline: <<-SHELL
    set -e
    cd ~/badass
    bash setup_vm.sh
  SHELL

  # 'sg docker' : the docker group added above is not active in this session yet.
  config.vm.provision "images", type: "shell", privileged: false, inline: <<-SHELL
    set -e
    cd ~/badass
    sg docker -c ./build_images.sh
  SHELL

  # Reboot once so groups, keyboard layout and the Xfce session take effect.
  config.vm.provision "reboot", type: "shell", privileged: true, reboot: true,
    inline: "echo 'provisioning done, rebooting'"
end
