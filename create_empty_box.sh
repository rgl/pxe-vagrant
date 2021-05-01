#!/bin/bash
set -eu

rm -rf tmp-empty-box 
mkdir -p tmp-empty-box
pushd tmp-empty-box

# create and add an empty box to the virtualbox provider.
TEMPLATE_BOX=~/.vagrant.d/boxes/ubuntu-20.04-amd64/0/virtualbox
if [ ! -d ~/.vagrant.d/boxes/empty/0/virtualbox ] && [ -d $TEMPLATE_BOX ]; then
echo '{"provider":"virtualbox"}' >metadata.json
VBoxManage createhd --filename empty.vmdk --format VMDK --size 10000
sed -r \
    -e 's,packer-.+-virtualbox-.+?.vmdk,empty.vmdk,' \
    -e 's,([">]packer-.+-virtualbox-)[^"<]+?,\1empty,' \
    $TEMPLATE_BOX/box.ovf \
    >box.ovf
cp $TEMPLATE_BOX/Vagrantfile .
tar cvzf empty.box metadata.json Vagrantfile box.ovf empty.vmdk
VBoxManage closemedium empty.vmdk --delete
vagrant box add --force empty empty.box
fi

# create and add an empty box to the libvirt provider.
TEMPLATE_BOX=~/.vagrant.d/boxes/ubuntu-20.04-amd64/0/libvirt
if [ ! -d ~/.vagrant.d/boxes/empty/0/libvirt ] && [ -d $TEMPLATE_BOX ]; then
rm -f *
cp $TEMPLATE_BOX/Vagrantfile .
echo '{"format":"qcow2","provider":"libvirt","virtual_size":10}' >metadata.json
qemu-img create -f qcow2 box.img 10G
tar cvzf empty.box metadata.json Vagrantfile box.img
vagrant box add --force empty empty.box
fi

popd
rm -rf tmp-empty-box
