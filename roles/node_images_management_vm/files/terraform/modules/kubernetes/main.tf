terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      version = ">= 0.7.0"
    }
  }
}

resource "libvirt_domain" "test-domain" {
  name = var.vm_name
  memory = var.memory
  vcpu = var.vcpu
  autostart = true
  qemu_agent = true

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  network_interface {
    macvtap = "eth0"
  }

  disk {
    volume_id = libvirt_volume.volume-qcow2.id
  }

  console {
    type = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type = "spice"
    listen_type = "address"
    autoport = true
  }
}

output "ip" {
  value = libvirt_domain.test-domain.network_interface[0]
}