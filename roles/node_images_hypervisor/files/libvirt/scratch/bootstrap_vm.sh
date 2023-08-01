#!/usr/bin/env bash

export DISK=/vms/images/management-x86_64.qcow2
export POOL_NAME=metal-pool
export VM_NAME=management-vm

# Create a cloud-init ISO
xorriso -as genisoimage -output /vms/cloud-init/management-vm/cloud-init.iso -volid CIDATA -joliet -rock /vms/cloud-init/management-vm/user-data /vms/cloud-init/management-vm/meta-data

# Create pool for storage
virsh pool-define-as ${POOL_NAME}
virsh pool-build ${POOL_NAME}
virsh pool-start ${POOL_NAME}
virsh pool-autostart ${POOL_NAME}

# Create a network if needed for local management
# virsh net-create network.xml

# Create a volume
virsh vol-create-as --pool ${POOL_NAME} --name ${VM_NAME}.qcow2 --capacity 20G --format qcow2
virsh vol-upload --pool ${POOL_NAME} ${VM_NAME}.qcow2 ${DISK}

# Create the domain (VM)
virsh create management.xml

# Can also virt-install to create the domain, needs more work
#virt-install --name=management-vm --ram=8192 --vcpus=20 --import --disk path=/vms/images/management-vm.qcow2,format=qcow2 --disk path=/vms/cloud-init/management-vm-cloud-init.iso,device=cdrom --os-variant=sle15 --network   --graphics vnc,listen=0.0.0.0 --noautoconsole
