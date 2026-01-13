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
  description = "AWS instance type for Windows nodes"
  type        = string
  default     = "m5a.large"
}

variable "winc_version" {
  description = "Windows Server version for the AMI (2019 or 2022)"
  type        = string
  default     = "2022"
  validation {
    condition     = contains(["2019", "2022"], var.winc_version)
    error_message = "Allowed values for winc_version are '2019' or '2022'."
  }
}

# Infrastructure Configuration
variable "winc_machine_hostname" {
  description = "Hostname of an existing cluster worker node. Can be retrieved with: oc get nodes -l node-role.kubernetes.io/worker --no-headers"
  type        = string
}

variable "winc_region" {
  description = "AWS region for resource deployment"
  type        = string
}

variable "aws_profile" {
  description = "AWS profile to use for authentication (e.g., 'saml' for SAML-based credentials)"
  type        = string
  default     = ""
}

# Authentication Configuration
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