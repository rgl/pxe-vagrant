#!/bin/bash
set -eux

echo 'Defaults env_keep += "DEBIAN_FRONTEND"' >/etc/sudoers.d/env_keep_apt
chmod 440 /etc/sudoers.d/env_keep_apt
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y


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
# get Ubuntu Linux (the PXE bootable version).

mkdir /srv/tftp/ubuntu
wget -qO- http://archive.ubuntu.com/ubuntu/dists/xenial-updates/main/installer-amd64/current/images/netboot/netboot.tar.gz \
  | tar xzv -C /srv/tftp/ubuntu
# test with: atftp --get --local-file pxelinux.0 --remote-file ubuntu/pxelinux.0 127.0.0.1


#
# get Tiny Core Linux.

apt-get install -y --no-install-recommends advancecomp
apt-get install -y --no-install-recommends squashfs-tools
apt-get install -y xz-utils

mkdir /srv/tftp/tcl && pushd /srv/tftp/tcl
TCL_REPOSITORY=http://tinycorelinux.net/7.x/x86_64
# corepure64.gz contains all the files on rootfs64 and modules64 merged together in a single smaller file.
#wget -q $TCL_REPOSITORY/release/distribution_files/{vmlinuz64,corepure64.gz,rootfs64.gz,modules64.gz}
wget -q $TCL_REPOSITORY/release/distribution_files/{vmlinuz64,corepure64.gz}
#zcat corepure64.gz | cpio -vt # list
#zcat corepure64.gz | (mkdir corepure64 && cd corepure64 && sudo cpio -idv --no-absolute-filenames) # extract
# create an extra initrd image that leaves the guest in a state that can be used by vagrant.
# TODO also load .dep files and get all the dependencies. e.g. http://tinycorelinux.net/7.x/x86_64/tcz/openssh.tcz.dep
#      NB when it returns 404 there are no dependencies.
mkdir -p provision/opt
TCE='openssh openssl'
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
# get and configure pxelinux to boot tcl.
# see http://www.syslinux.org/wiki/index.php?title=PXELINUX
# see http://www.syslinux.org/wiki/index.php?title=Config
SYSLINUX=syslinux-6.03
wget -q -P $HOME https://www.kernel.org/pub/linux/utils/boot/syslinux/$SYSLINUX.tar.xz
tar xf $HOME/$SYSLINUX.tar.xz -C $HOME
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
popd


#
# provision the HTTP server.

apt-get install -y --no-install-recommends nginx
rm /etc/nginx/sites-enabled/default
cat>/etc/nginx/sites-available/boot.conf<<'EOF'
server {
  listen 10.10.10.2:80;
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
cat>/etc/dhcp/dhcpd.conf<<'EOF'
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
option routers 10.10.10.2;
subnet 10.10.10.0 netmask 255.255.255.0 {
  range 10.10.10.100 10.10.10.254;
}

# NB we reuse the VirtualBox MAC 08:00:27 (Cadmus Computer Systems) vendor.
#    see https://www.wireshark.org/tools/oui-lookup.html

host ubuntu {
  hardware ethernet 08:00:27:00:00:01;
  filename "ubuntu/pxelinux.0";
}

host tcl {
  hardware ethernet 08:00:27:00:00:02;
  option pxelinux.pathprefix "http://10.10.10.2/tcl/";
  filename "tcl/lpxelinux.0";
}
EOF
sed -i -E 's,^(INTERFACES=).*,\1eth1,' /etc/default/isc-dhcp-server
systemctl restart isc-dhcp-server


#
# setup NAT.
# see https://help.ubuntu.com/community/IptablesHowTo

apt-get install -y iptables

# enable IPv4 forwarding.
sysctl net.ipv4.ip_forward=1
sed -i -E 's,^\s*#?\s*(net.ipv4.ip_forward=).+,\11,g' /etc/sysctl.conf

# NAT through eth0.
# NB use something like -s 10.10.10/24 to limit to a specific network.
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# load iptables rules on boot.
iptables-save >/etc/iptables-rules-v4.conf
cat<<'EOF'>/etc/network/if-pre-up.d/iptables-restore
#!/bin/sh
iptables-restore </etc/iptables-rules-v4.conf
EOF
chmod +x /etc/network/if-pre-up.d/iptables-restore
