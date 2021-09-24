# to make sure the gateway node is created before the other nodes, we
# have to force a --no-parallel execution.
ENV['VAGRANT_NO_PARALLEL'] = 'yes'

# the network prefix we use in this environment.
# NB this must be a /24 prefixed network.
$network_address_prefix = '10.10.10'
$public_bridge_name = nil

# configure the virtual machines network to use an already configured bridge.
# NB this is used for connecting to the external world (alike the one
#    described at https://github.com/rgl/pxe-raspberrypi-vagrant).
# NB set to nil to for using private networking.
#$network_address_prefix = '10.3.0'
#$public_bridge_name = 'br-rpi'

require 'fileutils'

def config_pxe_client_network(config, mac)
  if $public_bridge_name
    config.vm.network :public_network,
      dev: $public_bridge_name,
      mode: 'bridge',
      type: 'bridge',
      mac: mac,
      ip: "#{$network_address_prefix}.0",
      auto_config: false
  else
    config.vm.network :private_network,
      mac: mac,
      ip: "#{$network_address_prefix}.0",
      auto_config: false
  end
end

Vagrant.configure('2') do |config|
  config.vm.box = 'ubuntu-20.04-amd64'

  config.vm.provider :libvirt do |lv, config|
    lv.memory = 256
    lv.cpus = 2
    lv.cpu_mode = 'host-passthrough'
    # lv.nested = true
    lv.keymap = 'pt'
    config.vm.synced_folder '.', '/vagrant', type: 'nfs'
  end

  config.vm.provider :virtualbox do |vb|
    vb.linked_clone = true
    vb.memory = 256
    vb.cpus = 2
    vb.customize ['modifyvm', :id, '--cableconnected1', 'on']
  end

  config.vm.define :gateway do |config|
    config.vm.hostname = 'gateway'
    if $public_bridge_name
      config.vm.network :public_network,
        dev: $public_bridge_name,
        mode: 'bridge',
        type: 'bridge',
        mac: '080027000000',
        ip: "#{$network_address_prefix}.2"
    else
      config.vm.network :private_network,
        mac: '080027000000',
        ip: "#{$network_address_prefix}.2",
        libvirt__dhcp_enabled: false,
        libvirt__forward_mode: 'none'
    end
    config.vm.provider :libvirt do |lv, config|
      lv.memory = 512
    end
    config.vm.provider :virtualbox do |vb, config|
      vb.memory = 512
    end
    config.vm.provision :shell, path: 'gateway.sh', args: [$network_address_prefix]
    config.trigger.before :up do
      [
        '../debian-live-builder-vagrant/live-image-amd64.hybrid.iso',
        '../linuxkit-vagrant/shared/sshd-kernel',
        '../linuxkit-vagrant/shared/sshd-initrd.img',
        '../windows-pe-vagrant/tmp/winpe-amd64.iso',
      ].each do |source|
        destination = "tmp/#{File.basename(source)}"
        if File.exist?(source) && (!File.exist?(destination) || File.mtime(source) > File.mtime(destination))
          puts "Copying #{source} to #{destination}..."
          FileUtils.mkdir_p('tmp')
          FileUtils.cp(source, destination)
        end
      end
    end
  end

  config.vm.define :debian_live do |config|
    config.vm.box = 'empty'
    config_pxe_client_network(config, '080027000001')
    config.vm.provider :libvirt do |lv, config|
      lv.memory = 2048
      lv.boot 'network'
      # set some BIOS settings that will help us identify this particular machine.
      #
      #   QEMU                | Linux
      #   --------------------+----------------------------------------------
      #   type=1,manufacturer | /sys/devices/virtual/dmi/id/sys_vendor
      #   type=1,product      | /sys/devices/virtual/dmi/id/product_name
      #   type=1,version      | /sys/devices/virtual/dmi/id/product_version
      #   type=1,serial       | /sys/devices/virtual/dmi/id/product_serial
      #   type=1,sku          | dmidecode
      #   type=1,uuid         | /sys/devices/virtual/dmi/id/product_uuid
      #   type=3,manufacturer | /sys/devices/virtual/dmi/id/chassis_vendor
      #   type=3,family       | /sys/devices/virtual/dmi/id/chassis_type
      #   type=3,version      | /sys/devices/virtual/dmi/id/chassis_version
      #   type=3,serial       | /sys/devices/virtual/dmi/id/chassis_serial
      #   type=3,asset        | /sys/devices/virtual/dmi/id/chassis_asset_tag
      [
        'type=1,manufacturer=your vendor name here',
        'type=1,product=your product name here',
        'type=1,version=your product version here',
        'type=1,serial=your product serial number here',
        'type=1,sku=your product SKU here',
        'type=1,uuid=00000000-0000-4000-8000-000000000001',
        'type=3,manufacturer=your chassis vendor name here',
        #'type=3,family=1', # TODO why this does not work on qemu from ubuntu 18.04?
        'type=3,version=your chassis version here',
        'type=3,serial=your chassis serial number here',
        'type=3,asset=your chassis asset tag here',
      ].each do |value|
        lv.qemuargs :value => '-smbios'
        lv.qemuargs :value => value
      end
      config.vm.synced_folder '.', '/vagrant', disabled: true
    end
    config.vm.provider :virtualbox do |vb, config|
      # make sure this vm has enough memory to load the root fs into memory.
      vb.memory = 2048

      # let vagrant known that the guest does not have the guest additions nor a functional vboxsf or shared folders.
      vb.check_guest_additions = false
      vb.functional_vboxsf = false
      config.vm.synced_folder '.', '/vagrant', disabled: true

      # configure for PXE boot.
      vb.customize ['modifyvm', :id, '--boot1', 'net']
      vb.customize ['modifyvm', :id, '--boot2', 'disk']
      vb.customize ['modifyvm', :id, '--biospxedebug', 'on']
      vb.customize ['modifyvm', :id, '--cableconnected2', 'on']
      vb.customize ['modifyvm', :id, '--nicbootprio2', '1']
      vb.customize ['modifyvm', :id, "--nictype2", '82540EM'] # Must be an Intel card (as-of VB 5.1 we cannot Intel PXE boot from a virtio-net card).

      # set some BIOS settings that will help us identify this particular machine.
      #
      #   VirtualBox          | Linux
      #   --------------------+----------------------------------------------
      #   DmiSystemVendor     | /sys/devices/virtual/dmi/id/sys_vendor
      #   DmiSystemProduct    | /sys/devices/virtual/dmi/id/product_name
      #   DmiSystemVersion    | /sys/devices/virtual/dmi/id/product_version
      #   DmiSystemSerial     | /sys/devices/virtual/dmi/id/product_serial
      #   DmiSystemSKU        | dmidecode
      #   DmiSystemUuid       | /sys/devices/virtual/dmi/id/product_uuid
      #   DmiChassisVendor    | /sys/devices/virtual/dmi/id/chassis_vendor
      #   DmiChassisType      | /sys/devices/virtual/dmi/id/chassis_type
      #   DmiChassisVersion   | /sys/devices/virtual/dmi/id/chassis_version
      #   DmiChassisSerial    | /sys/devices/virtual/dmi/id/chassis_serial
      #   DmiChassisAssetTag  | /sys/devices/virtual/dmi/id/chassis_asset_tag
      #
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/DevPcBios.cpp
      # See https://www.virtualbox.org/browser/vbox/trunk/src/VBox/Devices/PC/BIOS
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/BIOS/bios.c
      #
      # NB the VirtualBox BIOS is based on Plex86/Boch/QEMU.
      # NB dump extradata with VBoxManage getextradata $(cat .vagrant/machines/debianlive/virtualbox/id)
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor',    'your vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct',   'your product name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion',   'your product version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial',    'your product serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSKU',       'your product SKU here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemUuid',      '00000000-0000-4000-8000-000000000001']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor',   'your chassis vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisType',     '1']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVersion',  'your chassis version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisSerial',   'your chassis serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisAssetTag', 'your chassis asset tag here']
    end

    # make sure we use the gateway machine as this machine default gateway.
    # NB the 10.0.2/24 network is the default VirtualBox NAT network, which we must replace with our gateway.
    config.vm.provision :shell, run: 'always', inline: "ip route list 0/0 | xargs ip route del; ip route add default via #{$network_address_prefix}.2"

    # dump some useful information.
    config.vm.provision :shell, inline: '''
        set -x
        uname -a
        cat /etc/network/interfaces
        ip addr
        ip route
        ip route get 8.8.8.8
        cat /proc/cmdline
        cat /sys/devices/virtual/dmi/id/sys_vendor
        cat /sys/devices/virtual/dmi/id/product_name
        cat /sys/devices/virtual/dmi/id/product_version
        cat /sys/devices/virtual/dmi/id/product_serial
        cat /sys/devices/virtual/dmi/id/product_uuid
        cat /sys/devices/virtual/dmi/id/chassis_vendor
        cat /sys/devices/virtual/dmi/id/chassis_type
        cat /sys/devices/virtual/dmi/id/chassis_version
        cat /sys/devices/virtual/dmi/id/chassis_serial
        cat /sys/devices/virtual/dmi/id/chassis_asset_tag
      '''
  end

  config.vm.define :linuxkit do |config|
    config.vm.box = 'empty'
    config.ssh.username = 'root'
    config.ssh.shell = '/bin/sh'
    config_pxe_client_network(config, '080027000002')
    config.vm.provider :libvirt do |lv, config|
      lv.memory = 2048
      lv.boot 'network'
      # set some BIOS settings that will help us identify this particular machine.
      #
      #   QEMU                | Linux
      #   --------------------+----------------------------------------------
      #   type=1,manufacturer | /sys/devices/virtual/dmi/id/sys_vendor
      #   type=1,product      | /sys/devices/virtual/dmi/id/product_name
      #   type=1,version      | /sys/devices/virtual/dmi/id/product_version
      #   type=1,serial       | /sys/devices/virtual/dmi/id/product_serial
      #   type=1,sku          | dmidecode
      #   type=1,uuid         | /sys/devices/virtual/dmi/id/product_uuid
      #   type=3,manufacturer | /sys/devices/virtual/dmi/id/chassis_vendor
      #   type=3,family       | /sys/devices/virtual/dmi/id/chassis_type
      #   type=3,version      | /sys/devices/virtual/dmi/id/chassis_version
      #   type=3,serial       | /sys/devices/virtual/dmi/id/chassis_serial
      #   type=3,asset        | /sys/devices/virtual/dmi/id/chassis_asset_tag
      [
        'type=1,manufacturer=your vendor name here',
        'type=1,product=your product name here',
        'type=1,version=your product version here',
        'type=1,serial=your product serial number here',
        'type=1,sku=your product SKU here',
        'type=1,uuid=00000000-0000-4000-8000-000000000002',
        'type=3,manufacturer=your chassis vendor name here',
        #'type=3,family=1', # TODO why this does not work on qemu from ubuntu 18.04?
        'type=3,version=your chassis version here',
        'type=3,serial=your chassis serial number here',
        'type=3,asset=your chassis asset tag here',
      ].each do |value|
        lv.qemuargs :value => '-smbios'
        lv.qemuargs :value => value
      end
      config.vm.synced_folder '.', '/vagrant', disabled: true
    end
    config.vm.provider :virtualbox do |vb, config|
      # make sure this vm has enough memory to load the root fs into memory.
      vb.memory = 2048

      # let vagrant known that the guest does not have the guest additions nor a functional vboxsf or shared folders.
      vb.check_guest_additions = false
      vb.functional_vboxsf = false
      config.vm.synced_folder '.', '/vagrant', disabled: true

      # configure for PXE boot.
      vb.customize ['modifyvm', :id, '--boot1', 'net']
      vb.customize ['modifyvm', :id, '--boot2', 'disk']
      vb.customize ['modifyvm', :id, '--biospxedebug', 'on']
      vb.customize ['modifyvm', :id, '--cableconnected2', 'on']
      vb.customize ['modifyvm', :id, '--nicbootprio2', '1']
      vb.customize ['modifyvm', :id, "--nictype2", '82540EM'] # Must be an Intel card (as-of VB 5.1 we cannot Intel PXE boot from a virtio-net card).

      # set some BIOS settings that will help us identify this particular machine.
      #
      #   VirtualBox          | Linux
      #   --------------------+----------------------------------------------
      #   DmiSystemVendor     | /sys/devices/virtual/dmi/id/sys_vendor
      #   DmiSystemProduct    | /sys/devices/virtual/dmi/id/product_name
      #   DmiSystemVersion    | /sys/devices/virtual/dmi/id/product_version
      #   DmiSystemSerial     | /sys/devices/virtual/dmi/id/product_serial
      #   DmiSystemSKU        | dmidecode
      #   DmiSystemUuid       | /sys/devices/virtual/dmi/id/product_uuid
      #   DmiChassisVendor    | /sys/devices/virtual/dmi/id/chassis_vendor
      #   DmiChassisType      | /sys/devices/virtual/dmi/id/chassis_type
      #   DmiChassisVersion   | /sys/devices/virtual/dmi/id/chassis_version
      #   DmiChassisSerial    | /sys/devices/virtual/dmi/id/chassis_serial
      #   DmiChassisAssetTag  | /sys/devices/virtual/dmi/id/chassis_asset_tag
      #
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/DevPcBios.cpp
      # See https://www.virtualbox.org/browser/vbox/trunk/src/VBox/Devices/PC/BIOS
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/BIOS/bios.c
      #
      # NB the VirtualBox BIOS is based on Plex86/Boch/QEMU.
      # NB dump extradata with VBoxManage getextradata $(cat .vagrant/machines/debianlive/virtualbox/id)
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor',    'your vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct',   'your product name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion',   'your product version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial',    'your product serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSKU',       'your product SKU here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemUuid',      '00000000-0000-4000-8000-000000000002']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor',   'your chassis vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisType',     '1']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVersion',  'your chassis version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisSerial',   'your chassis serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisAssetTag', 'your chassis asset tag here']
    end
  end

  config.vm.define :tcl do |config|
    config.vm.box = 'empty'
    config_pxe_client_network(config, '080027000003')
    config.ssh.insert_key = false
    config.ssh.shell = '/bin/sh' # TCL uses BusyBox ash instead of bash.
    config.vm.provider :libvirt do |lv, config|
      lv.boot 'network'
      # set some BIOS settings that will help us identify this particular machine.
      #
      #   QEMU                | Linux
      #   --------------------+----------------------------------------------
      #   type=1,manufacturer | /sys/devices/virtual/dmi/id/sys_vendor
      #   type=1,product      | /sys/devices/virtual/dmi/id/product_name
      #   type=1,version      | /sys/devices/virtual/dmi/id/product_version
      #   type=1,serial       | /sys/devices/virtual/dmi/id/product_serial
      #   type=1,sku          | dmidecode
      #   type=1,uuid         | /sys/devices/virtual/dmi/id/product_uuid
      #   type=3,manufacturer | /sys/devices/virtual/dmi/id/chassis_vendor
      #   type=3,family       | /sys/devices/virtual/dmi/id/chassis_type
      #   type=3,version      | /sys/devices/virtual/dmi/id/chassis_version
      #   type=3,serial       | /sys/devices/virtual/dmi/id/chassis_serial
      #   type=3,asset        | /sys/devices/virtual/dmi/id/chassis_asset_tag
      [
        'type=1,manufacturer=your vendor name here',
        'type=1,product=your product name here',
        'type=1,version=your product version here',
        'type=1,serial=your product serial number here',
        'type=1,sku=your product SKU here',
        'type=1,uuid=00000000-0000-4000-8000-000000000003',
        'type=3,manufacturer=your chassis vendor name here',
        #'type=3,family=1', # TODO why this does not work on qemu from ubuntu 18.04?
        'type=3,version=your chassis version here',
        'type=3,serial=your chassis serial number here',
        'type=3,asset=your chassis asset tag here',
      ].each do |value|
        lv.qemuargs :value => '-smbios'
        lv.qemuargs :value => value
      end
      config.vm.synced_folder '.', '/vagrant', disabled: true
    end
    config.vm.provider :virtualbox do |vb, config|
      # let vagrant known that the guest does not have the guest additions nor a functional vboxsf or shared folders.
      vb.check_guest_additions = false
      vb.functional_vboxsf = false
      config.vm.synced_folder '.', '/vagrant', disabled: true

      # configure for PXE boot.
      vb.customize ['modifyvm', :id, '--boot1', 'net']
      vb.customize ['modifyvm', :id, '--boot2', 'disk']
      vb.customize ['modifyvm', :id, '--biospxedebug', 'on']
      vb.customize ['modifyvm', :id, '--cableconnected2', 'on']
      vb.customize ['modifyvm', :id, '--nicbootprio2', '1']
      vb.customize ['modifyvm', :id, "--nictype2", '82540EM'] # Must be an Intel card (as-of VB 5.1 we cannot Intel PXE boot from a virtio-net card).

      # set some BIOS settings that will help us identify this particular machine.
      #
      #   VirtualBox          | Linux
      #   --------------------+----------------------------------------------
      #   DmiSystemVendor     | /sys/devices/virtual/dmi/id/sys_vendor
      #   DmiSystemProduct    | /sys/devices/virtual/dmi/id/product_name
      #   DmiSystemVersion    | /sys/devices/virtual/dmi/id/product_version
      #   DmiSystemSerial     | /sys/devices/virtual/dmi/id/product_serial
      #   DmiSystemSKU        | dmidecode
      #   DmiSystemUuid       | /sys/devices/virtual/dmi/id/product_uuid
      #   DmiChassisVendor    | /sys/devices/virtual/dmi/id/chassis_vendor
      #   DmiChassisType      | /sys/devices/virtual/dmi/id/chassis_type
      #   DmiChassisVersion   | /sys/devices/virtual/dmi/id/chassis_version
      #   DmiChassisSerial    | /sys/devices/virtual/dmi/id/chassis_serial
      #   DmiChassisAssetTag  | /sys/devices/virtual/dmi/id/chassis_asset_tag
      #
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/DevPcBios.cpp
      # See https://www.virtualbox.org/browser/vbox/trunk/src/VBox/Devices/PC/BIOS
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/BIOS/bios.c
      #
      # NB the VirtualBox BIOS is based on Plex86/Boch/QEMU.
      # NB dump extradata with VBoxManage getextradata $(cat .vagrant/machines/client/virtualbox/id)
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor',    'your vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct',   'your product name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion',   'your product version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial',    'your product serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSKU',       'your product SKU here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemUuid',      '00000000-0000-4000-8000-000000000003']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor',   'your chassis vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisType',     '1']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVersion',  'your chassis version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisSerial',   'your chassis serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisAssetTag', 'your chassis asset tag here']
    end

    # make sure we use the gateway machine as this machine default gateway.
    # NB the 10.0.2/24 network is the default VirtualBox NAT network, we remove its default route.
    #config.vm.provision :shell, run: 'always', inline: 'ip route del $(ip route list 0/0 | grep 10\\.0\\.2\\.)'
    config.vm.provision :shell, run: 'always', inline: "set -eux; i=$(route -n | grep -E '^0\\.0\\.0\\.0\\s+10\\.0\\.2\\.' | sed -E 's,.+(eth.+),\\1,'); route del default $i"

    # dump some useful information.
    config.vm.provision :shell, inline: '''
        set -x
        uname -a
        route -n
        #ip route
        #ip route get 8.8.8.8
        cat /proc/cmdline
        cat /sys/devices/virtual/dmi/id/sys_vendor
        cat /sys/devices/virtual/dmi/id/product_name
        cat /sys/devices/virtual/dmi/id/product_version
        cat /sys/devices/virtual/dmi/id/product_serial
        cat /sys/devices/virtual/dmi/id/product_uuid
        cat /sys/devices/virtual/dmi/id/chassis_vendor
        cat /sys/devices/virtual/dmi/id/chassis_type
        cat /sys/devices/virtual/dmi/id/chassis_version
        cat /sys/devices/virtual/dmi/id/chassis_serial
        cat /sys/devices/virtual/dmi/id/chassis_asset_tag
      '''
  end

  config.vm.define :winpe do |config|
    config.vm.box = 'empty'
    config_pxe_client_network(config, '080027000004')
    config.vm.provider :libvirt do |lv, config|
      lv.memory = 2048
      lv.boot 'network'
      # set some BIOS settings that will help us identify this particular machine.
      #
      #   QEMU                | Linux
      #   --------------------+----------------------------------------------
      #   type=1,manufacturer | /sys/devices/virtual/dmi/id/sys_vendor
      #   type=1,product      | /sys/devices/virtual/dmi/id/product_name
      #   type=1,version      | /sys/devices/virtual/dmi/id/product_version
      #   type=1,serial       | /sys/devices/virtual/dmi/id/product_serial
      #   type=1,sku          | dmidecode
      #   type=1,uuid         | /sys/devices/virtual/dmi/id/product_uuid
      #   type=3,manufacturer | /sys/devices/virtual/dmi/id/chassis_vendor
      #   type=3,family       | /sys/devices/virtual/dmi/id/chassis_type
      #   type=3,version      | /sys/devices/virtual/dmi/id/chassis_version
      #   type=3,serial       | /sys/devices/virtual/dmi/id/chassis_serial
      #   type=3,asset        | /sys/devices/virtual/dmi/id/chassis_asset_tag
      [
        'type=1,manufacturer=your vendor name here',
        'type=1,product=your product name here',
        'type=1,version=your product version here',
        'type=1,serial=your product serial number here',
        'type=1,sku=your product SKU here',
        'type=1,uuid=00000000-0000-4000-8000-000000000004',
        'type=3,manufacturer=your chassis vendor name here',
        #'type=3,family=1', # TODO why this does not work on qemu from ubuntu 18.04?
        'type=3,version=your chassis version here',
        'type=3,serial=your chassis serial number here',
        'type=3,asset=your chassis asset tag here',
      ].each do |value|
        lv.qemuargs :value => '-smbios'
        lv.qemuargs :value => value
      end
      lv.mgmt_attach = false
      config.vm.box = nil
    end
    config.vm.provider :virtualbox do |vb, config|
      # make sure this vm has enough memory to load the root fs into memory.
      vb.memory = 2048

      # let vagrant known that the guest does not have the guest additions nor a functional vboxsf or shared folders.
      vb.check_guest_additions = false
      vb.functional_vboxsf = false
      config.vm.synced_folder '.', '/vagrant', disabled: true

      # configure for PXE boot.
      vb.customize ['modifyvm', :id, '--boot1', 'net']
      vb.customize ['modifyvm', :id, '--boot2', 'disk']
      vb.customize ['modifyvm', :id, '--biospxedebug', 'on']
      vb.customize ['modifyvm', :id, '--cableconnected2', 'on']
      vb.customize ['modifyvm', :id, '--nicbootprio2', '1']
      vb.customize ['modifyvm', :id, "--nictype2", '82540EM'] # Must be an Intel card (as-of VB 5.1 we cannot Intel PXE boot from a virtio-net card).

      # set some BIOS settings that will help us identify this particular machine.
      #
      #   VirtualBox          | Windows WMI
      #   --------------------+----------------------------------------------
      #   DmiSystemVendor     | Win32_ComputerSystemProduct.Vendor
      #   DmiSystemProduct    | Win32_ComputerSystemProduct.Name
      #   DmiSystemVersion    | Win32_ComputerSystemProduct.Version
      #   DmiSystemSerial     | Win32_ComputerSystemProduct.IdentifyingNumber
      #   DmiSystemSKU        | TODO where do we read this from?
      #   DmiSystemUuid       | Win32_ComputerSystemProduct.UUID
      #   DmiChassisVendor    | TODO where do we read this from?
      #   DmiChassisType      | TODO where do we read this from?
      #   DmiChassisVersion   | TODO where do we read this from?
      #   DmiChassisSerial    | TODO where do we read this from?
      #   DmiChassisAssetTag  | TODO where do we read this from?
      #
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/DevPcBios.cpp
      # See https://www.virtualbox.org/browser/vbox/trunk/src/VBox/Devices/PC/BIOS
      # See https://www.virtualbox.org/svn/vbox/trunk/src/VBox/Devices/PC/BIOS/bios.c
      #
      # NB the VirtualBox BIOS is based on Plex86/Boch/QEMU.
      # NB dump extradata with VBoxManage getextradata $(cat .vagrant/machines/winpe/virtualbox/id)
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVendor',    'your vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemProduct',   'your product name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemVersion',   'your product version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSerial',    'your product serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemSKU',       'your product SKU here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiSystemUuid',      '00000000-0000-4000-8000-000000000004']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVendor',   'your chassis vendor name here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisType',     '1']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisVersion',  'your chassis version here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisSerial',   'your chassis serial number here']
      vb.customize ['setextradata', :id, 'VBoxInternal/Devices/pcbios/0/Config/DmiChassisAssetTag', 'your chassis asset tag here']
    end
  end
end
