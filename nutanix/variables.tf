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

variable "primary_windows_image" {
  description = "Name of the Windows VM template in Nutanix"
  type        = string
  default     = "nutanix-windows-server-openshift.qcow2"
}

# Nutanix Infrastructure Configuration
variable "winc_cluster_name" {
  description = "Name of the Nutanix cluster"
  type        = string
}

variable "subnet_uuid" {
  description = "UUID of the subnet for VM deployment"
  type        = string
}

# Nutanix Authentication Configuration
variable "nutanix_username" {
  description = "Username for Nutanix authentication"
  type        = string
}

variable "nutanix_password" {
  description = "Password for Nutanix authentication"
  type        = string
  sensitive   = true
}

# Windows Authentication Configuration
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