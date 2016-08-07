#!/bin/bash
set -eux

[ -d ~/.vagrant.d/boxes/empty ] && exit 0

rm -rf tmp-empty-box 
mkdir -p tmp-empty-box
pushd tmp-empty-box

TEMPLATE_BOX=~/.vagrant.d/boxes/ubuntu-16.04-amd64/0/virtualbox

echo '{"provider":"virtualbox"}' >metadata.json
VBoxManage createhd --filename empty.vmdk --format VMDK --size 10000
sed -r \
    -e 's,packer-amd64-virtualbox-.+?.vmdk,empty.vmdk,' \
    -e 's,([">]packer-amd64-virtualbox-)[^"<]+?,\1empty,' \
    $TEMPLATE_BOX/box.ovf \
    >box.ovf
cp $TEMPLATE_BOX/Vagrantfile .
tar cvzf empty.box metadata.json Vagrantfile box.ovf empty.vmdk
VBoxManage closemedium empty.vmdk --delete

vagrant box add empty empty.box

popd
rm -rf tmp-empty-box
