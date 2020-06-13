#!/bin/bash
set -eux

network_address_prefix="${1:-10.10.10}"; shift || true

echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/env_keep_apt
chmod 440 /etc/sudoers.d/env_keep_apt
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y


#
# install tcpdump for being able to capture network traffic.

apt-get install -y tcpdump


#
# install vim.

apt-get install -y --no-install-recommends vim
cat >/etc/vim/vimrc.local <<'EOF'
syntax on
set background=dark
set esckeys
set ruler
set laststatus=2
set nobackup
EOF


#
# provision the TFTP server.
# see https://help.ubuntu.com/community/Installation/QuickNetboot
# see https://help.ubuntu.com/community/PXEInstallServer
# see https://wiki.archlinux.org/index.php/PXE

apt-get install -y --no-install-recommends atftp atftpd
# NB if you need to troubleshoot edit the configuration by adding --verbose=7 --trace
sed -i -E 's,(USE_INETD=).+,\1false,' /etc/default/atftpd
systemctl restart atftpd


#
# get pxelinux.
# see http://www.syslinux.org/wiki/index.php?title=PXELINUX
# see http://www.syslinux.org/wiki/index.php?title=Config

apt-get install -y xz-utils
SYSLINUX=syslinux-6.03
wget -q -P $HOME https://www.kernel.org/pub/linux/utils/boot/syslinux/$SYSLINUX.tar.xz
tar xf $HOME/$SYSLINUX.tar.xz -C $HOME


#
# get wimboot.
# see http://ipxe.org/wimboot

WIMBOOT=wimboot-2.6.0-signed
WIMBOOT_URL=http://git.ipxe.org/releases/wimboot/$WIMBOOT.tar.bz2
WIMBOOT_SHA=f4f9304da9193cbe4584b47c65e0eaf0cc2af0d2052d1e47e8a089445b7ac1c3
wget -q -P $HOME $WIMBOOT_URL
if [ "$(sha256sum $HOME/$WIMBOOT.tar.bz2 | awk '{print $1}')" != "$WIMBOOT_SHA" ]; then
    echo "downloaded $WIMBOOT_URL failed the checksum verification"
    exit 1
fi
tar xf $HOME/$WIMBOOT.tar.bz2 -C $HOME


#
# get Debian Live (assumed to be built from https://github.com/rgl/debian-live-builder-vagrant).

if [ -f /vagrant/tmp/live-image-amd64.hybrid.iso ]; then
mkdir -p /srv/tftp/debian-live/pxelinux.cfg
pushd /srv/tftp/debian-live
# configure pxelinux to boot debian-live.
# see https://manpages.debian.org/stretch/live-boot-doc/live-boot.7.en.html
cp $HOME/$SYSLINUX/bios/com32/elflink/ldlinux/ldlinux.c32 .
cp $HOME/$SYSLINUX/bios/core/lpxelinux.0 .
cat >pxelinux.cfg/default <<'EOF'
default linux
label linux
kernel vmlinuz
initrd initrd.img
# boot from an http downloaded filesystem.squashfs:
append net.ifnames=0 boot=live fetch=http://$network_address_prefix.2/debian-live/filesystem.squashfs components username=vagrant
EOF
apt-get install -y --no-install-recommends p7zip-full
# make linux, initrd and the root filesystem available from tftp and http.
7z x -otmp /vagrant/tmp/live-image-amd64.hybrid.iso live/{vmlinuz,initrd.img,filesystem.squashfs}
mv tmp/live/* .
rm -rf tmp
popd
# test with: atftp --get --local-file lpxelinux.0 --remote-file debian-live/lpxelinux.0 127.0.0.1
fi


#
# get LinuxKit (assumed to be built from https://github.com/rgl/linuxkit-vagrant).

if [ -f /vagrant/tmp/sshd-kernel ]; then
mkdir -p /srv/tftp/linuxkit/pxelinux.cfg
pushd /srv/tftp/linuxkit
cp $HOME/$SYSLINUX/bios/com32/elflink/ldlinux/ldlinux.c32 .
cp $HOME/$SYSLINUX/bios/core/lpxelinux.0 .
cat >pxelinux.cfg/default <<'EOF'
default linux
label linux
kernel vmlinuz
initrd initrd.img
append console=tty0
EOF
cp /vagrant/tmp/sshd-kernel vmlinuz
cp /vagrant/tmp/sshd-initrd.img initrd.img
popd
# test with: atftp --get --local-file lpxelinux.0 --remote-file linuxkit/lpxelinux.0 127.0.0.1
fi


#
# get Tiny Core Linux.

apt-get install -y --no-install-recommends advancecomp
apt-get install -y --no-install-recommends squashfs-tools

mkdir /srv/tftp/tcl && pushd /srv/tftp/tcl
TCL_REPOSITORY=http://tinycorelinux.net/11.x/x86_64
# corepure64.gz contains all the files on rootfs64 and modules64 merged together in a single smaller file.
#wget -q $TCL_REPOSITORY/release/distribution_files/{vmlinuz64,corepure64.gz,rootfs64.gz,modules64.gz}
wget -q $TCL_REPOSITORY/release/distribution_files/{vmlinuz64,corepure64.gz}
#zcat corepure64.gz | cpio -vt # list
#zcat corepure64.gz | (mkdir corepure64 && cd corepure64 && sudo cpio -idv --no-absolute-filenames) # extract
# create an extra initrd image that leaves the guest in a state that can be used by vagrant.
# TODO also load .dep files and get all the dependencies. e.g. http://tinycorelinux.net/11.x/x86_64/tcz/openssh.tcz.dep
#      NB when it returns 404 there are no dependencies.
mkdir -p provision/opt
TCE='openssh openssl-1.1.1'
for tce in $TCE; do
  wget -q $TCL_REPOSITORY/tcz/$tce.tcz
  sudo unsquashfs -n -f -d provision $tce.tcz
done
pushd provision
# see etc/init.d/tc-config
# NB if you want to load an extension from the internet, do it like:
#       while ! sudo -u tc tce-load -wi openssh; do echo waiting for network; sleep 1; done
cat>opt/bootlocal.sh<<'EOF'
#!/bin/sh
set -eu
find /usr/local/tce.installed -type f -exec sh -c {} \;
sed -i -E 's,^(tc:)[^:]*(.+),\1*\2,' /etc/shadow && cp -fp /etc/shadow /etc/shadow-
echo vagrant:vagrant | chpasswd -m
install -d -o vagrant -g staff -m 700 /home/vagrant/.ssh
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key'>/home/vagrant/.ssh/authorized_keys
mv /usr/local/etc/ssh/sshd_config.orig /usr/local/etc/ssh/sshd_config
/usr/local/etc/init.d/openssh start
EOF
chmod +x opt/*.sh
popd
sudo chown -R 0:0 provision # NB uig:gid in your host are probably not the same as the ones inside the guest, so its probably better to restrict yourself to using 0:0.
(cd provision && sudo find . | sudo cpio -o -H newc | gzip -2) >provision.gz
advdef -z4 provision.gz
rm -rf provision *.tcz
#zcat provision.gz | cpio --list --numeric-uid-gid --verbose
# configure pxelinux to boot tcl.
mkdir pxelinux.cfg
cp $HOME/$SYSLINUX/bios/com32/elflink/ldlinux/ldlinux.c32 .
cp $HOME/$SYSLINUX/bios/core/lpxelinux.0 .
cat>pxelinux.cfg/default<<EOF
default linux
label linux
kernel vmlinuz64
initrd corepure64.gz,provision.gz
append base norestore noswap noautologin user=vagrant
EOF
# test with: atftp --get --local-file lpxelinux.0 --remote-file tcl/lpxelinux.0 127.0.0.1
popd


#
# get winpe (assumed to be built from https://github.com/rgl/windows-pe-vagrant).
# see http://ipxe.org/wimboot
# see http://ipxe.org/howto/winpe
# see http://www.syslinux.org/wiki/index.php?title=Linux.c32

if [ -f /vagrant/tmp/winpe-amd64.iso ]; then
mkdir -p /srv/tftp/winpe/pxelinux.cfg
pushd /srv/tftp/winpe
cp $HOME/$SYSLINUX/bios/com32/elflink/ldlinux/ldlinux.c32 .
cp $HOME/$SYSLINUX/bios/com32/modules/linux.c32 .
cp $HOME/$SYSLINUX/bios/com32/lib/libcom32.c32 .
cp $HOME/$SYSLINUX/bios/core/lpxelinux.0 .
cp $HOME/$WIMBOOT/wimboot .
7z x -otmp /vagrant/tmp/winpe-amd64.iso bootmgr Boot/{BCD,boot.sdi} sources/boot.wim
find tmp -type f -exec mv {} $PWD \;
rm -rf tmp
cat >pxelinux.cfg/default <<'EOF'
default winpe
label winpe
com32 linux.c32
append wimboot initrdfile=bootmgr,BCD,boot.sdi,boot.wim
EOF
popd
# test with: atftp --get --local-file lpxelinux.0 --remote-file winpe/lpxelinux.0 127.0.0.1
fi


#
# provision the HTTP server.

apt-get install -y --no-install-recommends nginx
rm /etc/nginx/sites-enabled/default
cat >/etc/nginx/sites-available/boot.conf <<EOF
server {
  listen $network_address_prefix.2:80;
  root /srv/tftp;
  autoindex on;
  access_log /var/log/nginx/boot.access.log;
}
EOF
ln -s ../sites-available/boot.conf /etc/nginx/sites-enabled
systemctl restart nginx


#
# provision the DHCP server.
# see http://www.syslinux.org/wiki/index.php?title=PXELINUX

apt-get install -y --no-install-recommends isc-dhcp-server
cat >/etc/dhcp/dhcpd.conf <<EOF
option space pxelinux;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
site-option-space "pxelinux";
if exists dhcp-parameter-request-list {
  # Always send the PXELINUX options (specified in hexadecimal)
  option dhcp-parameter-request-list = concat(option dhcp-parameter-request-list,d1,d2,d3);
}
authoritative;
default-lease-time 300;
max-lease-time 300;
option domain-name-servers 8.8.8.8, 8.8.4.4;
option subnet-mask 255.255.255.0;
option routers $network_address_prefix.2;
subnet $network_address_prefix.0 netmask 255.255.255.0 {
  range $network_address_prefix.100 $network_address_prefix.254;
}

# NB we reuse the VirtualBox MAC 08:00:27 (Cadmus Computer Systems) vendor.
#    see https://www.wireshark.org/tools/oui-lookup.html

host debian-live {
  hardware ethernet 08:00:27:00:00:01;
  option pxelinux.pathprefix "http://$network_address_prefix.2/debian-live/";
  filename "debian-live/lpxelinux.0";
}

host linuxkit {
  hardware ethernet 08:00:27:00:00:02;
  option pxelinux.pathprefix "http://$network_address_prefix.2/linuxkit/";
  filename "linuxkit/lpxelinux.0";
}

host tcl {
  hardware ethernet 08:00:27:00:00:03;
  option pxelinux.pathprefix "http://$network_address_prefix.2/tcl/";
  filename "tcl/lpxelinux.0";
}

host winpe {
  hardware ethernet 08:00:27:00:00:04;
  option pxelinux.pathprefix "http://$network_address_prefix.2/winpe/";
  filename "winpe/lpxelinux.0";
}

# run dhcp-event when a lease changes state.
# see dhcpd.conf(5) and dhcp-eval(5)
on commit {
  set client_ip = binary-to-ascii(10, 8, ".", leased-address);
  set client_hw = binary-to-ascii(16, 8, ":", substring(hardware, 1, 6));
  execute("/usr/local/sbin/dhcp-event", "commit", client_ip, client_hw, host-decl-name);
}
on release {
  set client_ip = binary-to-ascii(10, 8, ".", leased-address);
  set client_hw = binary-to-ascii(16, 8, ":", substring(hardware, 1, 6));
  execute("/usr/local/sbin/dhcp-event", "release", client_ip, client_hw, host-decl-name);
}
on expiry {
  set client_ip = binary-to-ascii(10, 8, ".", leased-address);
  set client_hw = binary-to-ascii(16, 8, ":", substring(hardware, 1, 6));
  execute("/usr/local/sbin/dhcp-event", "expiry", client_ip, client_hw, host-decl-name);
}
EOF
sed -i -E 's,^(INTERFACES=).*,\1eth1,' /etc/default/isc-dhcp-server
cat >/usr/local/sbin/dhcp-event <<'EOF'
#!/bin/bash
# this is called when a lease changes state.
# NB you can see these log entries with journalctl -t dhcp-event
logger -t dhcp-event "argv: $*"
for e in $(env); do
  logger -t dhcp-event "env: $e"
done
EOF
chmod +x /usr/local/sbin/dhcp-event
systemctl restart isc-dhcp-server


#
# setup NAT.
# see https://help.ubuntu.com/community/IptablesHowTo

apt-get install -y iptables iptables-persistent

# enable IPv4 forwarding.
sysctl net.ipv4.ip_forward=1
sed -i -E 's,^\s*#?\s*(net.ipv4.ip_forward=).+,\11,g' /etc/sysctl.conf

# NAT through eth0.
# NB use something like -s 10.10.10/24 to limit to a specific network.
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# load iptables rules on boot.
iptables-save >/etc/iptables/rules.v4
