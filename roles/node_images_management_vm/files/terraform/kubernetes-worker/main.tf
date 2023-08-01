terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
  #uri = "qemu+ssh://root@10.17.37.1"
  uri = "qemu:///system"
}

module "kubernetes" {
  volume_uri = "node-images/output-kubernetes-vm-qemu/kubernetes-vm-x86_64.qcow2"
  source        = "../modules/kubernetes"
  vm_name       = "kubernetes-worker-01"
  memory        = "1024"
  vcpu          = 2
  pool          = "metal-pool"
  system_volume = 100
}

output "ip_addresses" {
  value = module.kubernetes.ip
}