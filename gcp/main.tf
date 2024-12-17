terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.40"
    }
  }
  required_version = ">= 1.0.0"
}

# Provider configuration
# Authentication via environment variable:
# GOOGLE_CREDENTIALS (service account key JSON content)
provider "google" {
  project = var.winc_project
  region  = var.winc_region
  zone    = var.winc_zone
}

# Data source for existing worker node
data "google_compute_instance" "winc-machine-node" {
  name = var.winc_machine_hostname
}

# Windows Server instances
resource "google_compute_instance" "vm_instance" {
  count        = var.winc_number_workers
  name         = "${var.winc_instance_name}-${count.index}"
  machine_type = var.winc_instance_type

  # Boot disk configuration
  boot_disk {
    initialize_params {
      size  = 128
      type  = "pd-ssd"
      image = "projects/windows-cloud/global/images/family/${var.winc_win_version}"

      labels = {
        environment = "production"
        managed_by  = "terraform"
      }
    }
  }

  # Instance metadata for Windows configuration
  metadata = {
    sysprep-specialize-script-ps1 = data.template_file.windows-userdata.rendered
  }

  # Network configuration
  network_interface {
    network    = data.google_compute_instance.winc-machine-node.network_interface.0.network
    subnetwork = data.google_compute_instance.winc-machine-node.network_interface.0.subnetwork
  }

  # Service account configuration
  service_account {
    email  = data.google_compute_instance.winc-machine-node.service_account.0.email
    scopes = data.google_compute_instance.winc-machine-node.service_account.0.scopes
  }

  # Inherit tags from worker node
  tags = data.google_compute_instance.winc-machine-node.tags

  # Additional labels
  labels = {
    environment = "production"
    managed_by  = "terraform"
    name        = "${var.winc_instance_name}-${count.index}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Outputs
output "instance_ip" {
  description = "Private IP addresses of the Windows instances"
  value       = google_compute_instance.vm_instance[*].network_interface.0.network_ip
}

output "instance_ids" {
  description = "IDs of the Windows instances"
  value       = google_compute_instance.vm_instance[*].id
}

output "instance_names" {
  description = "Names of the Windows instances"
  value       = google_compute_instance.vm_instance[*].name
}

output "instance_hostname" {
  description = "Hostnames of the Windows instances"
  value       = google_compute_instance.vm_instance[*].name
}