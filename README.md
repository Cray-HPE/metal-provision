# metal-provision (deprecated)

***Deprecated***: The package lists here have moved into Ansible
[node-images](https://github.com/Cray-HPE/node-images/tree/main/metal-provision). The sections below highlight each package manifest file
of interest.

## Base / Common to all images

- [SUSE Packages \(aarch64\)](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/vars/packages/suse.aarch64.yml)
- [SUSE Packages \(x86_64\)](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/vars/packages/suse.x86_64.yml)
- [SUSE Packages](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/vars/packages/suse.yml)

## (CSM) Compute

- [SUSE Packages \(aarch64\)](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/compute/packages.suse.aarch64.yml)
- [SUSE Packages \(x86_64\)](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/compute/packages.suse.x86_64.yml)
- [SUSE Packages](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/compute/packages.suse.yml)

## Kubernetes

- [SUSE Packages](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/kubernetes/packages.suse.yml)
- [SUSE Packages](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/kubernetes_metal/packages.suse.yml)

## NCN Common (common to pre-install-toolkit, kubernetes, and storage-ceph) 

- [SUSE Packages](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/ncn/packages.suse.yml)

## Pre-install toolkit

- [SUSE Packages](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/pre_install_toolkit/packages.suse.yml)

# Storage-CEPH

- [SUSE Packages](https://github.com/Cray-HPE/node-images/blob/main/metal-provision/group_vars/storage_ceph/packages.suse.yml)