# -*- mode: ruby -*-
# BADASS lab VM - one Vagrantfile for Mac M4 (arm64) and the 42 cluster (amd64)
#   vagrant up                  -> VirtualBox (box arch picked from host CPU)
#   vagrant up --provider=utm   -> Mac fallback (vagrant plugin install vagrant_utm)

VM_NAME = "badass-junsan"
VM_CPUS = (ENV["BADASS_CPUS"] || 2).to_i
VM_MEM  = (ENV["BADASS_MEM"]  || 4096).to_i      # MB

Vagrant.configure("2") do |config|
  config.vm.box      = "bento/ubuntu-24.04"
  config.vm.hostname = "junsan"

  # repo on the host, copied one-way into the VM: `vagrant rsync` after edits
  config.vm.synced_folder ".", "/vagrant", disabled: true
  config.vm.synced_folder ".", "/home/vagrant/badass", type: "rsync",
    rsync__exclude: [".vagrant/", ".git/", "*.tgz", "*.log"]

  config.vm.provider "virtualbox" do |vb|
    vb.name   = VM_NAME
    vb.gui    = true            # GNS3 needs a desktop window
    vb.cpus   = VM_CPUS
    vb.memory = VM_MEM
  end

  config.vm.provider "utm" do |utm, override|
    override.vm.box = "utm/ubuntu-24.04"
    utm.name   = VM_NAME
    utm.cpus   = VM_CPUS
    utm.memory = VM_MEM
  end

  # run as user 'vagrant' (setup_vm.sh refuses root and uses sudo itself)
  config.vm.provision "setup", type: "shell", privileged: false, inline: <<-SHELL
    set -e
    cd ~/badass
    bash setup_vm.sh
  SHELL

  # 'sg docker': the docker group just added is not active in this session yet
  config.vm.provision "images", type: "shell", privileged: false, inline: <<-SHELL
    set -e
    cd ~/badass
    sg docker -c ./build_images.sh
  SHELL

  # reboot once: groups, keyboard layout and the Xfce session take effect
  config.vm.provision "reboot", type: "shell", privileged: true, reboot: true,
    inline: "echo 'provisioning done, rebooting'"
end
