variable "volume_uri" {
  description = "URI to the volume"
  type = string
  default = "/var/lib/libvirt/images/kubernetes-vm.qcow2"
}

variable "base_volume_name" {
  description = "Base name of the volume"
  type = string
  default = null
}

variable "base_pool_name" {
  description = "Base name of the pool"
  type = string
  default = null
}

variable "vm_name" {
  description = "Name of the VM"
  type = string
  default = "vm"
}

variable "memory" {
  description = "Memory in MB"
  type = string
  default = "1024"
}

variable "cpu_mode" {
  description = "CPU mode"
  type = string
  default = "host-passthrough"
}

variable "vcpu" {
  description = "Number of vCPUs"
  type = number
  default = 1
}

variable "pool" {
  description = "Name of pool for volumes"
  type = string
  default = "default"
}

variable "system_volume" {
  description = "System volume size in GB"
  type = number
  default = 20
}


