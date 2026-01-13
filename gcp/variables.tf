# Windows Instance Configuration
variable "winc_instance_name" {
  description = "Name prefix for the Windows VM instances"
  type        = string
}

variable "winc_number_workers" {
  description = "Number of BYOH worker instances to create"
  type        = number
  default     = 2
}

variable "winc_instance_type" {
  description = "GCP machine type for Windows instances"
  type        = string
  default     = "n1-standard-4"
}

variable "winc_win_version" {
  description = "Windows Server version for the instances"
  type        = string
  default     = "windows-2022-core"
}

# GCP Infrastructure Configuration
variable "winc_project" {
  description = "GCP project ID"
  type        = string
  # Remove default = "openshift-qe" as it's environment specific
}

variable "winc_region" {
  description = "GCP region for resource deployment"
  type        = string
  # Make it required instead of having a default
}

variable "winc_zone" {
  description = "GCP zone within the specified region"
  type        = string
  # Make it required instead of having a default
}

variable "winc_machine_hostname" {
  description = "Hostname of an existing cluster worker node. Can be retrieved with: oc get nodes -l node-role.kubernetes.io/worker --no-headers"
  type        = string
}

# Authentication and Access Configuration
variable "admin_username" {
  description = "Administrator username for Windows instances"
  type        = string
  default     = "Administrator"
}

variable "admin_password" {
  description = "Administrator password for Windows instances"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for Windows instances authentication"
  type        = string
}

# Networking Configuration
variable "container_logs_port" {
  type        = number
  default     = 10250
  description = "Container logs port for firewall rule"
}