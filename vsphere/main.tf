terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.1.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.7.0"
    }
  }
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = var.winc_datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.winc_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_resource_pool" "pool" {
  name          = var.winc_resource_pool
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.winc_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.winc_vsphere_template
  datacenter_id = data.vsphere_datacenter.dc.id
}

resource "vsphere_virtual_machine" "win_server" {
  count             = var.winc_number_workers
  name              = "${var.winc_instance_name}-${count.index}"
  resource_pool_id  = data.vsphere_resource_pool.pool.id
  datastore_id      = data.vsphere_datastore.datastore.id
  num_cpus          = data.vsphere_virtual_machine.template.num_cpus
  memory            = data.vsphere_virtual_machine.template.memory
  guest_id          = data.vsphere_virtual_machine.template.guest_id
  scsi_type         = data.vsphere_virtual_machine.template.scsi_type
  
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = data.vsphere_virtual_machine.template.disks.0.size
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }

  enable_disk_uuid = true
}


resource "time_sleep" "wait_120_seconds" {
  depends_on = [vsphere_virtual_machine.win_server]
  create_duration = "120s"
}

output "instance_ip" {
  value = vsphere_virtual_machine.win_server[*].default_ip_address
  depends_on = [time_sleep.wait_120_seconds]
}

output "instance_hostname" {
  description = "Hostnames of the Windows instances"
  value       = vsphere_virtual_machine.win_server[*].name
  depends_on  = [time_sleep.wait_120_seconds]
}
