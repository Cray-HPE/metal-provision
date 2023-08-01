resource "libvirt_pool" "base-pool-name" {
  name = var.pool
  type = "dir"
  path = "/var/lib/libvirt/${var.pool}"
}

resource "libvirt_volume" "base-volume-qcow2" {
  name = format("${var.vm_name}-base.qcow2")
  pool = libvirt_pool.base-pool-name.name
  source = var.volume_uri
  format = "qcow2"
}

resource "libvirt_volume" "volume-qcow2" {
  name = format("${var.vm_name}.qcow2")
  pool = libvirt_pool.base-pool-name.name
  size = 1024 * 1024 * 1024 * var.system_volume
  base_volume_id = libvirt_volume.base-volume-qcow2.id
  format = "qcow2"
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name = format("${var.vm_name}_init.iso")
  pool = libvirt_pool.base-pool-name.name
  user_data = data.template_file.user_data.rendered
}

data "template_file" "user_data" {
  template = file("${path.module}/templates/cloud_init.cfg")
}