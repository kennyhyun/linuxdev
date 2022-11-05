# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.env.enable # plugin vagrant-env
  
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  config.vm.box = ENV['VM_BOX'] || "bento/debian-10.10"
  config.vm.box_version = "202107.08.0"

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"
  forwarded_ports = (ENV['FORWARDED_PORTS'] || "443").split(',')
  forwarded_ports.each { |forwarded_port|
    port = forwarded_port.to_i
    config.vm.network "forwarded_port", guest: port, host: port, host_ip: "0.0.0.0"
  }

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network "private_network", ip: "192.168.33.10"
  private_networks = (ENV['PRIVATE_NETWORKS'] || "192.168.99.123").split(',')
  private_networks.each { |private_network|
    config.vm.network "private_network", ip: private_network
  }

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  # config.vm.synced_folder "../data", "/vagrant_data"
  config.vm.synced_folder "./data", "/mnt/data"
  dynamic_synced_folders = (ENV['HOST_PATHS'] || "~/Projects").split(',')
  dynamic_synced_folders.each { |host_path|
    abs_path = File.expand_path(host_path)
    # windows drive path conversion C:/ => /c/
    abs_path = abs_path.sub(/^([a-zA-Z]):\//){ '/' + $1.downcase + '/' }
    # use only for debug: vagrant ssh-config will have this too
    # puts "Adding synced_folder: " + host_path + ':' + abs_path
    config.vm.synced_folder host_path, abs_path, create: true
  }

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  # config.vm.provider "virtualbox" do |vb|
  #   # Display the VirtualBox GUI when booting the machine
  #   vb.gui = true
  #
  #   # Customize the amount of memory on the VM:
  #   vb.memory = "1024"
  # end
  #
  # View the documentation for the provider you are using for more
  # information on available options.
  machine_name = ENV['NAME'] || "linuxdev"
  config.vm.provider "virtualbox" do |vb|
    vb.name = machine_name
    vb.gui = false
    vb.memory = ENV['MEMORY'] || 1024
    vb.cpus = ENV['CPUS'] || 2

    docker_disk_size = ENV['DOCKER_DISK_SIZE_GB']
    disk_filename = (ENV['VMDISK_LOCATION'] || "") + "#{machine_name}.docker.#{docker_disk_size}.vdi"
    if docker_disk_size && !File.exist?(disk_filename)
      vb.customize ['createhd', '--filename', disk_filename, '--variant', 'Fixed', '--size', docker_disk_size.to_i * 1024]
      vb.customize ['storageattach', :id,  '--storagectl', 'SATA Controller', '--port', 1, '--type', 'hdd', '--medium', disk_filename]
    end
    project_disk_size = ENV['PROJECT_DISK_SIZE_GB']
    disk_filename = (ENV['VMDISK_LOCATION'] || "") + "#{machine_name}.projects.#{project_disk_size}.vdi"
    if project_disk_size && !File.exist?(disk_filename)
      vb.customize ['createhd', '--filename', disk_filename, '--variant', 'Fixed', '--size', project_disk_size.to_i * 1024]
      vb.customize ['storageattach', :id,  '--storagectl', 'SATA Controller', '--port', 2, '--type', 'hdd', '--medium', disk_filename]
    end

  end

  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
  # config.vm.provision "shell", inline: <<-SHELL
  #   apt-get update
  #   apt-get install -y apache2
  # SHELL
  #config.vm.provision "file", source: "./.vagrant/machines/default/virtualbox/private_key", destination: "$HOME/.ssh/id_rsa"
  config.vm.provision "shell", inline: "echo '. /vagrant/config/env_var.sh' > /etc/profile.d/env_var.sh", run: "always"
  config.vm.provision "docker",
    images: ["stanback/alpine-samba", "docker/dockerfile:1.0-experimental"]
end
